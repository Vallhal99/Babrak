"""Diagonální chůze a zvedání ze země ze složky Animace_doplnek (80px snímky) -> řádky ve sheetu těla (64px buňky)."""
from pathlib import Path

import numpy as np
from PIL import Image

DIRS = ("north-west", "north-east", "south-west", "south-east")  # = řádky walk_diag: Dir UP_LEFT .. DOWN_RIGHT
PICK_DIRS = {"west": 1, "south": 2, "east": 3}                   # řádek = Dir; UP (0) se zkopíruje z jihu
WALK_FRAMES, PICK_FRAMES = 6, 5
FEET_Y = 61  # patky v 64px buňce (CharacterVisual.ORIGIN)


def _read(path) -> np.ndarray:
    return np.array(Image.open(path).convert("RGBA"))


def _lowest(frames) -> int:
    return max(int(np.nonzero(f[..., 3])[0].max()) for f in frames)


def _crop(frames, bottom: int):
    """80px -> 64px: střed x, nejnižší bod animace na FEET_Y."""
    top = bottom - FEET_Y
    return [np.ascontiguousarray(f[top:top + 64, 8:72]) for f in frames]


def load(folder: Path):
    """Vrátí (walk {směr: [buňky]}, pick {směr: [buňky]})."""
    anim = folder / "animations"
    walk = {d: [_read(anim / "Walking" / d / f"frame_{i:03d}.png") for i in range(WALK_FRAMES)] for d in DIRS}
    pick = {d: [_read(anim / "Picking_Up" / d / f"frame_{i:03d}.png") for i in range(PICK_FRAMES)] for d in PICK_DIRS}
    bw, bp = max(_lowest(f) for f in walk.values()), max(_lowest(f) for f in pick.values())
    return {d: _crop(f, bw) for d, f in walk.items()}, {d: _crop(f, bp) for d, f in pick.items()}
