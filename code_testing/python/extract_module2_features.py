"""
Module 2 feature extraction -- PARTIAL.

Writes one row per image with the vessel + optic-disc features from the
configurations chosen in notes/.../Module2_Results.md:

    vessels     line detector L=21, W=21, 12 orientations
                threshold calibrated to 11% coverage
                length filter, min length 40 px
                gap bridging (connect-two-components only)
                -> 80.7% in one tree, 8 components
    optic disc  disc-sized mean on RAW green, search r <= 0.60 R
                RAW, not shade-corrected: the disc is 124 px and the background
                window is 60 px, so correction divides the disc out

Usage:
    python extract_module2_features.py <aptos_root> <out.csv> [--ids ids.txt]
                                       [--limit N] [--all]

By default it processes only the IDs that already have measured results (the
round-5 sweep and the functional test).  --all runs the full training set, which
takes 2-4 hours.

Resumable: rows are flushed as computed and existing id_codes are skipped.

CAVEATS carried from the docs -- do not treat these columns as validated:
  * no vessel ground truth exists in APTOS.  ~9% coverage in one dominant tree
    is CONSISTENT WITH a correct segmentation, not proof of one.
  * a correct tree should be >90% in one component; we measure ~81%.
  * the optic disc has ~10% of estimates pinned at its search boundary, so its
    true error rate is unknown.

  * ma_count_INVALID IS EXACTLY WHAT ITS NAME SAYS.  It is the raw candidate
    stage only -- the classifier step of the classical pipeline is NOT
    implemented.  Measured correlation with grade: -0.117, i.e. near zero and
    the WRONG SIGN (grade 1 is DEFINED as "microaneurysms only", so a working
    count must RISE with grade).  It is emitted for completeness.
    DO NOT FEED IT TO A MODEL.
"""
import argparse, csv, gc, os, sys, time, warnings
import numpy as np
from scipy import ndimage as ndi
warnings.filterwarnings("ignore")

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from extract_module1_features import detect_fov, TARGET_R          # noqa: E402
import cv2                                                          # noqa: E402
from PIL import Image                                               # noqa: E402

HALF = int(TARGET_R)
OD_R = int(round(TARGET_R/7.0))
UM = 1850.0/(2*OD_R)
_Y, _X = np.mgrid[0:2*HALF, 0:2*HALF].astype(np.float32)
RRAD = np.hypot(_Y-HALF, _X-HALF)
RET = RRAD <= TARGET_R*0.95
MM = RRAD <= TARGET_R*0.92
OD_SEARCH = RRAD <= TARGET_R*0.60


def load_norm(root, idc):
    p = os.path.join(root, "train_images", idc+".png")
    with Image.open(p) as im:
        I = (np.asarray(im.convert("RGB"), dtype=np.uint8)
             .astype(np.float32))/np.float32(255)
    f, _, _, _ = detect_fov(I, 0.5)
    if f is None:
        return None
    s = TARGET_R/f["R"]
    J = ndi.zoom(I, (s, s, 1), order=1); del I
    pad = HALF+10
    Jp = np.pad(J, ((pad, pad), (pad, pad), (0, 0))); del J
    r0 = int(round(f["cy"]*s+pad))-HALF
    c0 = int(round(f["cx"]*s+pad))-HALF
    K = np.ascontiguousarray(Jp[r0:r0+2*HALF, c0:c0+2*HALF]); del Jp
    K[~RET] = 0
    gc.collect()
    return K


def prep_green(K):
    """Shade-corrected green.  NOT CLAHE -- [F] measured it costs 20% of MA
    contrast and gains nothing for vessels."""
    g = K[:, :, 1].astype(np.float32)
    filled = np.where(RET, g, g[RET].mean())
    sm = ndi.zoom(filled, 1/8, order=1)
    bg = ndi.zoom(ndi.gaussian_filter(sm, 7.5), 8, order=1)[:g.shape[0], :g.shape[1]]
    if bg.shape != g.shape:
        bg = np.pad(bg, ((0, g.shape[0]-bg.shape[0]),
                         (0, g.shape[1]-bg.shape[1])), mode="edge")
    out = np.clip(g/np.maximum(bg, 1e-3)*max(bg[RET].mean(), 1e-3), 0, 1)
    out[~RET] = out[RET].mean()
    return out


def line_detector(I, L=21, W=21, nang=12):
    inv = 1.0-I
    box = cv2.blur(inv, (W, W))
    best = np.full(I.shape, -np.inf, np.float32)
    for a in range(nang):
        se = np.zeros((L, L), np.float32); se[L//2, :] = 1.0
        M = cv2.getRotationMatrix2D((L/2-0.5, L/2-0.5), a*180.0/nang, 1.0)
        k = cv2.warpAffine(se, M, (L, L))
        best = np.maximum(best, cv2.filter2D(inv, -1, k/max(k.sum(), 1e-6)))
    return best-box


def component_lengths(bw):
    """Skeleton length without thinning:  w ~ 4*mean(EDT),  L ~ area/w.
    ~160x faster than Zhang-Suen and vectorised over all components."""
    lab, n = ndi.label(bw)
    if n == 0:
        return np.zeros(0), lab, 0, np.zeros(0)
    flat = lab.ravel()
    area = np.bincount(flat, minlength=n+1)[1:].astype(np.float64)
    edt = ndi.distance_transform_edt(bw)
    esum = np.bincount(flat, weights=edt.ravel(), minlength=n+1)[1:]
    width = 4.0*esum/np.maximum(area, 1)
    return area/np.maximum(width, 1e-6), lab, n, area


def segment_vessels(g, cov=11.0, min_len=40):
    """cov=11.0 matches the round-5 sweep exactly.  It was 10.0, which is why
    the first CSV pass reported vessel_largest_pct 64.1% against the sweep's
    72.4% -- same algorithm, different threshold, incomparable numbers."""
    resp = line_detector(g)
    bw = (resp > np.percentile(resp[MM], 100-cov)) & MM
    bw = ndi.binary_opening(bw, np.ones((2, 2)))
    L, lab, n, area = component_lengths(bw)
    if n == 0:
        return bw
    return np.isin(lab, np.where((L >= min_len) & (area >= 25))[0]+1)


def bridge_gaps(bw, max_gap=9):
    """Reconnect a severed tree by adding ONLY pixels that join two distinct
    pre-existing components.

    The retinal vasculature is anatomically ONE structure -- everything
    emanates from the disc -- so a largest-component share of 72% means the
    mask is severed at faint points, not that the anatomy is fragmented.

    An earlier version kept every pixel that morphological closing added, which
    also linked noise into NEW fragments (components 14 -> 40).  Checking that
    each bridge touches two DIFFERENT original components instead gives
    components 14 -> 8 and largest 62.6% -> 80.7%, with coverage up only 0.1%.
    """
    lab, n = ndi.label(bw)
    if n < 2:
        return bw
    add = np.zeros_like(bw)
    U = bw.astype(np.uint8)
    for a in range(12):
        closed = cv2.morphologyEx(U, cv2.MORPH_CLOSE, line_se(max_gap, a*15.0)) > 0
        add |= closed & ~bw
    if not add.any():
        return bw
    alab, an = ndi.label(add)
    if an == 0:
        return bw
    grown = ndi.grey_dilation(lab, size=(3, 3))
    keep = np.zeros(an+1, bool)
    for i in range(1, an+1):
        t = np.unique(grown[alab == i])
        t = t[t > 0]
        if t.size >= 2:
            keep[i] = True
    return bw | keep[alab]


def vessel_stats(bw, g):
    L, lab, n, area = component_lengths(bw)
    tot = int(bw.sum())
    out = {"vessel_pct": 100.0*tot/MM.sum(), "vessel_comps": int(n),
           "vessel_largest_pct": 100.0*(area.max()/max(tot, 1)) if n else 0.0,
           "vessel_skel_len": float(L.sum()) if n else 0.0}
    out["vessel_frag"] = 1000.0*n/max(out["vessel_skel_len"], 1.0)
    edt = ndi.distance_transform_edt(bw)
    out["vessel_width_med"] = float(2*np.median(edt[bw])) if tot else np.nan
    gx, gy = ndi.sobel(g, 1), ndi.sobel(g, 0)
    Jxx = ndi.gaussian_filter(gx*gx, 2.0); Jyy = ndi.gaussian_filter(gy*gy, 2.0)
    Jxy = ndi.gaussian_filter(gx*gy, 2.0)
    tr = Jxx+Jyy
    dsc = np.sqrt(np.maximum((Jxx-Jyy)**2+4*Jxy*Jxy, 0))
    with np.errstate(all="ignore"):
        coh = np.nan_to_num(dsc/np.maximum(tr, 1e-12))
    out["vessel_coh"] = float(coh[bw].mean()) if tot else np.nan
    return out


def valid_mean(g, size):
    """Window mean counting ONLY retina pixels, so the black surround does not
    drag the average down near the rim."""
    m = RET.astype(np.float32)
    return ndi.uniform_filter(g*m, size)/np.maximum(ndi.uniform_filter(m, size), 1e-6)


def raw_green(K):
    """Green channel, NOT shade-corrected, surround filled with the interior
    mean.  Use this for the optic disc -- see locate_od."""
    g = K[:, :, 1].astype(np.float32).copy()
    g[~RET] = g[RET].mean()
    return g


def locate_od(g):
    """Disc-sized mean on green, search r <= 0.60 R.  The search region did more
    than any detector refinement (median 0.546 R -> 0.445 R).

    PASS RAW GREEN, NOT SHADE-CORRECTED GREEN.

    The shade corrector estimates the illumination field with a sigma=60 px
    Gaussian, but the optic disc is 124 px across -- so the disc partially
    survives into the "field" and gets divided out.  Module1_C_Illumination.md
    warns about exactly this ("window must comfortably exceed the optic disc").

    Measured on 14 images: shade correction drops od_bright from 2.99 to 1.87
    (-37%) on every image, and on one it moved the detection 465 px.

    Vessels are unaffected -- at 3-10 px they are far below the 60 px window --
    so vessels still use the shade-corrected channel.
    """
    B = valid_mean(g, OD_R)
    T = B.copy(); T[~OD_SEARCH] = -np.inf
    cy, cx = divmod(int(np.argmax(T)), T.shape[1])
    dd = np.hypot(_Y-cy, _X-cx)
    core = (dd <= OD_R) & RET
    ring = (dd > OD_R*2.0) & (dd <= OD_R*3.5) & RET
    if core.sum() < 200 or ring.sum() < 200:
        return cy, cx, np.nan, np.nan
    bright = (g[core].mean()-g[ring].mean())/max(g[ring].std(), 1e-6)
    struct = g[core].std()/max(g[ring].std(), 1e-6)
    return cy, cx, float(bright), float(struct)


def line_se(L, deg):
    se = np.zeros((L, L), np.uint8); se[L//2, :] = 1
    M = cv2.getRotationMatrix2D((L/2-0.5, L/2-0.5), deg, 1.0)
    return (cv2.warpAffine(se, M, (L, L)) > 0).astype(np.uint8)


MA_MAX_A = np.pi*(125.0/UM/2)**2
HEM_MAX_A = np.pi*(34.0/2)**2          # 500 um, the DME zone radius
DD = 2*OD_R                            # one disc diameter, 124 px

# The SECOND quality gate.  Module 1's gate decides whether an image is worth
# KEEPING; this decides whether it is sharp enough to COUNT LESIONS on.
#
# Derived on 250 images sampled across all 10 sharpness deciles x 5 grades.
# There is a step change between the 40th and 50th percentile of varLapNorm,
# not a smooth gradient -- which is why a cut is the right shape of fix:
#
#   cut    keeps   hem_n   q_max        (within-stratum rho above the cut)
#   0.069   60%    0.194   0.131
#   0.082   50%    0.387   0.335   <- SHARP_MIN
#   0.097   40%    0.437   0.404
#
# IMPORTANT -- this gate is NOT global.  It helps the dark-lesion features and
# does nothing for exudates (exu_n is ~0 at every cut).  It actively HURTS
# nv_fine, which measures +0.394 on all images and +0.035 above the 70th
# percentile.  Apply it to hem_n / ma_n / q_min / q_max / rule421 only.
SHARP_MIN = 0.082


def min_close(U, L, nang=12):
    """Minimum over closings by line SEs at nang orientations.  A structure is
    filled only if some line BRIDGES it, so L sets the largest lesion the
    difference image can see: L=15 for microaneurysms, L=41 for haemorrhages."""
    C = None
    for a in range(nang):
        c = cv2.morphologyEx(U, cv2.MORPH_CLOSE, line_se(L, a*180.0/nang))
        C = c if C is None else np.minimum(C, c)
    return C


def ma_count_raw(g, vessel, L=15, nang=12, dil=3):
    """RAW CANDIDATE STAGE ONLY -- the classifier step is not implemented.
    Currently correlates -0.117 with grade (near zero, wrong sign).  Written
    for completeness; DO NOT use as a feature yet."""
    U = (np.clip(g, 0, 1)*255).astype(np.uint8)
    Cmin = None
    for a in range(nang):
        C = cv2.morphologyEx(U, cv2.MORPH_CLOSE, line_se(L, a*180.0/nang))
        Cmin = C if Cmin is None else np.minimum(Cmin, C)
    diff = (Cmin.astype(np.float32)-U.astype(np.float32))/255.0
    if vessel is not None:
        diff[ndi.binary_dilation(vessel, np.ones((3, 3)), iterations=dil)] = 0
    diff[~MM] = 0
    if not np.any(diff > 0):
        return 0
    cand = diff > max(np.percentile(diff[MM], 99.5), 1e-4)
    lab, n = ndi.label(cand)
    if n == 0:
        return 0
    cnt = np.bincount(lab.ravel()); cnt[0] = 0
    return int(np.sum((cnt >= 3) & (cnt <= MA_MAX_A)))


def locate_fovea(g, vessel, od):
    """Darkest centre-surround response, penalised by local vessel density
    (the fovea is avascular), searched only in the 2.1-2.9 DD annulus around
    the optic disc.  See Module2_Fovea_Localization.md."""
    G = g.astype(np.float32)
    cs = ndi.uniform_filter(G, 161)-ndi.uniform_filter(G, 41)
    vd = ndi.uniform_filter(vessel.astype(np.float32), 81)
    dist = np.hypot(_Y-od[0], _X-od[1])
    ann = MM & (dist > 2.1*DD) & (dist < 2.9*DD)
    if not ann.any():
        return od[0], od[1], 0.0
    sc = np.where(ann, cs-3.0*vd, -np.inf)
    fy, fx = np.unravel_index(np.argmax(sc), sc.shape)
    # Report density over the foveal avascular zone (500 um = 34 px radius),
    # NOT vd[fy,fx].  The search maximises `cs - 3.0*vd`, so the argmax always
    # lands on a strictly zero-vessel pixel and vd at that point is identically
    # 0.0 on every image -- a constant, not a measurement.
    faz = np.hypot(_Y-fy, _X-fx) <= 34.0
    dens = float(100.0*vessel[faz & MM].mean()) if (faz & MM).any() else 0.0
    return int(fy), int(fx), dens


def exudates(g, od, min_area=8):
    """Bright lesions.  The whole fix was the min-area filter: without it this
    returns 1,244-2,279 specks per image and rho -0.196; with it, 1.5-47 per
    image and rho +0.503.  See Module2_Exudates.md."""
    G = g.astype(np.float32)
    bg = ndi.uniform_filter(G, 81)
    diff = G-bg
    diff[np.hypot(_Y-od[0], _X-od[1]) < 0.9*OD_R] = 0     # mask the disc itself
    diff[~MM] = 0
    if not np.any(diff > 0):
        return 0, 0.0
    bw = diff > max(np.percentile(diff[MM], 99.0), 1e-4)
    lab, n = ndi.label(bw)
    if n == 0:
        return 0, 0.0
    cnt = np.bincount(lab.ravel()); cnt[0] = 0
    keep = cnt >= min_area
    return int(keep.sum()), float(100.0*cnt[keep].sum()/MM.sum())


HEM_FEATS = ["area", "perim", "circ", "ecc", "solidity", "aspect", "contrast",
             "rg", "diff_rel", "vdist", "vdens", "rad"]
_HEM_MODEL = None


def _hem_model():
    global _HEM_MODEL
    if _HEM_MODEL is None:
        import joblib
        p = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "models", "hem_candidate_rf.joblib")
        _HEM_MODEL = joblib.load(p) if os.path.exists(p) else False
    return _HEM_MODEL


def hem_candidates(K, g, vessel, L=41, pct=96.0, dil=3):
    """Scale-matched closing, then per-candidate features.  Returns the feature
    matrix and centroids -- the classifier is a separate step because the
    threshold stage alone gives 80 'haemorrhages' on a normal retina."""
    U = (np.clip(g, 0, 1)*255).astype(np.uint8)
    diff = (min_close(U, L).astype(np.float32)-U.astype(np.float32))/255.0
    diff[ndi.binary_dilation(vessel, np.ones((3, 3)), iterations=dil)] = 0
    diff[~MM] = 0
    if not np.any(diff > 0):
        return np.zeros((0, len(HEM_FEATS)), np.float32), np.zeros((0, 2))
    bw = ndi.binary_closing(diff > max(np.percentile(diff[MM], pct), 1e-4),
                            np.ones((5, 5)))
    lab, n = ndi.label(bw)
    if n == 0:
        return np.zeros((0, len(HEM_FEATS)), np.float32), np.zeros((0, 2))
    vdist = ndi.distance_transform_edt(~vessel)
    vdens = ndi.uniform_filter(vessel.astype(np.float32), 60)
    R_, G_ = K[:, :, 0], K[:, :, 1]
    dm = max(diff[MM].mean(), 1e-9)
    h, wid = g.shape
    rows, cents = [], []
    for i, sl in enumerate(ndi.find_objects(lab), start=1):
        m = lab[sl] == i
        a = int(m.sum())
        if a < MA_MAX_A or a > HEM_MAX_A:
            continue
        ys, xs = np.nonzero(m)
        cy = sl[0].start+ys.mean(); cx = sl[1].start+xs.mean()
        per = int(np.sum(m & ~ndi.binary_erosion(m)))
        y0, x0 = ys-ys.mean(), xs-xs.mean()
        cov = np.cov(np.stack([x0, y0])) if a > 2 else np.eye(2)
        ev = np.sort(np.linalg.eigvalsh(cov+1e-9*np.eye(2)))
        # local contrast window -- a full-image distance map per candidate cost
        # 2.9 s/image with a few hundred candidates; a 26 px crop is identical
        # arithmetic on ~0.3% of the pixels.
        iy, ix = int(cy), int(cx)
        y1, y2 = max(iy-26, 0), min(iy+27, h)
        x1, x2 = max(ix-26, 0), min(ix+27, wid)
        dd = np.hypot(_Y[y1:y2, x1:x2]-cy, _X[y1:y2, x1:x2]-cx)
        gw, mw = g[y1:y2, x1:x2], MM[y1:y2, x1:x2]
        core = dd <= max(np.sqrt(a/np.pi), 2.0)
        ring = (dd > 12) & (dd <= 24) & mw
        rows.append([
            a, per, 4*np.pi*a/max(per*per, 1),
            float(np.sqrt(max(1-ev[0]/max(ev[1], 1e-9), 0))),
            a/max(m.shape[0]*m.shape[1], 1),
            float(m.shape[1]/max(m.shape[0], 1)),
            float(gw[ring].mean()-gw[core].mean()) if ring.sum() > 40 else 0.0,
            float(R_[sl][m].mean()/max(G_[sl][m].mean(), 1e-6)),   # ratio only
            float(diff[sl][m].mean()/dm),
            float(vdist[int(cy), int(cx)]), float(vdens[int(cy), int(cx)]),
            float(np.hypot(cy-h/2, cx-wid/2)/(h/2))])
        cents.append([cy, cx])
    return (np.asarray(rows, np.float32).reshape(-1, len(HEM_FEATS)),
            np.asarray(cents, np.float32).reshape(-1, 2))


def hem_and_quadrants(K, g, vessel, od, fov):
    """Classify candidates, then bin the survivors into quadrants on the
    OD-fovea axis and apply the 4-2-1 rule.  Threshold recalibrated from the
    textbook's 20 to 5 -- see Module2_Haemorrhages_NV_Quadrants.md."""
    X, cents = hem_candidates(K, g, vessel)
    out = dict(hem_raw=len(X), hem_n=0, q_min=0, q_max=0, rule421=0)
    mdl = _hem_model()
    if len(X) == 0 or not mdl:
        return out
    # Threshold 0.8, not 0.5.  The forest is fitted on a 70.7%-positive weak
    # label set, so its posterior is skewed; at 0.5 it kept ~100% of candidates
    # on unseen images and fired the 4-2-1 rule on a grade-0 retina.  0.8 is
    # the point at which the grade-0 median count reaches ZERO, which is the
    # clinically correct value for a no-DR eye.
    keep = mdl["model"].predict_proba(X)[:, 1] >= mdl.get("threshold", 0.8)
    out["hem_n"] = int(keep.sum())
    if not keep.any():
        return out
    c = cents[keep]
    ax = np.arctan2(fov[0]-od[0], fov[1]-od[1])
    ang = np.mod(np.arctan2(c[:, 0]-od[0], c[:, 1]-od[1])-ax, 2*np.pi)
    q = np.bincount(np.clip((ang//(np.pi/2)).astype(int), 0, 3), minlength=4)
    # The textbook rule is ">20 haemorrhages in each of four quadrants".  That
    # constant assumes a clinician on a dilated seven-field exam; on a single
    # 45-degree field it fires on nothing at any grade.  Re-derived against this
    # detector: >3 gives 93% specificity at grades 0-2 and 64% sensitivity at
    # grades 3-4.  q_min and q_max are stored raw so the constant can be
    # refitted on the full dataset without re-extracting.
    out.update(q_min=int(q.min()), q_max=int(q.max()),
               rule421=int(q.min() > 3))
    return out


_MA_MODEL = None


def _ma_model():
    global _MA_MODEL
    if _MA_MODEL is None:
        import joblib
        p = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         "models", "ma_candidate_rf.joblib")
        _MA_MODEL = joblib.load(p) if os.path.exists(p) else False
    return _MA_MODEL


def ma_candidates(K, g, vessel, L=15, pct=99.0, dil=3):
    """Microaneurysm candidates: same five-step pipeline as haemorrhages but a
    SHORTER structuring element (L=15, the 125 um / 8.4 px lesion class) and a
    tighter area window.  Features are identical to the haemorrhage set so the
    two classifiers stay comparable."""
    U = (np.clip(g, 0, 1)*255).astype(np.uint8)
    diff = (min_close(U, L).astype(np.float32)-U.astype(np.float32))/255.0
    diff[ndi.binary_dilation(vessel, np.ones((3, 3)), iterations=dil)] = 0
    diff[~MM] = 0
    if not np.any(diff > 0):
        return np.zeros((0, len(HEM_FEATS)), np.float32)
    lab, n = ndi.label(diff > max(np.percentile(diff[MM], pct), 1e-4))
    if n == 0:
        return np.zeros((0, len(HEM_FEATS)), np.float32)
    vdist = ndi.distance_transform_edt(~vessel)
    vdens = ndi.uniform_filter(vessel.astype(np.float32), 60)
    R_, G_ = K[:, :, 0], K[:, :, 1]
    dm = max(diff[MM].mean(), 1e-9)
    h, wid = g.shape
    rows = []
    for i, sl in enumerate(ndi.find_objects(lab), start=1):
        m = lab[sl] == i
        a = int(m.sum())
        if a < 3 or a > MA_MAX_A:
            continue
        ys, xs = np.nonzero(m)
        cy = sl[0].start+ys.mean(); cx = sl[1].start+xs.mean()
        per = int(np.sum(m & ~ndi.binary_erosion(m)))
        y0, x0 = ys-ys.mean(), xs-xs.mean()
        cov = np.cov(np.stack([x0, y0])) if a > 2 else np.eye(2)
        ev = np.sort(np.linalg.eigvalsh(cov+1e-9*np.eye(2)))
        iy, ix = int(cy), int(cx)
        y1, y2 = max(iy-26, 0), min(iy+27, h)
        x1, x2 = max(ix-26, 0), min(ix+27, wid)
        dd = np.hypot(_Y[y1:y2, x1:x2]-cy, _X[y1:y2, x1:x2]-cx)
        gw, mw = g[y1:y2, x1:x2], MM[y1:y2, x1:x2]
        core = dd <= max(np.sqrt(a/np.pi), 2.0)
        ring = (dd > 12) & (dd <= 24) & mw
        rows.append([
            a, per, 4*np.pi*a/max(per*per, 1),
            float(np.sqrt(max(1-ev[0]/max(ev[1], 1e-9), 0))),
            a/max(m.shape[0]*m.shape[1], 1),
            float(m.shape[1]/max(m.shape[0], 1)),
            float(gw[ring].mean()-gw[core].mean()) if ring.sum() > 40 else 0.0,
            float(R_[sl][m].mean()/max(G_[sl][m].mean(), 1e-6)),
            float(diff[sl][m].mean()/dm),
            float(vdist[iy, ix]), float(vdens[iy, ix]),
            float(np.hypot(cy-h/2, cx-wid/2)/(h/2))])
    return np.asarray(rows, np.float32).reshape(-1, len(HEM_FEATS))


def ma_classified(K, g, vessel):
    """The count to use.  `ma_count_INVALID` is the threshold stage alone and
    correlates -0.117 with grade; this applies the candidate classifier."""
    X = ma_candidates(K, g, vessel)
    mdl = _ma_model()
    if len(X) == 0 or not mdl:
        return len(X), 0
    p = mdl["model"].predict_proba(X)[:, 1]
    return len(X), int((p >= mdl.get("threshold", 0.8)).sum())


def nv_fine(g, vessel_unused=None):
    """Neovascular vessels are THIN.  Detect at fine and coarse scale; NV is
    what responds to fine but not coarse.  within-stratum rho +0.356, positive
    in all four resolution strata.  PARTIAL: never validated against real NV
    annotations, which APTOS does not have."""
    fine = line_detector(g, 9, 11)
    coarse = line_detector(g, 31, 31)
    fm = (fine > np.percentile(fine[MM], 92)) & MM
    cm = (coarse > np.percentile(coarse[MM], 92)) & MM
    ex = fm & ~ndi.binary_dilation(cm, np.ones((5, 5)))
    return (float(100.0*ex.sum()/MM.sum()),
            float(ndi.uniform_filter(ex.astype(np.float32), int(DD))[MM].max()))


COLS = ["id_code", "diagnosis", "width", "height",
        "vessel_pct", "vessel_comps", "vessel_largest_pct", "vessel_width_med",
        "vessel_skel_len", "vessel_frag", "vessel_coh",
        "od_x", "od_y", "od_bright", "od_struct",
        "fovea_x", "fovea_y", "fovea_vdens", "fovea_od_dd",
        "exu_n", "exu_area",
        "ma_raw", "ma_n",
        "hem_raw", "hem_n", "q_min", "q_max", "rule421",
        "nv_fine", "nv_fine_max",
        "sharp_ok", "ma_count_INVALID", "m2_ok", "m2_reason", "m2_ms"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("out")
    ap.add_argument("--ids", default=None, help="text file, one id_code per line")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--all", action="store_true")
    a = ap.parse_args()

    import pandas as pd
    m1 = pd.read_csv(os.path.join(os.path.dirname(a.out),
                                  "aptos_train_module1_features.csv"))
    m1 = m1[(m1.fov_ok == 1) & (m1.gate_reject == 0)]

    if a.ids and os.path.exists(a.ids):
        want = [l.strip() for l in open(a.ids) if l.strip()]
        m1 = m1[m1.id_code.isin(want)]
    elif not a.all:
        print("no --ids and no --all: nothing to do")
        return
    if a.limit:
        m1 = m1.head(a.limit)

    done = set()
    if os.path.exists(a.out):
        with open(a.out, newline="") as fh:
            done = {r["id_code"] for r in csv.DictReader(fh)}
        print(f"resuming: {len(done)} rows already present")

    fh = open(a.out, "a", newline="")
    w = csv.DictWriter(fh, fieldnames=COLS)
    if not done:
        w.writeheader()

    print(f"{len(m1)} images to process", flush=True)
    t0 = time.time(); nok = 0
    for i, (_, r) in enumerate(m1.iterrows()):
        if r.id_code in done:
            continue
        row = {c: "" for c in COLS}
        row.update(id_code=r.id_code, diagnosis=r.get("diagnosis", ""),
                   width=r.get("width", ""), height=r.get("height", ""))
        ti = time.perf_counter()
        try:
            K = load_norm(a.root, r.id_code)
            if K is None:
                row.update(m2_ok=0, m2_reason="fov_failed")
            else:
                g = prep_green(K)              # shade-corrected: vessels
                v = bridge_gaps(segment_vessels(g)) & MM
                row.update(vessel_stats(v, g))
                cy, cx, br, st = locate_od(raw_green(K))   # RAW: optic disc
                row.update(od_x=cx, od_y=cy, od_bright=br, od_struct=st)
                fy, fx, fvd = locate_fovea(g, v, (cy, cx))
                row.update(fovea_x=fx, fovea_y=fy, fovea_vdens=fvd,
                           fovea_od_dd=round(float(np.hypot(fy-cy, fx-cx)/DD), 4))
                en, ea = exudates(g, (cy, cx))
                row.update(exu_n=en, exu_area=ea)
                mr, mn = ma_classified(K, g, v)
                row.update(ma_raw=mr, ma_n=mn)
                row.update(hem_and_quadrants(K, g, v, (cy, cx), (fy, fx)))
                nf, nfm = nv_fine(g)
                row.update(nv_fine=nf, nv_fine_max=nfm)
                # Module 1's gate accepts images on which the lesion counts
                # reverse sign against grade.  sharp_ok is the SECOND, stricter
                # gate: accepting an image for storage and accepting it for
                # lesion counting are different decisions.
                row["sharp_ok"] = int(float(r.get("varLapNorm", 0)) >= SHARP_MIN)
                row["ma_count_INVALID"] = ma_count_raw(g, v)
                row.update(m2_ok=1, m2_reason="ok")
                nok += 1
                del K, g, v
            gc.collect()
        except Exception as e:
            row.update(m2_ok=0, m2_reason=f"{type(e).__name__}:{str(e)[:50]}")
        row["m2_ms"] = round((time.perf_counter()-ti)*1000, 1)
        for k, val in row.items():
            if isinstance(val, float) and np.isfinite(val):
                row[k] = round(val, 5)
            elif isinstance(val, float):
                row[k] = ""
        w.writerow(row); fh.flush()
        if (i+1) % 20 == 0:
            el = time.time()-t0
            print(f"  {i+1}/{len(m1)}  ok={nok}  {el:.0f}s  "
                  f"({el/(i+1):.2f}s/img)", flush=True)
    fh.close()
    print(f"\ndone: {nok} succeeded, {time.time()-t0:.0f}s -> {a.out}")


if __name__ == "__main__":
    main()
