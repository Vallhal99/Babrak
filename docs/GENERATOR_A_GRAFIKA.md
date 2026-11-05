# Slovník objektů, generátor map, atmosféra

## Slovník (`data/world/object_catalog.json`)
Každý z ~350 objektů má český název, `kind`, `tags` (tree, bush, rock, barrel, camp, village, ritual, …). `tag_rules` říkají,
co smí do které zóny (cesta = jen drobnosti, les = stromy/keře/houby, tábor = stan/sudy/bedny kolem ohně…).
Položky `"uncertain": true` a seznam `unknown_for_user` jsou věci k ověření (brána, stojan, kompozity k rozřezání).
Změníš-li slovník: `python3 tools/build_user_pack.py` (znovu vytvoří `tiled_pack/` s vlastnostmi `tags`, `label`).

## Mapa ze skici
```
python3 tools/generate_map.py skica.png legenda.json mapa.tmj [--seed 3]
python3 tools/tiled_import.py mapa.tmj --name nazev      # -> data/world/nazev
```
Skica: 1 px = 1 dlaždice (24 px), plošné barvy = zóny. Legenda mapuje barvu → zóna (terén, `mix`, `profile`, `scatter` pravidla
s tagy/hustotou/odstupem, `camp: true` = ohniště + vybavení). Příklad: `tools/sketches/palouk.png` + `palouk_legenda.json`.
Výsledek otevři v Tiledu a dolaď ručně.

## Atmosféra (`scripts/world/atmosphere.gd`)
`add_child(Atmosphere.new())` + `set_time(t)` + `set_weather(Atmosphere.Weather.RAIN)`. Obsahuje post-processing
(`shaders/post_fx.gdshader`: bloom, grading, tilt-shift, vinětace), stíny mraků a mlhu (`shaders/clouds.gdshader`),
částice pyl/světlušky, listí, déšť, sníh. V ukázce: N = denní doba, B = počasí. Test: `tests/atm_shot.tscn`.
