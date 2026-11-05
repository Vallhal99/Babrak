class_name AnimCatalog
extends RefCounted
## Layout spritesheetu (dodávaný 1:1). 64px snímky, 4 směry pod sebou (up, left, down, right).
## Dole je "oversize" oblast 128px (efekty zbraně) pro animace s klíčem big_row.
## Nová animace = nový řádek v ANIMS. Klíče: row, frames, fps, loop, dirs (1 = jen jeden řádek), big_row, hit_frame (snímek zásahu).
## Kombinované: "top" = horní půlku (nad pasem) vezme z jiné animace (pochodeň při chůzi).
## "extra" = snímky jsou v extra sheetu (vlastní textura těla/předmětu); vrstvy bez extra sheetu
## použijí "alias" animaci (snímek / alias_div).

const FRAME := 64
const BIG := 128
const BIG_Y := 4480   # kde v sheetu začíná oversize oblast (pod 70 řádky po 64 px)
const BIG_OFFSET := 32  # 64px snímek leží uprostřed 128px snímku

enum Dir { UP, LEFT, DOWN, RIGHT }

const ANIMS := {
	&"spellcast": {"row": 0, "frames": 7, "fps": 10.0, "hit_frame": 5},
	&"thrust": {"row": 4, "frames": 8, "fps": 12.0, "hit_frame": 4},
	&"walk": {"row": 8, "frames": 9, "fps": 10.0, "loop": true},
	&"slash": {"row": 12, "frames": 6, "fps": 14.0, "big_row": 0, "hit_frame": 3},
	&"shoot": {"row": 16, "frames": 13, "fps": 12.0},
	&"hurt": {"row": 20, "frames": 6, "fps": 8.0, "dirs": 1},
	&"climb": {"row": 21, "frames": 6, "fps": 8.0, "loop": true, "dirs": 1},
	&"idle": {"row": 22, "frames": 2, "fps": 2.0, "loop": true},
	&"jump": {"row": 26, "frames": 5, "fps": 8.0},
	&"sit": {"row": 30, "frames": 3, "fps": 4.0},
	&"emote": {"row": 34, "frames": 3, "fps": 4.0},
	&"run": {"row": 38, "frames": 8, "fps": 12.0, "loop": true},
	&"combat": {"row": 42, "frames": 2, "fps": 2.0, "loop": true},
	&"backslash": {"row": 46, "frames": 13, "fps": 16.0, "big_row": 4, "hit_frame": 7},
	&"halfslash": {"row": 50, "frames": 6, "fps": 14.0, "big_row": 8, "hit_frame": 3},
	# Jednoruční / nové animace z balíčku postavy v2.
	&"slash_1h": {"row": 54, "frames": 13, "fps": 16.0, "hit_frame": 7},
	&"watering": {"row": 66, "frames": 8, "fps": 8.0},
	# Pochodeň: zvednutá ruka (dokreslená póza), chůze = horní půlka pózy + nohy z walk/run.
	&"torch_idle": {"row": 0, "frames": 8, "fps": 8.0, "loop": true, "extra": true, "alias": &"idle", "alias_div": 4},
	&"torch_walk": {"row": 8, "frames": 9, "fps": 10.0, "loop": true, "top": &"torch_idle"},
	&"torch_run": {"row": 38, "frames": 8, "fps": 12.0, "loop": true, "top": &"torch_idle"},
}


static func frame_count(anim: StringName) -> int:
	return ANIMS[anim]["frames"]


static func fps(anim: StringName) -> float:
	return ANIMS[anim]["fps"]


static func is_loop(anim: StringName) -> bool:
	return ANIMS[anim].get("loop", false)


static func hit_frame(anim: StringName) -> int:
	return ANIMS[anim].get("hit_frame", -1)


static func is_extra(anim: StringName) -> bool:
	return ANIMS[anim].get("extra", false)


static func alias_of(anim: StringName) -> StringName:
	return ANIMS[anim]["alias"]


static func alias_div(anim: StringName) -> int:
	return ANIMS[anim].get("alias_div", 1)


static func is_split(anim: StringName) -> bool:
	return ANIMS[anim].has("top")


static func top_of(anim: StringName) -> StringName:
	return ANIMS[anim]["top"]


static func has_big(anim: StringName) -> bool:
	return ANIMS[anim].has("big_row")


## Výřez snímku v sheetu. big = oversize varianta (jen pro animace s big_row).
static func rect(anim: StringName, dir: int, frame: int, big := false) -> Rect2:
	var def: Dictionary = ANIMS[anim]
	var d: int = dir if def.get("dirs", 4) > 1 else 0
	if big:
		return Rect2(frame * BIG, BIG_Y + (def["big_row"] + d) * BIG, BIG, BIG)
	return Rect2(frame * FRAME, (def["row"] + d) * FRAME, FRAME, FRAME)
