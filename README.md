# Hero RPG (Godot 4.7)

Spuštění: otevřít projekt, F5. Ovládání: WASD/šipky, Shift = běh, Space/J = útok, Q = kouzlo, I/Tab = inventář, N = noc/den, Esc = pauza.

## Struktura
- `scripts/data/` – `ItemData` (Resource), `ItemDB` (autoload, čte `data/items/*.tres`), `Inventory`, `Equipment`
- `scripts/character/` – `AnimCatalog` (layout sheetu), `CharacterVisual` (vrstvy + animace), `Character` (základ: staty, boj, vybavení), `Hero` (vstup hráče), `Enemy` (AI)
- `scripts/world/hd2d_world.gd` – HD-2D svět (palouk, `TiledWorld` + 3D vykreslení), `scripts/ui/inventory_panel.gd` – inventář
- `tools/build_hero.py` – z balíčku `tools/source_hero/` (renderované kompletní postavy) vyrobí tělo, vrstvy vybavení (rozdíl proti holému tělu), ikony a `data/items/*.tres`; vypíše chybějící animace u každé věci
- `archive/hero_v1/` – původní postava, předměty a nástroje (`.gdignore`, Godot je ignoruje)

## Systémy
- **Staty/level:** `Character` (hp, mana, xp, `gain_xp`). Každá úroveň = 5 dovednostních bodů (`spend_point`) do atributů v `Character.ATTRIBUTES` (nový atribut = řádek tam + efekt v max_hp/max_mana/attack_power/speed_mult). Nepřítel dává `xp_reward`.
- **Loot:** `Enemy.loot` = pole `LootEntry` (předmět + šance). Padá jako `Pickup`, hráč ho sebere dotykem.
- **Kouzla:** `SpellData` (.tres v `data/spells/`) → postavě do `spells`. Sesílání = animace `spellcast`, efekt na snímku `hit_frame`. Nový efekt = větev v `Character._release_spell`.
- **UI:** `Hud` (životy/mana/XP), `InventoryPanel` (záložky Postava, Kouzla), `PauseMenu` (Esc), `main_menu.tscn` (run/main_scene).

## Postavy
NPC: `Npc` (neutrální, `invulnerable`, stojí) – scéna `merchant.tscn`. Ukončení hry potvrzuje `ExitDialog`. Obchod: E u NPC se `shop_stock` → `ShopPanel` (zlato, `ItemData.price`).
Nová postava = nová scéna zděděná z `scenes/characters/character.tscn` + skript s `_think()`. Vzhled/staty/vybavení (`start_items`) se nastavují v inspektoru.
Pochodeň: mechanika `stance`/`torch_*` zůstává v kódu, ale pochodeň je zatím archivovaná (nová póza pro nové tělo se nekreslila).

## Jak přidávat
- **Předmět:** nový `.tres` v `data/items/` (slot, `layer_sheet`, ikona). Nic dalšího.
- **Slot (tělo, nohy, ruce, štít…):** `ItemData.Slot` + `SLOT_NAMES`, `CharacterVisual.DRAW_ORDER`, `InventoryPanel.SLOTS`.
- **Animace:** řádek v `AnimCatalog.ANIMS`.
- **Layout sheetu:** 832 px široký, 70 řádků po 64 px (`AnimCatalog.ANIMS`), pod nimi (od `BIG_Y`) 192px oversize efekty zbraní (meč, dlouhý meč, kyj).
- **Nová věc z balíčku:** přidat složku do `tools/source_hero/` + řádek do `ITEMS` v `tools/build_hero.py` a spustit ho (vznikne sheet, ikona i `.tres`).
- **Sloty:** Zbraň, Hlava, Tělo, Rukavice, Boty, Druhá ruka; pořadí kreslení `CharacterVisual.DRAW_ORDER`.

Test: `godot --headless --path . res://tests/smoke_test.tscn`
