"""
Backfill the Stage [C] illumination columns onto an existing Module 1 feature CSV.

The extractor is resumable but skips id_codes already present, so it will NOT
add new columns to rows it already wrote. This script computes only the [C]
features for those rows.

It is cheap because it does NOT re-run FOV detection: the fitted geometry
(centre_x, centre_y, radius) is already in the CSV, so the measurement mask is
reconstructed analytically as a circle at 0.98R -- the same convention the
extractor already uses for [B].

SAFETY: this NEVER writes to the input CSV. Phase 1 appends to a separate
C-only file; phase 2 writes a merged copy to a new path. That makes it safe to
run while an extraction is still in progress.

Usage:
    # phase 1 -- compute [C] for every id in the existing CSV (resumable)
    python backfill_module1_c.py <aptos_root> data/aptos_train_module1_features.csv

    # phase 2 -- join into a complete CSV (only once phase 1 has caught up)
    python backfill_module1_c.py <aptos_root> data/aptos_train_module1_features.csv \
           --merge data/aptos_train_module1_full.csv
"""
import argparse, csv, gc, os, sys, time, warnings
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from extract_module1_features import colour_metric, field_metrics, TARGET_R  # noqa: E402

warnings.filterwarnings("ignore")
Image.MAX_IMAGE_PIXELS = None

C_COLS = ["bgMean", "bgCV", "bgSpread", "bgTiltMag", "bgTiltDir", "bgRadial",
          "localContrast", "localContrastP10", "colorSat"]
OUT_COLS = ["id_code"] + C_COLS + ["c_reason", "c_ms"]


def circle_mask(shape, cx, cy, R, frac=0.98):
    """Reconstruct the measurement mask analytically from the fitted circle.

    The real mask is the detected region eroded by 2% of R; a circle at 0.98R
    is the same thing to within the erosion tolerance, and it costs one
    hypot instead of a full re-detection.
    """
    h, w = shape
    yy, xx = np.ogrid[0:h, 0:w]
    return (xx - cx) ** 2 + (yy - cy) ** 2 <= (frac * R) ** 2


def merge(src, cfile, dest):
    if os.path.abspath(src) == os.path.abspath(dest):
        sys.exit("ERROR: refusing to overwrite the source CSV. Choose a different --merge path.")
    with open(cfile, newline="") as fh:
        cmap = {r["id_code"]: r for r in csv.DictReader(fh)}
    with open(src, newline="") as fh:
        rd = csv.DictReader(fh)
        base = rd.fieldnames or []
        rows = list(rd)

    # Insert [C] right after ratio_BG so the merged file matches the column
    # order the extractor now writes.
    cols = list(base)
    anchor = cols.index("ratio_BG") + 1 if "ratio_BG" in cols else len(cols)
    for c in C_COLS:
        if c not in cols:
            cols.insert(anchor, c)
            anchor += 1

    hit = 0
    with open(dest, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            c = cmap.get(r["id_code"])
            if c:
                hit += 1
                for k in C_COLS:
                    r[k] = c.get(k, "")
            else:
                for k in C_COLS:
                    r.setdefault(k, "")
            w.writerow(r)
    print(f"merged {hit}/{len(rows)} rows with [C] -> {dest}")
    if hit < len(rows):
        print(f"  {len(rows) - hit} rows still missing [C]; re-run phase 1 then merge again.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("root")
    ap.add_argument("src", help="existing feature CSV (read-only)")
    ap.add_argument("--out", default="", help="C-only output (default: <src>_conly.csv)")
    ap.add_argument("--merge", default="", help="write a joined CSV to this path and exit")
    ap.add_argument("--split", default="train", choices=["train", "test"])
    ap.add_argument("--limit", type=int, default=0)
    a = ap.parse_args()

    cfile = a.out or a.src.replace(".csv", "_conly.csv")
    if a.merge:
        return merge(a.src, cfile, a.merge)

    if os.path.abspath(cfile) == os.path.abspath(a.src):
        sys.exit("ERROR: --out must differ from the source CSV.")

    imgdir = os.path.join(a.root, f"{a.split}_images")
    with open(a.src, newline="") as fh:
        rows = list(csv.DictReader(fh))
    if a.limit:
        rows = rows[: a.limit]
    print(f"{len(rows)} rows in {a.src}", flush=True)

    done = set()
    if os.path.exists(cfile):
        with open(cfile, newline="") as fh:
            done = {r["id_code"] for r in csv.DictReader(fh)}
        print(f"resuming: {len(done)} already backfilled", flush=True)

    fh = open(cfile, "a", newline="")
    w = csv.DictWriter(fh, fieldnames=OUT_COLS)
    if not done:
        w.writeheader()

    t0, nok = time.time(), 0
    todo = [r for r in rows if r["id_code"] not in done]
    print(f"{len(todo)} to compute", flush=True)

    for i, rec in enumerate(todo):
        idc = rec["id_code"]
        out = {c: "" for c in OUT_COLS}
        out["id_code"] = idc
        ti = time.perf_counter()
        try:
            if rec.get("fov_ok") != "1" or not rec.get("radius"):
                out["c_reason"] = "no_fov"
            else:
                cx, cy, R = float(rec["centre_x"]), float(rec["centre_y"]), float(rec["radius"])
                path = os.path.join(imgdir, idc + ".png")
                with Image.open(path) as im:
                    I = np.asarray(im.convert("RGB"), dtype=np.uint8).astype(np.float32) / np.float32(255)
                M = circle_mask(I.shape[:2], cx, cy, R)
                if M.sum() < 100:
                    out["c_reason"] = "mask_too_small"
                    del I, M
                else:
                    # colour first -- it must read the ORIGINAL, before any
                    # resampling blends clipped and unclipped pixels
                    out["colorSat"] = round(colour_metric(I, M)["colorSat"], 6)
                    del M

                    # normalise to R=436, exactly as the extractor does, so the
                    # 15 px contrast window means the same anatomical scale in
                    # every image -- and memory stays bounded at 872x872
                    s = TARGET_R / R
                    Jg = ndi.zoom(I[:, :, 1], (s, s), order=1)
                    del I
                    gc.collect()
                    half, pad = int(TARGET_R), int(TARGET_R) + 10
                    Jp = np.pad(Jg, ((pad, pad), (pad, pad)))
                    del Jg
                    r0 = int(round(cy * s + pad)) - half
                    c0 = int(round(cx * s + pad)) - half
                    J = np.ascontiguousarray(
                        Jp[r0:r0 + 2 * half, c0:c0 + 2 * half]).astype(np.float64)
                    del Jp
                    gc.collect()

                    yy, xx = np.mgrid[0:J.shape[0], 0:J.shape[1]]
                    MM = np.hypot(yy - half, xx - half) <= TARGET_R * 0.98
                    del yy, xx
                    for k, v in field_metrics(J, MM).items():
                        out[k] = "" if (isinstance(v, float) and not np.isfinite(v)) else round(v, 6)
                    del J, MM
                    out["c_reason"] = "ok"
                    nok += 1
        except Exception as e:
            out["c_reason"] = f"{type(e).__name__}:{str(e)[:50]}"
        out["c_ms"] = round((time.perf_counter() - ti) * 1000, 1)
        w.writerow(out)
        fh.flush()
        gc.collect()

        if (i + 1) % 100 == 0:
            el = time.time() - t0
            rate = (i + 1) / el
            print(f"  {i+1}/{len(todo)}  ok={nok}  {el/60:.1f} min  "
                  f"{rate:.2f} img/s  ETA {(len(todo)-i-1)/rate/60:.0f} min", flush=True)

    fh.close()
    print(f"\ndone: {len(todo)} computed, {nok} ok, {time.time()-t0:.0f}s -> {cfile}")
    print(f"now merge:\n  python {os.path.basename(__file__)} {a.root} {a.src} "
          f"--merge {a.src.replace('.csv', '_full.csv')}")


if __name__ == "__main__":
    main()
