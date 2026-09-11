"""#1 Pixel Dimension gate.

Mega-Pixel Size: Borderline (0.3-1 MP), Reject (<0.3 MP), Pass (>1 MP).
"""

from dataclasses import dataclass

REJECT_MP = 0.3
BORDERLINE_MP = 1.0


@dataclass
class PixelDimensionResult:
    width: int
    height: int
    megapixels: float
    status: str  # "pass" | "borderline" | "fail"


def check_pixel_dimension(width: int, height: int) -> PixelDimensionResult:
    megapixels = (width * height) / 1_000_000.0

    if megapixels < REJECT_MP:
        status = "fail"
    elif megapixels < BORDERLINE_MP:
        status = "borderline"
    else:
        status = "pass"

    return PixelDimensionResult(width=width, height=height, megapixels=megapixels, status=status)


def check_pixel_dimension_image(image) -> PixelDimensionResult:
    """image: HxW or HxWxC numpy array."""
    height, width = image.shape[:2]
    return check_pixel_dimension(width, height)
