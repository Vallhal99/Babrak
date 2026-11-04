# Tilesety od uživatele (zip „titleset_velke“)

Uloženo v `tools/source_tilesets/user/` (složka je pro Godot ignorovaná – `.gdignore`):
- `images/` – 27 PNG, `tsx/` – 110 původních tilesetů z Tiledu (beze změny), `tsx_local/` – 19 tilesetů s opravenou cestou k obrázku (otevřou se přímo),
- `CHYBEJICI_OBRAZKY.txt` – 91 `.tsx` odkazuje na obrázky z uživatelova disku (`Hra/Titleset/…`), které v zipu nebyly. Dodat jen, když je bude potřeba.

## Mřížka
Mapy i tilesety v Tiledu: **24×24 px**. Sheety RPG Maker 768×768 se v Tiledu berou jako 32×32 dlaždic po 24 px (každá původní dlaždice 48 px = 2×2 kousky).
Výjimka: `A_Outside_B_mvt.tsx` má 32×32 px (nesedí s ostatními – před použitím sjednotit).

## Vlastní sheety uživatele (bez .tsx, 24 px)
| soubor | rozměr | obsah |
|---|---|---|
| `titleset_zem.png`, `tileset_zem2.png`, `titleset_zem3.png` | 720×864 (30×36) | **země**: tráva, hlína, písek, dlažba, zdi, útesy, jeskyně, schody, mosty, voda/jezírka (A1/A2/A4/A5 sestavené do jednoho listu) |
| `tileset_okoli.png`, `tileset_okoli2.png`, `tileset_okoli3.png` | 720×864 | **okolí**: keře, květiny, tráva, balvany, kameny, pařezy, stromy (zelené, podzimní, tyrkysové), živé ploty, kmeny, mostky |
| `tileset_doplnky.png` | 912×720 (38×30) | **doplňky**: sudy, truhly, kádě, žebříky, nářadí, stany, sloupky, sochy, dlaždice zdí, usychající stromy a keře |
| `Trees02.png`, `Trees01.png`, `trees.png` | 720×864 / 768² | stromy a keře |

## Hotové sady (RPG Maker, 768×768)
`EX_Village`(1–5), `Graveyard_B/C/D`, `D_Dungeon_B/C`, `D_Outside_C`, `Fantasy_Outside_B_green`, `MZ_EX_Outside_C_Alternate/D/E`, `TileE-OutsideTown`.

## Jak se s tím bude pracovat
- Terény (tráva, hlína, písek…) = ploché vnitřní dlaždice z `zem*` listů s vlastností `terrain`; přechody dělá shader (ne autotile).
- Objekty (stromy, keře, kameny, sudy, stany) = vyříznuté sprity jako tile-objekty (kolekce obrázků) s kolizí u paty.
- Cíl: balíček pro Tiled (`tiled_pack`) složený z těchto sheetů.
