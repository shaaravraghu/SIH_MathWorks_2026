"""
Extract every Module 1 [A]+[B] feature for the APTOS 2019 dataset.

Produces a duplicate of train.csv with ~45 extra columns: FOV geometry
(centre, radius, black-background %, clipping), per-channel exposure, and all
ten focus/sharpness metrics.

This is the Python reference implementation of matlab/detectFOV.m,
normalizeFundus.m and focusMetrics.m -- kept in-repo because the MATLAB
Image Processing Toolbox is not installed (see notes/docs/Module1_Feature_Reference.md).

Usage:
    python extract_module1_features.py <aptos_root> <out.csv> [--split train|test] [--limit N] [--scale 0.5]

Notes:
  * FOV detection runs at --scale (default 0.5): 4.4x faster, median radius
    error 0.83 px.  Geometry is rescaled back to full-resolution pixels.
  * Focus metrics run on the RADIUS-NORMALISED image (R=436) at FULL
    resolution -- never downsampled, because downsampling is a low-pass
    filter and would destroy the very signal being measured.
  * Rows are flushed as they are computed, so the run is resumable and a
    crash does not lose work.
"""
import argparse, csv, gc, os, sys, time, warnings
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

warnings.filterwarnings("ignore")
Image.MAX_IMAGE_PIXELS = None

DISK = np.zeros((11, 11), bool)
_y, _x = np.ogrid[-5:6, -5:6]
DISK[_y**2 + _x**2 <= 25] = True

TARGET_R = 436.0


# ----------------------------------------------------------------- [A]
def otsu(x):
    h, e = np.histogram(x.ravel(), 256, (0, 1))
    h = h / max(h.sum(), 1)
    c = np.cumsum(h)
    m = np.cumsum(h * ((e[:-1] + e[1:]) / 2))
    mt = m[-1]
    with np.errstate(all="ignore"):
        sb = np.nan_to_num((mt * c - m) ** 2 / (c * (1 - c)))
    k = int(sb.argmax())
    return (e[k] + e[k + 1]) / 2


def kasa(x, y):
    A = np.column_stack([2 * x, 2 * y, np.ones(len(x))])
    s, *_ = np.linalg.lstsq(A, x**2 + y**2, rcond=None)
    return s[0], s[1], np.sqrt(max(s[2] + s[0] ** 2 + s[1] ** 2, 0))


def try_threshold(Ir, t):
    """Mirror of MATLAB tryThreshold. Returns (dict|None, reason)."""
    H, W = Ir.shape
    bw = Ir > t
    if bw.sum() < 100:
        return None, "empty_after_thresh"
    lab, n = ndi.label(bw)
    if n == 0:
        return None, "no_components"
    # bincount, not ndi.sum -- ndi.sum upcasts to float64 and OOMs on a
    # memory-constrained machine.
    cnt = np.bincount(lab.ravel())
    cnt[0] = 0
    bw = lab == int(cnt.argmax())
    del lab, cnt
    bw = ndi.binary_fill_holes(bw)
    bw = ndi.binary_fill_holes(ndi.binary_opening(bw, DISK))
    if bw.mean() > 0.98:
        return None, "mask_gt_98pct"
    if bw.sum() < 100:
        return None, "too_small_after_open"

    bnd = bw & ~ndi.binary_erosion(bw)
    ys, xs = np.nonzero(bnd)
    if len(ys) < 50:
        return None, "too_few_boundary"
    on = (ys <= 2) | (ys >= H - 3) | (xs <= 2) | (xs >= W - 3)
    if (~on).sum() > 50:
        fx, fy = xs[~on].astype(np.float64), ys[~on].astype(np.float64)
    else:
        fx, fy = xs.astype(np.float64), ys.astype(np.float64)
    try:
        cx, cy, R = kasa(fx, fy)
        if not np.isfinite(R) or R < 0.05 * min(H, W) or R > 3 * max(H, W):
            return None, "R_out_of_range"
        res = np.abs(np.hypot(fx - cx, fy - cy) - R)
        keep = res < max(5, 3 * np.median(res))
        if keep.sum() > 50:
            cx, cy, R = kasa(fx[keep], fy[keep])
        if not np.isfinite(R) or R < 0.05 * min(H, W) or R > 3 * max(H, W):
            return None, "R_out_of_range2"
    except Exception as e:
        return None, "fit_exception:" + type(e).__name__

    A, P = int(bw.sum()), len(ys)
    return dict(
        mask=bw, cx=cx, cy=cy, R=R,
        residual=float(np.abs(np.hypot(fx - cx, fy - cy) - R).mean() / R),
        raggedness=float(P / (2 * np.pi * R)),
        circularity=float(4 * np.pi * A / P**2),
        areaFrac=float(A / (np.pi * R * R)),
        borderFrac=float(on.mean()),
        maskPx=A,
    ), "ok"


def detect_fov(I, scale=1.0):
    """I: float32 HxWx3 in [0,1]. Returns (dict|None, reason, degenerate, retried)."""
    full_h, full_w = I.shape[:2]
    Ir = I[:, :, 0]
    degenerate = False
    if Ir.std() < 0.01:
        Ir = I.max(2)
        degenerate = True
    if scale < 1.0:
        Ir = ndi.zoom(Ir, scale, order=1)

    f, why = try_threshold(Ir, otsu(Ir))
    retried = False
    need = (f is None) or f["raggedness"] > 1.4 or f["areaFrac"] < 0.15 or f["areaFrac"] > 1.6
    if need:
        pos = Ir[Ir > 0.02]
        if pos.size:
            alt, why2 = try_threshold(Ir, 0.5 * float(pos.mean()))
            if alt is not None and (f is None or alt["raggedness"] < f["raggedness"]):
                f, why, retried = alt, why2, True
            elif f is None:
                why = f"otsu:{why}/fallback:{why2}"
    if f is None:
        return None, why, degenerate, retried

    if scale < 1.0:
        f["mask"] = ndi.zoom(f["mask"].astype(np.uint8), (full_h / f["mask"].shape[0],
                                                          full_w / f["mask"].shape[1]),
                             order=0).astype(bool)
        f["cx"] /= scale
        f["cy"] /= scale
        f["R"] /= scale
        f["maskPx"] = int(f["mask"].sum())

    f["offset"] = float(np.hypot(f["cx"] - full_w / 2, f["cy"] - full_h / 2) / f["R"])
    return f, "ok", degenerate, retried


# ----------------------------------------------------------------- [B]
def focus_metrics(Ig, M, cy, cx, R):
    L = ndi.laplace(Ig)
    gx, gy = ndi.sobel(Ig, 1), ndi.sobel(Ig, 0)
    gm = np.sqrt(gx**2 + gy**2)
    ML = (np.abs(2 * Ig - np.roll(Ig, 1, 1) - np.roll(Ig, -1, 1)) +
          np.abs(2 * Ig - np.roll(Ig, 1, 0) - np.roll(Ig, -1, 0)))
    K = np.array([[1.0, -2, 1], [-2, 4, -2], [1, -2, 1]])
    vI = max(Ig[M].var(), 1e-12)

    d = dict(
        varLap=float(L[M].var()),
        varLapNorm=float(L[M].var() / vI),
        sml=float(ML[M].mean()),
        tenengrad=float((gx**2 + gy**2)[M].mean()),
        tenengradVar=float(gm[M].var()),
        brenner=float(((np.roll(Ig, -2, 1) - Ig) ** 2)[M].mean()),
        noiseSigma=float(np.sqrt(np.pi / 2) * np.abs(ndi.convolve(Ig, K)[M]).mean() / 6),
        specSlope=spectral_slope(Ig, cy, cx, R),
    )

    H, W = M.shape
    yy, xx = np.mgrid[0:H, 0:W]
    rr = np.hypot(yy - cy, xx - cx)
    ang = np.degrees(np.arctan2(-(yy - cy), xx - cx)) % 360
    regs = [M & (rr < 0.4 * R)]
    for k in range(4):
        regs.append(M & (rr >= 0.4 * R) & (ang >= k * 90) & (ang < (k + 1) * 90))
    vals = []
    for r in regs:
        vals.append(L[r].var() / max(Ig[r].var(), 1e-12) if r.sum() > 100 else np.nan)
    v = np.array(vals, float)
    d["regionMin"] = float(np.nanmin(v)) if np.isfinite(v).any() else np.nan
    d["regionCV"] = float(np.nanstd(v) / np.nanmean(v)) if np.isfinite(v).any() else np.nan
    for i in range(5):
        d[f"region{i+1}"] = float(v[i])
    return d


def spectral_slope(x, cy, cx, R):
    half = int(0.45 * R)
    r0, r1 = max(0, int(cy) - half), min(x.shape[0], int(cy) + half)
    c0, c1 = max(0, int(cx) - half), min(x.shape[1], int(cx) + half)
    C = x[r0:r1, c0:c1]
    if min(C.shape) < 64:
        return float("nan")
    C = C - C.mean()
    C = C * np.outer(np.hanning(C.shape[0]), np.hanning(C.shape[1]))
    P = np.abs(np.fft.fftshift(np.fft.fft2(C))) ** 2
    h, w = P.shape
    yy, xx = np.mgrid[0:h, 0:w]
    rad = np.hypot(yy - h / 2, xx - w / 2).astype(int)
    prof = np.bincount(rad.ravel(), P.ravel()) / np.maximum(np.bincount(rad.ravel()), 1)
    lo, hi = 6, min(120, len(prof))
    if hi <= lo + 5:
        return float("nan")
    fr = np.arange(lo, hi)
    return float(-np.polyfit(np.log(fr), np.log(prof[lo:hi] + 1e-20), 1)[0])


# ----------------------------------------------------------------- [C]
def colour_metric(I, M):
    """colorSat -- must be measured on the ORIGINAL image.

    Resampling blends clipped and unclipped pixels, so anything derived from
    the top of the range has to be read before normalisation.

    Computed over masked pixels only (1-D vectors), never as full-frame
    temporaries -- full-resolution APTOS images OOM on a constrained machine.
    """
    r = I[:, :, 0][M]
    g = I[:, :, 1][M]
    b = I[:, :, 2][M]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    del r, g, b
    with np.errstate(all="ignore"):
        sat = (mx - mn) / np.maximum(mx, 1e-9)
    return {"colorSat": float(sat.mean())}


def field_metrics(J, MM, R=TARGET_R):
    """Background field, tilt and local contrast on the RADIUS-NORMALISED image.

    Normalising first is what makes these comparable across cameras: a 15 px
    contrast window means the same anatomical scale in every image only once
    the retinal radius is fixed. It also bounds memory -- J is 872x872
    regardless of whether the source was 640x480 or 4288x2848.

    See notes/docs/Module1_C_Illumination.md.
    """
    out = {}

    # --- background field: downsample -> median -> statistics -------------
    # The illumination field is smooth by definition, so 1/16 scale loses none
    # of it, and a 176 px median at full resolution is ~250x slower.
    F = 16
    small = ndi.zoom(J, 1.0 / F, order=1)
    msmall = ndi.zoom(MM.astype(np.float32), 1.0 / F, order=1) > 0.5
    if msmall.sum() < 50:
        msmall = np.ones_like(small, bool)

    # Hold the outside at the interior median. Leaving the black surround at
    # ~0 drags the field down near the rim and manufactures a falloff that is
    # not optical.
    filled = small.copy()
    filled[~msmall] = np.median(small[msmall])

    # Window must comfortably exceed the optic disc (~0.29R across), or the
    # disc survives into the "illumination" field and flat-fielding dims it.
    win = max(5, int(2 * round(0.5 * 0.4 * R / F) + 1))
    L = ndi.median_filter(filled, size=win, mode="nearest")
    del filled, small

    Lm = L[msmall]
    out["bgMean"] = float(Lm.mean())
    out["bgCV"] = float(Lm.std() / max(Lm.mean(), 1e-9))
    p5, p95 = np.percentile(Lm, [5, 95])
    out["bgSpread"] = float(p95 - p5)

    # --- plane + radial fit ------------------------------------------------
    # Symmetric falloff is normal vignetting; asymmetric tilt is a fault.
    # Separating them needs two fits, not one.
    cyx = (L.shape[0] / 2.0, L.shape[1] / 2.0)
    ys, xs = np.nonzero(msmall)
    X = (xs - cyx[1]) * F / R      # scale-free: same meaning at R=400 and 1800
    Y = (ys - cyx[0]) * F / R
    try:
        sol, *_ = np.linalg.lstsq(np.column_stack([X, Y, np.ones(X.size)]), Lm, rcond=None)
        out["bgTiltMag"] = float(np.hypot(sol[0], sol[1]))
        out["bgTiltDir"] = float(np.degrees(np.arctan2(sol[1], sol[0])))
        rad = np.hypot(X, Y)
        sr, *_ = np.linalg.lstsq(np.column_stack([rad, np.ones(rad.size)]), Lm, rcond=None)
        out["bgRadial"] = float(sr[0])     # negative = normal centre-bright
    except Exception:
        out["bgTiltMag"] = out["bgTiltDir"] = out["bgRadial"] = float("nan")
    del L, Lm, msmall

    # NOTE: bgTiltDir is systematically pulled toward the optic disc, a
    # genuinely bright off-centre structure. The bias is consistent (the disc
    # is always nasal), so a classifier can learn around it -- but never read a
    # single image's tilt as misalignment without cross-checking `offset`.

    # --- local contrast ----------------------------------------------------
    # [B] measures how sharply edges transition; this measures how large the
    # differences are. varLapNorm is contrast-invariant by construction and so
    # structurally cannot see haze. This is what catches it.
    #
    # Written with in-place ops: the naive form peaks at ~6 full arrays and
    # OOMs alongside a concurrent extraction run.
    g32 = J.astype(np.float32, copy=False)
    m = ndi.uniform_filter(g32, 15)
    sq = g32 * g32
    m2 = ndi.uniform_filter(sq, 15)
    del sq
    np.multiply(m, m, out=m)
    np.subtract(m2, m, out=m2)
    del m
    np.maximum(m2, 0, out=m2)
    np.sqrt(m2, out=m2)
    Sm = m2[MM]
    del m2
    out["localContrast"] = float(Sm.mean())
    out["localContrastP10"] = float(np.percentile(Sm, 10))

    # WARNING: localContrast is dominated by anatomy, not quality -- the
    # optic-disc half reads ~50% higher than the macula half on a perfectly
    # exposed image. It has an anatomical floor, like regionCV in [B].
    return out


# ----------------------------------------------------------------- columns
COLS = [
    # identity
    "id_code", "diagnosis",
    # raw image
    "width", "height", "megapixels", "aspect", "file_kb",
    # [A] status
    "fov_ok", "fov_reason", "red_degenerate", "raggedness_retry",
    # [A] geometry (full-resolution pixels)
    "centre_x", "centre_y", "radius",
    "residual", "raggedness", "circularity", "areaFrac", "offset", "borderFrac",
    # coverage
    "retina_px", "retina_pct", "black_bg_pct",
    # exposure / colour, measured INSIDE the mask
    "mean_R", "mean_G", "mean_B", "std_R", "std_G", "std_B",
    "sat_R", "sat_G", "sat_B", "dark_frac", "ratio_RG", "ratio_BG",
    # [C] illumination, exposure and contrast
    "bgMean", "bgCV", "bgSpread", "bgTiltMag", "bgTiltDir", "bgRadial",
    "localContrast", "localContrastP10", "colorSat",
    # [B] focus, on the radius-normalised image
    "varLap", "varLapNorm", "sml", "tenengrad", "tenengradVar", "brenner",
    "specSlope", "noiseSigma", "regionMin", "regionCV",
    "region1", "region2", "region3", "region4", "region5",
    # verdict
    "gate_reject", "gate_reason", "proc_ms",
]


def blank_row(idc, dx):
    r = {c: "" for c in COLS}
    r["id_code"] = idc
    r["diagnosis"] = dx
    return r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("out")
    ap.add_argument("--split", default="train", choices=["train", "test"])
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--scale", type=float, default=0.5)
    a = ap.parse_args()

    src = os.path.join(a.root, f"{a.split}.csv")
    imgdir = os.path.join(a.root, f"{a.split}_images")
    rows = list(csv.DictReader(open(src)))
    if a.limit:
        rows = rows[: a.limit]
    print(f"{len(rows)} rows from {src}  (FOV scale={a.scale})", flush=True)

    done = set()
    if os.path.exists(a.out):
        with open(a.out, newline="") as fh:
            rd = csv.DictReader(fh)
            existing = rd.fieldnames or []
            done = {r["id_code"] for r in rd}
        # csv.DictWriter does not re-read the file's header -- it writes values
        # in COLS order. Appending to a file with a different header silently
        # MISALIGNS every new row, which is unrecoverable without re-running.
        if existing and existing != COLS:
            miss = [c for c in COLS if c not in existing]
            extra = [c for c in existing if c not in COLS]
            sys.exit(
                f"\nERROR: header mismatch on {a.out}\n"
                f"  file has  {len(existing)} columns\n"
                f"  this code writes {len(COLS)} columns\n"
                f"  missing from file : {miss}\n"
                f"  unexpected in file: {extra}\n\n"
                f"Appending would misalign every new row. Options:\n"
                f"  1. write to a NEW file, or\n"
                f"  2. backfill the missing columns onto the existing rows:\n"
                f"       python python/backfill_module1_c.py {a.root} {a.out}\n"
            )
        print(f"resuming: {len(done)} already present", flush=True)

    fh = open(a.out, "a", newline="")
    w = csv.DictWriter(fh, fieldnames=COLS)
    if not done:
        w.writeheader()

    t0 = time.time()
    nok = 0
    for i, rec in enumerate(rows):
        idc = rec["id_code"]
        if idc in done:
            continue
        dx = rec.get("diagnosis", "")
        row = blank_row(idc, dx)
        ti = time.perf_counter()
        try:
            path = os.path.join(imgdir, idc + ".png")
            row["file_kb"] = round(os.path.getsize(path) / 1024, 1)
            with Image.open(path) as im:
                im = im.convert("RGB")
                I = np.asarray(im, dtype=np.uint8).astype(np.float32) / np.float32(255)
            H, W = I.shape[:2]
            row.update(width=W, height=H, megapixels=round(H * W / 1e6, 3),
                       aspect=round(W / H, 4))

            f, why, deg, ret = detect_fov(I, a.scale)
            row.update(fov_reason=why, red_degenerate=int(deg), raggedness_retry=int(ret))

            if f is None:
                row["fov_ok"] = 0
                row["gate_reject"] = 1
                row["gate_reason"] = "fov_failed"
            else:
                nok += 1
                row["fov_ok"] = 1
                M = f["mask"]
                row.update(
                    centre_x=round(f["cx"], 2), centre_y=round(f["cy"], 2),
                    radius=round(f["R"], 2), residual=round(f["residual"], 6),
                    raggedness=round(f["raggedness"], 4),
                    circularity=round(f["circularity"], 4),
                    areaFrac=round(f["areaFrac"], 4), offset=round(f["offset"], 5),
                    borderFrac=round(f["borderFrac"], 4),
                    retina_px=f["maskPx"],
                    retina_pct=round(100 * f["maskPx"] / (H * W), 3),
                    black_bg_pct=round(100 * (1 - f["maskPx"] / (H * W)), 3),
                )
                # exposure / colour inside the mask
                for nm, ch in (("R", 0), ("G", 1), ("B", 2)):
                    v = I[:, :, ch][M]
                    row[f"mean_{nm}"] = round(float(v.mean()), 5)
                    row[f"std_{nm}"] = round(float(v.std()), 5)
                    row[f"sat_{nm}"] = round(float((v >= 250 / 255).mean()), 6)
                g = I[:, :, 1][M]
                row["dark_frac"] = round(float((g <= 5 / 255).mean()), 6)
                mg = max(float(I[:, :, 1][M].mean()), 1e-6)
                row["ratio_RG"] = round(float(I[:, :, 0][M].mean()) / mg, 4)
                row["ratio_BG"] = round(float(I[:, :, 2][M].mean()) / mg, 4)

                # ---- [C] colour: on the ORIGINAL, before I is freed ----
                # Resampling blends clipped and unclipped pixels, so anything
                # read from the top of the range must be measured here.
                row["colorSat"] = round(colour_metric(I, M)["colorSat"], 6)

                # ---- normalise to R=436, then [B] at full resolution ----
                s = TARGET_R / f["R"]
                Jg = ndi.zoom(I[:, :, 1], (s, s), order=1)
                del I
                f["mask"] = None
                gc.collect()
                half, pad = int(TARGET_R), int(TARGET_R) + 10
                Jp = np.pad(Jg, ((pad, pad), (pad, pad)))
                del Jg
                r0 = int(round(f["cy"] * s + pad)) - half
                c0 = int(round(f["cx"] * s + pad)) - half
                J = np.ascontiguousarray(Jp[r0:r0 + 2 * half, c0:c0 + 2 * half]).astype(np.float64)
                del Jp
                gc.collect()

                yy, xx = np.mgrid[0:J.shape[0], 0:J.shape[1]]
                MM = np.hypot(yy - half, xx - half) <= TARGET_R * 0.98
                fm = focus_metrics(J, MM, half, half, TARGET_R)
                for k, v in fm.items():
                    row[k] = "" if (isinstance(v, float) and not np.isfinite(v)) else round(v, 8)

                # ---- [C] field metrics: reuse the normalised image ----
                for k, v in field_metrics(J, MM).items():
                    row[k] = "" if (isinstance(v, float) and not np.isfinite(v)) else round(v, 6)

                del J, MM, yy, xx
                gc.collect()

                # ---- fast-reject gate ----
                reasons = []
                if f["residual"] > 0.06:   reasons.append("residual")
                if f["areaFrac"] < 0.50:   reasons.append("areaFrac")
                if f["offset"] > 0.35:     reasons.append("offset")
                if f["borderFrac"] > 0.80: reasons.append("borderFrac")
                row["gate_reject"] = int(bool(reasons))
                row["gate_reason"] = "|".join(reasons)
        except Exception as e:
            row["fov_ok"] = 0
            row["gate_reject"] = 1
            row["gate_reason"] = "exception"
            row["fov_reason"] = f"{type(e).__name__}:{str(e)[:60]}"
        row["proc_ms"] = round((time.perf_counter() - ti) * 1000, 1)
        w.writerow(row)
        fh.flush()
        gc.collect()

        if (i + 1) % 100 == 0:
            el = time.time() - t0
            rate = (i + 1) / el
            print(f"  {i+1}/{len(rows)}  ok={nok}  {el/60:.1f} min elapsed  "
                  f"{rate:.2f} img/s  ETA {(len(rows)-i-1)/rate/60:.0f} min", flush=True)

    fh.close()
    print(f"\ndone: {len(rows)} rows, {nok} detected, {time.time()-t0:.0f}s -> {a.out}", flush=True)


if __name__ == "__main__":
    main()
