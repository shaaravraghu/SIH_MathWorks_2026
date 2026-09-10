"""
Merge Module 2 features into the existing Module 1 CSV.

Adds the Module 2 columns to aptos_train_module1_features.csv, filled for
whichever id_codes have been processed and blank for the rest.  Re-running with
more processed rows fills more cells without disturbing existing ones.

A timestamped backup of the original is written before anything is changed.

Usage:
    python merge_module2.py <module1.csv> <module2_partial.csv>
"""
import sys, os, shutil, time
import pandas as pd

M2_COLS = ["vessel_pct", "vessel_comps", "vessel_largest_pct", "vessel_width_med",
           "vessel_skel_len", "vessel_frag", "vessel_coh",
           "od_x", "od_y", "od_bright", "od_struct",
           "ma_count_INVALID", "m2_ok", "m2_reason", "m2_ms"]


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return
    m1_path, m2_path = sys.argv[1], sys.argv[2]

    m1 = pd.read_csv(m1_path)
    m2 = pd.read_csv(m2_path)
    print(f"module1: {m1.shape[0]} rows x {m1.shape[1]} cols")
    print(f"module2: {m2.shape[0]} rows")

    bak = m1_path.replace(".csv", f".backup_{time.strftime('%Y%m%d_%H%M%S')}.csv")
    shutil.copy2(m1_path, bak)
    print(f"backup : {os.path.basename(bak)}")

    have = [c for c in M2_COLS if c in m2.columns]
    m2 = m2[["id_code"]+have].drop_duplicates("id_code")

    # drop any pre-existing module2 columns so a re-run refreshes rather than
    # creating _x/_y suffixes
    m1 = m1.drop(columns=[c for c in have if c in m1.columns], errors="ignore")

    out = m1.merge(m2, on="id_code", how="left")
    assert len(out) == len(m1), "merge changed the row count"

    out.to_csv(m1_path, index=False)
    filled = int(out["m2_ok"].notna().sum()) if "m2_ok" in out else 0
    print(f"\nwrote  : {out.shape[0]} rows x {out.shape[1]} cols")
    print(f"filled : {filled}/{len(out)} rows have Module 2 features "
          f"({100*filled/len(out):.1f}%)")
    print(f"added  : {', '.join(have)}")

    if filled:
        sub = out[out.m2_ok == 1]
        print("\nsummary of the filled rows:")
        for c in ["vessel_pct", "vessel_comps", "vessel_largest_pct",
                  "vessel_width_med", "od_bright", "od_struct", "ma_count_INVALID"]:
            if c in sub.columns:
                v = pd.to_numeric(sub[c], errors="coerce").dropna()
                if len(v):
                    print(f"   {c:>20}  min {v.min():>8.2f}  med {v.median():>8.2f}"
                          f"  max {v.max():>8.2f}")


if __name__ == "__main__":
    main()
