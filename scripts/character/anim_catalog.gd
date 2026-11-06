class_name AnimCatalog
extends RefCounted
## Layout spritesheetu postavy (generuje ho tools/build_hero.py). 64px snímky, 4 směry pod sebou (up, left, down, right).
## Dole je "oversize" oblast 192px (efekty zbraně) pro animace s klíčem big_row; zbraň říká, které animace ji mají (ItemData.big_anims).
## Nová animace = nový řádek v ANIMS. Klíče: row, frames, fps, loop, dirs (1 = jen jeden řádek), big_row, hit_frame (snímek zásahu).
## Diagonální směry mají jen animace z DIAG (chůze/běh); jinde se kreslí svislý směr (viz resolve).

const FRAME := 64
const BIG := 192
const BIG_Y := 3968   # kde v sheetu začíná oversize oblast (pod 62 řádky po 64 px)
const BIG_OFFSET := 64  # 64px snímek leží uprostřed 192px snímku

enum Dir { UP, LEFT, DOWN, RIGHT, UP_LEFT, UP_RIGHT, DOWN_LEFT, DOWN_RIGHT }
const DIAG := {&"walk": &"walk_diag", &"run": &"run_diag"}

const ANIMS := {
	&"spellcast": {"row": 0, "frames": 7, "fps": 10.0, "hit_frame": 5},
	&"thrust": {"row": 4, "frames": 8, "fps": 12.0, "big_row": 12, "hit_frame": 4},
	&"walk": {"row": 8, "frames": 9, "fps": 10.0, "loop": true},
	&"slash": {"row": 12, "frames": 6, "fps": 14.0, "big_row": 0, "hit_frame": 3},
	&"shoot": {"row": 16, "frames": 13, "fps": 12.0, "hit_frame": 9},
	&"hurt": {"row": 20, "frames": 6, "fps": 8.0, "dirs": 1},
	&"idle": {"row": 22, "frames": 2, "fps": 2.0, "loop": true},
	&"run": {"row": 38, "frames": 8, "fps": 12.0, "loop": true},
	&"combat": {"row": 42, "frames": 2, "fps": 2.0, "loop": true},
	&"backslash": {"row": 46, "frames": 13, "fps": 16.0, "big_row": 4, "hit_frame": 7},
	&"halfslash": {"row": 50, "frames": 6, "fps": 14.0, "big_row": 8, "hit_frame": 3},
	# Osm směrů: diagonální chůze (řádky = Dir UP_LEFT..DOWN_RIGHT), běh je stejné snímky rychleji.
	&"walk_diag": {"row": 54, "frames": 6, "fps": 8.0, "loop": true},
	&"run_diag": {"row": 54, "frames": 6, "fps": 12.0, "loop": true},
	# Zvedání ze země (experiment; bez vybavení, směr UP = kopie DOWN).
	&"pickup": {"row": 58, "frames": 5, "fps": 8.0},
}


## Animace a řádek (0-3) pro směr 0-7: diagonála bez vlastní animace se kreslí svislým směrem.
static func resolve(anim: StringName, dir: int) -> Array:
	if dir < 4:
		return [anim, dir]
	if DIAG.has(anim):
		return [DIAG[anim], dir - Dir.UP_LEFT]
	return [anim, Dir.UP if dir == Dir.UP_LEFT or dir == Dir.UP_RIGHT else Dir.DOWN]


## Nejbližší z 8 směrů pro vektor pohybu.
static func dir8(v: Vector2) -> int:
	var ax := absf(v.x)
	var ay := absf(v.y)
	if ax > 2.414 * ay or ay > 2.414 * ax:
		return Character.dir_from(v)
	if v.y < 0.0:
		return Dir.UP_RIGHT if v.x > 0.0 else Dir.UP_LEFT
	return Dir.DOWN_RIGHT if v.x > 0.0 else Dir.DOWN_LEFT


static func frame_count(anim: StringName) -> int:
	return ANIMS[anim]["frames"]


static func fps(anim: StringName) -> float:
	return ANIMS[anim]["fps"]


static func is_loop(anim: StringName) -> bool:
	return ANIMS[anim].get("loop", false)


static func hit_frame(anim: StringName) -> int:
	return ANIMS[anim].get("hit_frame", -1)


static func has_big(anim: StringName) -> bool:
	return ANIMS[anim].has("big_row")


## Výřez snímku v sheetu. big = oversize varianta (jen pro animace s big_row).
static func rect(anim: StringName, dir: int, frame: int, big := false) -> Rect2:
	var def: Dictionary = ANIMS[anim]
	var d: int = dir if def.get("dirs", 4) > 1 else 0
	if big:
		return Rect2(frame * BIG, BIG_Y + (def["big_row"] + d) * BIG, BIG, BIG)
	return Rect2(frame * FRAME, (def["row"] + d) * FRAME, FRAME, FRAME)
