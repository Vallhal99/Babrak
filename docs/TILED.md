# Svět z Tiledu (chunky)

## Postup
1. V Tiledu: *New Map* → Orthogonal, **velikost dlaždice 24×24 nebo 48×48** (obojí funguje, hra se řídí tím, co je v mapě; 24 = jemnější malování, tileset v Tiledu musí mít stejnou velikost dlaždice), zapnout **Infinite**. Format vrstev: CSV nebo Base64 (zlib).
2. Namaluj mapu (vrstvy a vlastnosti níže), ulož jako `.tmj` (JSON).
3. Z kořene projektu: `python3 tools/tiled_import.py cesta/mapa.tmj --name svet`
   → vznikne `data/world/svet/` (chunky) a `assets/tilesets/svet/` (obrázky).
4. Ve scéně `TiledWorld` nastav `world_dir = res://data/world/svet`. Ukázka: `scenes/demo/tiled_demo.tscn` (F6).

## Vrstvy (vlastnosti vrstvy v Tiledu)
| vlastnost | význam |
|---|---|
| `hd` = true | podklad se kreslí shaderem (organické přechody, detaily). Dlaždice mají vlastnost `terrain` |
| `above` = true | vrstva se kreslí nad postavou (koruny, střechy) |
| (žádná) | obyčejná vrstva dlaždic, dlaždice s `solid` = true mají kolizi |

## Vlastnosti dlaždic (Tileset editor)
- `terrain` (string): `grass`, `dirt`, `sand` – názvy z `data/world/terrains.json` (první = základ, max. 3 přebíjející)
- `solid` (bool): dlaždice blokuje pohyb
- u dlaždic ve sbírce obrázků (stromy…): `collision` (`"12"` = kruh, `"100,26"` = obdélník, `"none"`), `shadow` (bool), `sway` (bool)

## Objekty (objektová vrstva)
Nejlépe **body** (Insert Point). Pozice = pata objektu.
- `type=prop`, vlastnost `id` (`tree_oak`, `tent`, `barrel`, `log`, `stump`…) – obrázky v `assets/world/`
- `type=campfire` – táborák (plameny, světlo, kolize)
- `type=light` – světlo: `color` (`#ffb070`), `energy`, `radius` (px)
- `type=player_start` – kde začíná hrdina
- **tile-objekt** (vložený obrázek z tilesetu) – pata = spodní střed obrázku; kolize z vlastností dlaždice
- vlastní typy: `world.spawners["enemy"] = Callable(obj, chunk) -> Node2D`

## Nastavení streamování (`TiledWorld`)
`load_radius` (chunky kolem hráče, výchozí 2 = 5×5), `unload_margin`, `rows_per_frame` (rozpočet kreslení), `tuft_density` (trsy trávy).
Velikost chunku: `--chunk-size` při importu (výchozí ≈ 1536 px, tj. 32 dlaždic při 48 px, 64 při 24 px).
Ukázkový balíček pro jinou mřížku: `python3 tools/export_tiled_pack.py 24` (nebo `48`).

## Omezení
- Otočené/překlopené dlaždice jsou podporované, diagonální překlopení (transpose) není otestované.
- Offsety vrstev a rotace dlaždic-objektů se ignorují. Komprese zstd není podporovaná.

## Spolupráce na mapě (ty v Tiledu ↔ Claude)
Složka `tiled_pack/` je připravená k otevření v Tiledu (File → Open Project → `svet.tiled-project`): sdílené tilesety `tilesety/terrain.tsj` (terény, zeď) a `tilesety/props.tsj` (stromy, stan, sud… s předvyplněnými vlastnostmi) a ukázková mapa `mapy/ukazka.tmj`.
Vlastní mapy ukládej do `tiled_pack/mapy/`, aby seděly cesty k tilesetům.

1. Pošli mi `.tmj` a napiš, co chceš (např. „doplň les kolem cesty, vlevo přidej tábor“). Pošli i složku `tilesety/`, pokud jsi v ní něco měnil.
2. Vrátím soubor s novým číslem verze (`mapa_v2.tmj`). **Pokračuj od něj** a dokud ti ho nevrátím, starou verzi neupravuj.
3. Když jsi mezitím upravoval starou verzi, nevadí: `python3 tools/tiled_tool.py merge mapa_v1.tmj mapa_v2.tmj tva_verze.tmj -o mapa_v3.tmj` spojí změny obou stran (u konfliktu vyhrává verze od Clauda).
4. Kontrola mapy: `python3 tools/tiled_tool.py check mapa.tmj`, rozdíl verzí: `... diff stara.tmj nova.tmj`.
5. Knihovna `tools/tiled_map.py` umí mapu číst a upravovat skriptem (malování terénů, cest, hromadné rozmístění objektů) a při ukládání zachová vše, co nezná (vlastnosti, externí tilesety).

Tipy do Tiledu: terény maluj plochými dlaždicemi z `terrain.tsj` (ne autotile – přechody dělá shader). Stromy a rekvizity vkládej jako **tile-objekty** (Insert Tile) z `props.tsj`; spodní střed obrázku = pata. Třídu `campfire`, `light`, `player_start` napiš do pole *Class* u bodového objektu.

## Balíček z tvých tilesetů (`tiled_pack/`, vytváří `python3 tools/build_user_pack.py`)
Otevři `tiled_pack/svet.tiled-project`, mapa `mapy/start.tmj` je ukázka.
- `terrain.tsj` – **paleta terénů** (16 dlaždic 24 px, vlastnost `terrain`): grass, grass_meadow, grass_dark, leaf_grass, flowers, forest_floor, dry_grass, dirt, dirt_rock, sand, cobble, stone_dark, brick_tan, wood_floor, marble, mossy_ground. Maluj jimi vrstvu `ground` (hd). Přechody dělá shader; chunk zobrazí až 8 různých terénů naráz (nejčastější vyhrají), vyšší číslo se kreslí přes nižší.
- `zem1/2/3.tsj` – tvoje sheety země v mřížce 24 px pro ruční kreslení zdí, útesů, jeskyní, mostů (do vrstvy `walls`, `solid` nastav v Tiledu na dlaždicích, které mají blokovat).
- `okoli1/2/3.tsj`, `doplnky.tsj`, `stromy02.tsj`, `rm_stromy01.tsj`, `rm_stromy.tsj` – **objekty** automaticky vyříznuté z tvých sheetů (≈350 kusů). Vkládej je jako tile-objekty (Insert Tile), pata = spodní střed. Každý má předvyplněné vlastnosti `kind` (tree/bush/prop/building/plant/deco), `collision`, `sway`, `shadow`, `shadow_size`; klasifikace je odhad podle tvaru a barvy, kdykoli ji v Tiledu přepiš.
- Pořadí tilesetů v mapě nikdy neměň (číslování gid by se rozbilo), nové jen přidávej na konec.
- Cesty k obrázkům, které v zipu chyběly (91 tilesetů), se ignorují.
