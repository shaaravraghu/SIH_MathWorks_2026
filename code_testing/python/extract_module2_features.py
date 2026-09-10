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


COLS = ["id_code", "diagnosis", "width", "height",
        "vessel_pct", "vessel_comps", "vessel_largest_pct", "vessel_width_med",
        "vessel_skel_len", "vessel_frag", "vessel_coh",
        "od_x", "od_y", "od_bright", "od_struct",
        "ma_count_INVALID", "m2_ok", "m2_reason", "m2_ms"]


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
