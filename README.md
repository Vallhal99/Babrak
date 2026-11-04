# Hero RPG (Godot 4.7)

Spuštění: otevřít projekt, F5. Ovládání: WASD/šipky, Shift = běh, Space/J = útok, Q = kouzlo, I/Tab = inventář, N = noc/den, Esc = pauza.

## Struktura
- `scripts/data/` – `ItemData` (Resource), `ItemDB` (autoload, čte `data/items/*.tres`), `Inventory`, `Equipment`
- `scripts/character/` – `AnimCatalog` (layout sheetu), `CharacterVisual` (vrstvy + animace), `Character` (základ: staty, boj, vybavení), `Hero` (vstup hráče), `Enemy` (AI)
- `scripts/world/game_map.gd` – mapa + zdi, `scripts/ui/inventory_panel.gd` – inventář
- `tools/build_torch.py` – dokreslí pózu zvednuté ruky + plamen pochodně
- `tools/build_assets.py` – z `full_sheet_with_sword.png` udělá `hero_base.png` (tělo) + vrstvu meče + ikony

## Systémy
- **Staty/level:** `Character` (hp, mana, xp, `gain_xp`). Každá úroveň = 5 dovednostních bodů (`spend_point`) do atributů v `Character.ATTRIBUTES` (nový atribut = řádek tam + efekt v max_hp/max_mana/attack_power/speed_mult). Nepřítel dává `xp_reward`.
- **Loot:** `Enemy.loot` = pole `LootEntry` (předmět + šance). Padá jako `Pickup`, hráč ho sebere dotykem.
- **Kouzla:** `SpellData` (.tres v `data/spells/`) → postavě do `spells`. Sesílání = animace `spellcast`, efekt na snímku `hit_frame`. Nový efekt = větev v `Character._release_spell`.
- **UI:** `Hud` (životy/mana/XP), `InventoryPanel` (záložky Postava, Kouzla), `PauseMenu` (Esc), `main_menu.tscn` (run/main_scene).

## Postavy
NPC: `Npc` (neutrální, `invulnerable`, stojí) – scéna `merchant.tscn`. Ukončení hry potvrzuje `ExitDialog`. Obchod: E u NPC se `shop_stock` → `ShopPanel` (zlato, `ItemData.price`).
Nová postava = nová scéna zděděná z `scenes/characters/character.tscn` + skript s `_think()`. Vzhled/staty/vybavení (`start_items`) se nastavují v inspektoru.
Pochodeň: předmět ve slotu OFFHAND se `stance = torch` přepne chůzi/stání na `torch_*` animace (horní půlka = dokreslená póza, nohy z walk/run).

## Jak přidávat
- **Předmět:** nový `.tres` v `data/items/` (slot, `layer_sheet`, ikona). Nic dalšího.
- **Slot (tělo, nohy, ruce, štít…):** `ItemData.Slot` + `SLOT_NAMES`, `CharacterVisual.DRAW_ORDER`, `InventoryPanel.SLOTS`.
- **Animace:** řádek v `AnimCatalog.ANIMS`.
- **Zbraň:** sheet ve stejném layoutu jako `full_sheet_with_sword.png` (1664×4992; dole 128px efekty), jen samotná zbraň; `attack_anim` určuje útok.
- **Ostatní vybavení:** sheet 832×3456 ve stejném layoutu jako ostatní.

Test: `godot --headless --path . res://tests/smoke_test.tscn`
