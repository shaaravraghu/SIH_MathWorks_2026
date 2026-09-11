"""Stage 3 feature selection: which Stage 2 columns reach the grading model,
and the Phase 6 ablation blocks (Module3_Plan.md S2.2, S6, S8, D5, D7).

TWO RULES THIS MODULE ENFORCES, both measured rather than stylistic:

1. STAGE 1 CONTRIBUTES NO MODEL INPUTS (D7, S2.1). Module 1 features alone
   reached AUC 0.707 for referable DR, and adding them to the Module 2 set
   moved AUC only 0.910 -> 0.915. Within resolution strata every sharpness
   metric's apparent link to grade turns out to be the camera: sicker APTOS
   patients were photographed on different equipment, their retinas are not
   blurrier. S1 columns are carried for QC and confidence routing (S6.4)
   and are never returned by model_inputs().

2. EXCLUDE AND QC COLUMNS NEVER REACH THE NETWORK (S2.2). od_x/od_y/
   fovea_x/fovea_y are raw coordinates; od_radius_pct/od_contrast/
   od_fovea_dist_dd are localisation sanity checks whose search window
   bounds them (od_fovea_dist_dd within rho -0.036).

PHASE 6 ADDS BLOCKS IN ORDER, NOT ALL AT ONCE (D5). 38 inputs on ~340
training rows per fold overfits; the plan starts at the 12 columns with a
measured within-resolution equivalent and keeps each later block only if
within-resolution out-of-fold QWK improves.
"""

# --- Phase 6 blocks, in the order S8 adds them ------------------------------

BLOCK_MEASURED_CORE = [            # 6a: S2-01..06, 12, 13, 24, 29, 30, 37
    "vessel_density_pct", "vessel_fragmentation", "vessel_components",
    "vessel_largest_tree_pct", "vessel_length", "vessel_orientation_coherence",
    "nv_score", "nv_score_max",
    "haem_count", "haem_q_min", "haem_q_max", "rule421_haem",
]
BLOCK_MICROANEURYSM = [            # 6b: S2-41..45, decision D1
    "ma_count", "ma_q1", "ma_q2", "ma_q3", "ma_q4",
]
BLOCK_CALIBRE_BEADING = [          # 6c: S2-07..11
    "major_vessel_pct", "branch1_vessel_pct", "minor_vessel_pct",
    "venous_beading_pct", "venous_beading_quadrants",
]
BLOCK_NV_SPLIT = [                 # 6d: S2-14..16
    "nvd_score", "nve_score", "nv_irma_quadrants",
]
BLOCK_EXUDATE_DME = [              # 6e: S2-31..34 - previous detector was INVERTED, check the sign first
    "hard_exudate_count", "hard_exudate_area_pct",
    "exudate_fovea_min_dist_dd", "dme_flag",
]
BLOCK_CWS = [                      # 6f: S2-35, 36
    "cws_count", "cws_area_pct",
]
BLOCK_QUADRANTS_421 = [            # 6g: S2-25..28, 38..40
    "haem_q1", "haem_q2", "haem_q3", "haem_q4",
    "rule421_beading", "rule421_irma", "severe_npdr_flag",
]

# Ordered: block name -> columns. Phase 6 walks this cumulatively.
PHASE6_BLOCKS = [
    ("6a_measured_core", BLOCK_MEASURED_CORE),
    ("6b_microaneurysm", BLOCK_MICROANEURYSM),
    ("6c_calibre_beading", BLOCK_CALIBRE_BEADING),
    ("6d_nv_split", BLOCK_NV_SPLIT),
    ("6e_exudate_dme", BLOCK_EXUDATE_DME),
    ("6f_cws", BLOCK_CWS),
    ("6g_quadrants_421", BLOCK_QUADRANTS_421),
]

# S5 / S2.3: carried in the CSV, never a feature. `resolution` is for
# stratified reporting only (S4.3) - the network must never see it.
CARRY_COLUMNS = ["id_code", "diagnosis", "split", "cv_fold", "resolution", "sample_source"]

# S6.4: confidence routing lowers the calibrated probability for these, but
# they are NOT model inputs (D7).
CONFIDENCE_COLUMNS = ["stage1_verdict", "enhancement_applied"]

# Lesion columns: these are the ONLY columns a fitted lesion classifier
# changes, so they are what has to be recomputed inside every CV fold
# (S4.1, S6.1). Everything else in the Stage 2 row is classifier-free.
CLASSIFIER_DEPENDENT_COLUMNS = [
    "haem_count", "haem_q1", "haem_q2", "haem_q3", "haem_q4",
    "haem_q_min", "haem_q_max", "rule421_haem",
    "ma_count", "ma_q1", "ma_q2", "ma_q3", "ma_q4",
    "hard_exudate_count", "hard_exudate_area_pct",
    "exudate_fovea_min_dist_dd", "dme_flag",
    "cws_count", "cws_area_pct",
    "severe_npdr_flag",   # composite of rule421_haem, which is classifier-dependent
]

REFERABLE_THRESHOLD_GRADE = 2   # S6.4: referable = grade >= 2
DME_OVERRIDE_COLUMN = "dme_flag"  # S6.4: forces urgent referral regardless of grade


def blocks_through(last_block):
    """Cumulative feature list up to and including `last_block` (S8's Phase 6
    walk). Pass "6a_measured_core" for the 12-column start (D5)."""
    columns, found = [], False
    for name, block in PHASE6_BLOCKS:
        columns.extend(block)
        if name == last_block:
            found = True
            break
    if not found:
        raise ValueError(f"unknown block {last_block!r}; expected one of "
                         f"{[n for n, _ in PHASE6_BLOCKS]}")
    return columns


def all_model_inputs():
    """Every MODEL-role Stage 2 column: 38 with the D1 microaneurysm block.
    D5 recommends starting at 6a and adding blocks rather than using this."""
    return blocks_through(PHASE6_BLOCKS[-1][0])


def model_inputs(last_block="6a_measured_core"):
    """The feature list for one Phase 6 step. Defaults to 6a per D5."""
    return blocks_through(last_block)


def check_against_stage2(stage2_columns):
    """Guards the block lists against Stage 2's actual schema: every block
    column must exist, and every MODEL-role column must appear in exactly one
    block. Returns (missing, unassigned) - both empty means the lists agree
    with features.py."""
    assigned = []
    for _, block in PHASE6_BLOCKS:
        assigned.extend(block)
    missing = [c for c in assigned if c not in stage2_columns]

    exclude = {"od_x", "od_y", "fovea_x", "fovea_y"}
    qc = {"od_radius_pct", "od_contrast", "od_fovea_dist_dd"}
    model_role = [c for c in stage2_columns if c not in exclude and c not in qc]
    unassigned = [c for c in model_role if c not in set(assigned)]
    return missing, unassigned
