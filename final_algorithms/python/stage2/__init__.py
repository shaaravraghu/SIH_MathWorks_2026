"""Stage 2: Localization/Segmentation suite (see
notes/Implementation_Ideas/Final_Ideas/Stage_2_CNN).

The Module 3 feature schema (S2-01..S2-45, run at the working resolution
required by every pixel constant in Stage_2_CNN) lives in features.py and
resample.py; import those directly (`from final_algorithms.python.stage2
import features, resample`) rather than through here, since that API is
CV-fold-safe (candidates vs. classified features are two separate calls) and
not a single convenience function.
"""

from .pipeline import run_stage2
from .vessels import (
    VESSEL_CALIBRE_BEADING,
    VESSEL_CALIBRE_MAJOR,
    VESSEL_CALIBRE_FIRST_BRANCH,
    VESSEL_CALIBRE_MINOR,
    VESSEL_CLASS_MAJOR,
    VESSEL_CLASS_NEOVASCULARISATION,
    VESSEL_CLASS_IRMA,
)

__all__ = [
    "run_stage2",
    "VESSEL_CALIBRE_BEADING",
    "VESSEL_CALIBRE_MAJOR",
    "VESSEL_CALIBRE_FIRST_BRANCH",
    "VESSEL_CALIBRE_MINOR",
    "VESSEL_CLASS_MAJOR",
    "VESSEL_CLASS_NEOVASCULARISATION",
    "VESSEL_CLASS_IRMA",
]
