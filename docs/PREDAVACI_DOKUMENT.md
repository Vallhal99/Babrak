# PŘEDÁVACÍ DOKUMENT PROJEKTU – Hero RPG (Godot 4.7)
Stav k 5. 11. 2026. Fakta jsou z konverzace; vše označené **[předpoklad]** nebo **[neznámé]** nebylo potvrzeno.
Konverzace byla jednou komprimována; části z doby před kompresí (postava, boj, inventář, obchod) znám jen ze shrnutí.

---
## 1. PODSTATA PROJEKTU
- **Cíl:** 2D hra ve stylu Final Fantasy / Zelda v **Godotu 4.7** (GDScript). Projekt: `/home/claude/hero_rpg`, GitHub **Vallhal99/babrak** (repozitář byl přejmenován/přesunut na `https://github.com/Vallhal99/Babrak.git`, push stále prochází), větev `main`, lokální klon `/home/claude/babrak`.
- **Dlouhodobé cíle uživatele:** čistý rozšiřitelný kód; vrstvená postava s bojem; sdílené animace; mapa postavená z **jeho vlastních tilesetů**; moderní vzhled („2D-HD" pro rok 2026).
- **Jak to funguje (aktuální pipeline):** uživatel kreslí v **Tiledu** (mapa 24 px mřížka, vlastní tilesety) → pošle `.tmj` → AI ho upraví/doplní nástroji → vrací → uživatel pokračuje. Z `.tmj` se importérem vyrobí chunky (`data/world/<jméno>/`), které Godot streamuje (`TiledWorld`). Nově lze mapu **vygenerovat ze skici** (PNG s plošnými barvami + legenda) podle **slovníku objektů** (sémantika: co je co, kam smí).
- **Problémy, které to řeší:** obří otevřený svět bez načítacích časů (chunky); moderní vzhled terénu (měkké přechody, tráva); kooperace uživatel↔AI nad mapou (merge/diff nástroje); nesmyslné rozmístění objektů (sudy a lana na cestě) → slovník + pravidla zón.
- **Vize:** otevřený svět z uživatelových tilesetů s moderním osvětlením a atmosférou; uživatel dodá skicu/mapu, AI doplní detaily smysluplně.
- **Uživatel:** Čech, chce stručné odpovědi, šetří tokeny.

### 1b. ZÁKLADY HRY (doplněno z kódu a README; původní rozhovor o designu už nemám k dispozici, jen jeho výsledek v kódu)
- **Název/spuštění:** „Hero RPG", `run/main_scene = res://scenes/ui/main_menu.tscn`, okno 960×720, filtr textur nearest (pixel art), autoloady `Inputs` (klávesy v kódu) a `ItemDB` (čte `data/items/*.tres`). Hlavní herní scéna `scenes/main.tscn` + `scripts/main.gd` (mapa, hrdina, UI, respawn nepřátel po 6 s, po smrti hrdiny restart scény po 2,5 s, startovní zlato 50, testovací vybavení = všechny předměty v batohu).
- **Ovládání:** WASD/šipky pohyb, Shift běh, Space/J útok, Q kouzlo, E interakce (obchod), I/Tab inventář, N noc/den, Esc pauza.
- **Postavy:** `Character` (základ pro hrdinu, nepřítele i NPC; `_think()` přepisují potomci) → `Hero` (vstup hráče), `Enemy` (AI: sight 200, attack_range 30, cooldown 1,2 s, `loot` = pole `LootEntry` s šancí), `Npc` (neutrální, nezranitelný, obchodník `merchant.tscn`, `shop_stock`, nekonečné zásoby, prodej za polovinu ceny).
- **Staty:** hp 30, útok 2, obrana 0, mana 20 (regen 2/s), chůze 90, běh 150. Úroveň: každá = 5 bodů (`POINTS_PER_LEVEL`) do atributů `ATTRIBUTES`: Síla (+1 útok), Vitalita (+4 zdraví), Duch (+3 many), Obratnost (+3 % rychlosti). Nepřítel dává `xp_reward`, `gold_reward`.
- **Vybavení:** sloty `ItemData.Slot` = NONE, WEAPON (Zbraň), HEAD (Hlava), FEET (Boty), OFFHAND (Druhá ruka). Předmět `ItemData` (.tres): id, název, ikona, slot, cena, `layer_sheet`, `extra_sheet`, `stance` (pochodeň = `torch`), `light` (poloměr světla), damage/defense/max_hp/max_mana, `attack_anim`. `Equipment` přesouvá mezi batohem (`Inventory`) a sloty, `sum_of()` sčítá staty. Existující předměty: sword_wood, sword_steel, helm_hood_slate, helm_armet_steel, helm_mail_silver, boots_sandals_maroon, boots_armour_silver, torch.
- **Kouzla:** `SpellData` (.tres: PROJECTILE/HEAL, mana_cost, power, color, cast_anim); existují `fireball`, `heal`; sesílání = animace `spellcast`, efekt na `hit_frame`, nový efekt = větev v `Character._release_spell`; projektil `scripts/combat/projectile.gd`.
- **Vrstvená postava:** `CharacterVisual` skládá tělo + sloty vybavení z vrstev, každá vrstva = 2 sprity (horní/dolní půlka, dělí se v pasu `SPLIT_Y`=42), sdílený čas → vrstvy jsou synchronní; pořadí kreslení `DRAW_ORDER`. `AnimCatalog` = layout spritesheetu 64 px snímky, 4 směry (up, left, down, right), oversize oblast 128 px dole (efekty zbraní, `BIG_Y`=3456); animace: spellcast, thrust, walk, slash, shoot, hurt, climb, idle, jump, sit, emote, run, combat, backslash, halfslash + pochodňové `torch_*` (horní půlka z dokreslené pózy, nohy z walk/run). **Sdílené animace** = všechny postavy používají stejný layout sheetu (cíl projektu).
- **UI:** `Hud` (životy/mana/XP, layer 5), `InventoryPanel` (záložky Postava, Kouzla), `ShopPanel`, `PauseMenu`, `ExitDialog`, `main_menu`.
- **Jak přidávat (pravidla z README):** předmět = nový `.tres` v `data/items/`; slot = `ItemData.Slot`+`SLOT_NAMES`+`CharacterVisual.DRAW_ORDER`+`InventoryPanel.SLOTS`; animace = řádek v `AnimCatalog.ANIMS`; zbraň = sheet 1664×4992 ve stejném layoutu jako `full_sheet_with_sword.png`, ostatní vybavení sheet 832×3456; nová postava = scéna zděděná z `scenes/characters/character.tscn` + skript s `_think()`; kouzlo = `.tres` v `data/spells/`.
- **Nástroje postavy:** `tools/build_torch.py` (póza zvednuté ruky + plamen), `tools/build_assets.py` (z `full_sheet_with_sword.png` udělá `hero_base.png`, vrstvu meče, ikony). Test: `godot --headless --path . res://tests/smoke_test.tscn`.
- **[neznámé]** Příběh, svět, herní smyčka a cíle (quest, bossové, progres) – v kódu ani v dostupných podkladech nejsou; pokud jsme je dříve probírali, jsou ztracené. Nová AI se má uživatele zeptat, nebo je doplnit z jeho odpovědi.
- **Renderer:** `project.godot` nenastavuje `rendering_method` → platí výchozí (Forward+ **[předpoklad]**); u uživatele nepotvrzeno.

---
## 2. DOSAVADNÍ PRÁCE
### Hotovo (potvrzeno testy / snímky)
1. Postava (Hero, vrstvená), boj, inventář, obchod – z doby před kompresí **[detaily neznámé, v kódu `scripts/character`, `scripts/ui`]**.
2. Demo „varianta B" (`camp_demo`): palouk s ohništěm, živé efekty (plameny, světla, světlušky, sway stromů, stíny, den/noc).
3. **TiledWorld** (`scripts/world/tiled_world.gd`) – streamovaný loader chunků (WorkerThreadPool), hystereze načítání/uvolnění, kolize, y-sort, vlastní terénní shader (až 8 terénů na chunk, měkké hrany šumem), tuft trávy přes MultiMesh.
4. **Importér** `tools/tiled_import.py` (.tmj → `world.json` + `chunk_X_Y.json`, kopíruje obrázky do `assets/tilesets/<jméno>/`).
5. **Nástroje pro spolupráci:** `tools/tiled_tool.py` (check/diff/3-way merge), `tools/tiled_map.py` (knihovna: fill_rect/fill_circle/stroke/add_object/save).
6. **Balíček pro Tiled** `tiled_pack/` (zip `/tmp/claude-0/tiled_pack_tvuj.zip`, doručen uživateli): projekt `svet.tiled-project`, `mapy/start.tmj`, `mapy/palouk.tmj`, tilesety (terrain + zem1/2/3, okoli1/2/3, doplnky, stromy02, rm_stromy01, rm_stromy; objekty jako kolekce obrázků s vlastnostmi `id, kind, collision, sway, shadow, shadow_size, tags, label`).
7. **Terény** (16): grass, grass_meadow, grass_dark, leaf_grass, flowers, forest_floor, dry_grass, dirt, dirt_rock, sand, cobble, stone_dark, brick_tan, wood_floor, marble, mossy_ground (`tools/terrains_user.py`, `data/world/terrains.json`).
8. **Slovník objektů** `data/world/object_catalog.json` – všech 351 objektů (139 skupin přes rozsahy id), české názvy, `kind`, `tags`, pravidla zón `tag_rules` (path/forest/camp/meadow/swamp/village), příznaky `uncertain`, seznam `unknown_for_user`. Loader: `tools/object_catalog.py`. `build_user_pack.py` z něj přebírá `kind` a `tags`.
9. **Generátor mapy ze skici** `tools/generate_map.py` + ukázka `tools/sketches/palouk.png`, `palouk_legenda.json`. Ověřeno v Godotu: cesta volná, les = stromy/keře/houby, tábor = stan/sudy/bedny/dříví kolem ohně.
10. **Atmosféra + post-processing** (2D): `scripts/world/atmosphere.gd` (class `Atmosphere`), `shaders/post_fx.gdshader` (tilt-shift, bloom z mipmap, grading, vinětace), `shaders/clouds.gdshader` (stíny mraků + mlha ve světových souřadnicích), částice pyl/světlušky/listí/déšť/sníh. Integrováno do `tiled_demo` (N = denní doba, B = počasí). Test `tests/atm_shot.tscn`.
11. **HD-2D ukázka** (oddělená): nahrazena hrou: `scripts/world/hd2d_world.gd` (viz 9c).
12. Dokumentace: `docs/TILED.md`, `docs/TILESETY_UZIVATEL.md`, `docs/GENERATOR_A_GRAFIKA.md`.

### Klíčová rozhodnutí
- Mřížka mapy **24 px** (uživatel: tilesety mu vycházejí jen takto), ne 48.
- Soubory uživatele (`titleset_velke.zip`) = zdroj všech tilesetů; ořezané objekty ~351 ks, 91 tsx bez obrázků se ignoruje.
- Verzování map `mapa_v1`, `_v2`; starou verzi needitovat, když je nová u AI; **neměnit pořadí tilesetů** (stabilita gid).
- 2D-HD (Octopath) **nevyžaduje 3D modely** – objekty zůstávají 2D sprity.
- Pořadí grafiky (doporučené): 1 post-processing ✔, 2 atmosféra ✔, 3 skutečné stíny slunce/ohně, 4 normal mapy, 5 voda/decaly, 6 postavy (rim light), 7 UI, 8 skutečné HD-2D (3D scéna).

### Postupy HD-2D ukázky (jak je to postavené)
- `SubViewport` (ground_vp) renderuje 2D svět (`TiledWorld`, load_radius 8, objekty skryté) → textura na `PlaneMesh` (1 px = 0,02 m).
- Objekty: z `world.objects` se pro každý Sprite2D vytvoří `Sprite3D` (alpha scissor, shaded, rotace x = −TILT 44°, střed posunut vektorem UP) → real stíny `DirectionalLight3D`.
- Hrdina běží v 2D v druhém SubViewportu (hero_vp, 192 px, transparentní, `canvas_cull_mask` 2; ground_vp maska 1; sdílí `world_2d` kvůli fyzice) a zobrazuje se jako Sprite3D.
- Camera3D fov 26°, offset (0,17,14) m, post_fx přes CanvasLayer (tilt-shift), Environment: filmic, glow, fog; oheň = OmniLight3D + CPUParticles3D; N cykluje den/soumrak/noc.

---
## 3. AKTUÁLNÍ STAV
**Funguje:** vše výše v „Hotovo" (ověřeno screenshoty přes xvfb/opengl3).
**Rozpracované / nedotažené:**
- Rozhodnutí uživatele, zda jít **2D styl** (pak body 3–4) nebo **HD-2D** (přepis loaderu) – čeká se na něj.
- Slovník: položky `uncertain` nepotvrzeny uživatelem.
**Nefunguje / známé vady:**
- HD-2D: plamen přes den bílá skvrna; stíny korun stromů vypadají jako světelné pruhy; tráva/drobné květiny jen ploché na zemi; DoF ověřen NENÍ (xvfb/Compatibility ho nepodporuje; v Forward+/Mobile má fungovat **[předpoklad]**); chybí sway; hrdina se čte z dočasného snímku, žádné HUD.
- Déšť v 2D atmosféře je jen slabé čáry.
- `doplnky_017` je rozložený stan (vypadá jako velký hnědý čtverec), druhý obrázek v souboru je hotový stan.
- Kompozity k ručnímu rozřezání (generátor je přeskakuje): `doplnky_013/018/019/021`, `okoli3_004/007/017/038`.
- Nejisté štítky: `doplnky_007/008` (kamenná brána – rituál/dungeon?), `doplnky_037` (stojan?), `okoli2_028/030` (jáma a pahorek – terén či ozdoba?), `okoli2_041`, `okoli1_045`.
- Netestováno: transponované (rotované) dlaždice z Tiledu.
- Klasifikace druhů v `classify()` byla odhad podle tvaru/barvy; slovník ji nyní přepisuje.
- Renderer: `project.godot` ho nenastavuje (výchozí Forward+ **[předpoklad]**); u uživatele nepotvrzeno. Screenshoty se dělaly v Compatibility (opengl3).

---
## 4. TECHNICKÉ INFORMACE
**Technologie:** Godot 4.7-stable, GDScript; Python 3 (numpy, PIL, scipy) pro nástroje; Tiled (.tmj JSON, infinite maps, chunky 16×16, externí .tsj/.tsx, image-collection tilesety, vlastnosti, flip flagy gid, Base64/zlib).
**Struktura (`/home/claude/hero_rpg`):**
- `scripts/world/`: `tiled_world.gd` (TiledWorld), `camp_world.gd`, `camp_demo.gd`, `tiled_demo.gd`, `prop_factory.gd`, `fx.gd`, `terrain_mask.gd`, `day_night.gd` (DayNight, CanvasModulate: 0 den, 0.5 soumrak, 1 noc, `counter_color()`), `campfire.gd` (group `campfires`), `atmosphere.gd`, `hd2d_demo.gd`.
- `scripts/character/hero.gd` (class Hero), `scripts/ui/` (Hud layer 5, InventoryPanel 10, ShopPanel 11, PauseMenu 20).
- `shaders/`: `ground_terrain.gdshader` (tex0..7, mask_a/mask_b, blur_px, tile, edge_noise), `ground.gdshader`, `sway.gdshader`, `vignette.gdshader`, `shafts.gdshader`, `post_fx.gdshader`, `clouds.gdshader`.
- `scenes/`: `maps/camp_map.tscn`, `demo/camp_demo.tscn`, `demo/tiled_demo.tscn`, `characters/hero.tscn`.
- `tools/`: `tiled_import.py`, `tiled_map.py`, `tiled_tool.py`, `build_world_assets.py`, `terrains_user.py`, `build_user_pack.py`, `object_catalog.py`, `generate_map.py`, `sketches/`, `source_tilesets/user/` (zdroje), `.gdignore`.
- `data/world/`: `terrains.json`, `object_catalog.json`, `start/` (4 chunky), `palouk/` (vygenerovaná mapa, 4 chunky, hranice dlaždic [-50,-38,50,38], chunk 64).
- `tiled_pack/` (`.gdignore`), `docs/`, `tests/` (`camp_shot`, `tiled_stream`, `tuft_orient`, `palouk_shot`, `atm_shot`).
**Důležité parametry TiledWorld:** `world_dir`, `load_radius`=2, `unload_margin`=1, `rows_per_frame`=24, `tuft_density`, `edge_noise`=0.34, `terrain_texture_size`=48, `blur_px`=34, `MAX_SLOTS`=8 (mask_a RGBA sloty 1–4, mask_b RGB sloty 5–7, default `Color(0,0,0,0)`).
**Tiled konvence:** vrstvy `ground`(hd), `walls`, `above`(above), `objects`; tile-objekty origin vlevo dole, `objectalignment bottom`; vlastnosti dlaždic `terrain`/`solid`; třídy objektů `prop`/`campfire`/`light`/`player_start`.
**Formát slovníku:** `{"s":sada,"r":"000-005,010","name","kind","tags":[…],"uncertain"?,"note"?}`; sady: okoli1, okoli2, okoli3, doplnky, stromy02, rm_stromy01, rm_stromy. Id objektu = `sada_NNN`.
**Generátor – legenda:** `{"colors":{"#hex":"zona"},"zones":{"zona":{"terrain","mix":[[terén,podíl]],"profile","scatter":[{"tags","density","min_dist","min_h","max_h","none_tags"}],"camp":true,"camp_items":[…]}}}`; 1 px skici = 1 dlaždice; použití `python3 tools/generate_map.py skica.png legenda.json mapa.tmj [--seed N] [--origin x,y]`, pak `python3 tools/tiled_import.py mapa.tmj --name jméno`. Cesta: zakázané velké objekty (`tag_rules.path.forbid`).
**Technická řešení (shrnutí):** CPUParticles2D s additive materiálem a protibarvou proti CanvasModulate; PointLight2D flicker; MultiMeshInstance2D s ArrayMesh quadem (QuadMesh je v 2D převrácený); sway shader (horní část sprite); spatial hash pro rozestupy stromů; TileSet za běhu (fyzická vrstva, solid dlaždice); Compatibility-safe post efekty přes `hint_screen_texture`.
**Spouštění testů (screenshoty):**
`xvfb-run -a -s "-screen 0 960x720x24" godot --rendering-driver opengl3 --path . res://tests/<test>.tscn`. Binárka Godotu: `/tmp/claude-0/godot/Godot_v4.7-stable_linux.x86_64` (**dočasná**, v novém prostředí nemusí existovat; `g.zip` ve stejné složce). Po přidání mnoha PNG / nových `class_name` je nutný `godot --headless --import --path .` (trvá i >100 s → spouštět na pozadí s `&` a čekat `sleep`).
**Git:** commit zakončit řádky `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` a `Claude-Session: https://claude.ai/code/session_01FD8vuVyrJSbNkXnfN6hiP1`. Poslední commit `4140dec`. Postup: změny v hero_rpg → `tar --exclude=.godot -cf - . | (cd /home/claude/babrak && tar xf -)` → commit/push (rsync není).

---
## 5. DŮLEŽITÁ ROZHODNUTÍ A PRAVIDLA
- Nesmí se měnit: 24 px mřížka; pořadí tilesetů a gid; stará verze mapy, kterou má AI u sebe; stávající 2D styl a demo musí zůstat zachované (uživatel to výslovně žádal pro srovnání).
- Rozvoj: iterativně, nejdřív ukázka/snímek, pak rozhodnutí uživatele; slovník je zdroj pravdy o významu objektů; nové objekty = doplnit do slovníku → `build_user_pack.py` → regenerace balíčku.
- Slepé uličky a chyby (neopakovat):
  - `pkill -f <vzor>` zabije vlastní shell (konec 144) – nepoužívat.
  - `godot --headless --import` trvá minuty – spouštět na pozadí.
  - Hrdina reparentovaný do `world.objects` → hledat `map.objects.get_node("Hero")`.
  - `add_collision_polygon` až po `_tileset.add_source(src)`.
  - Hystereze: počet chunků ≤ (2(r+margin)+1)², v testu kontrolovat vzdálenost ≤ r+margin.
  - Tráva obráceně v MultiMesh → ArrayMesh `_sprite_quad` s UV (0,0)=levý horní roh.
  - Neseamless textury terénu (okraje živého plotu) → odstraněny `grass_bright`, `moss_dark`; `grass_dark` ze zem1 (2,9).
  - Alfa masky jako datový kanál slotu 4 měla default 1 → nastaveno 0 (jinak celé hnědé).
  - V GDScriptu: dictionary hodnota nemá odvozený typ (`var x: float = {...}[k]`); `EMISSION_SHAPE_RECTANGLE` (ne RECT); builtiny shaderu (`SCREEN_PIXEL_SIZE`) nejsou dostupné v pomocných funkcích → předat parametrem.
  - Sdílení `world_2d` mezi SubViewporty sdílí i canvas → nutné `canvas_cull_mask` + `visibility_layer`; hrdinu dát do vlastního viewportu, jinak se renderuje i země; viewport textura vyžaduje `UPDATE_ALWAYS`.
  - Neseamless/objekty na cestě bez slovníku (sudy, lana, oltář) → řešeno slovníkem.

---
## 6. OTEVŘENÉ ÚKOLY
**Nejvyšší priorita:** získat od uživatele **rozhodnutí 2D vs. HD-2D** (viz bod 8).
Dál:
- Pokud 2D: bod 3 (skutečné stíny slunce/ohně), 4 (normal mapy), 5 (voda/decaly), 6 (rim light postav), 7 (UI).
- Pokud HD-2D: přepsat loader na 3D (objekty jako Sprite3D přímo z chunků, ne ze snímku 2D světa), opravit plamen/stíny/trávu, sway, DoF ověřit ve Forward+, HUD, výkon.
- Potvrzení nejistých štítků ve slovníku; rozřezání kompozitů; rozdělení `doplnky_017` na dva stany.
- Kosmetika: silnější déšť v 2D atmosféře.
- Testy: transponované dlaždice z Tiledu.
- Uživatel pošle svou mapu z Tiledu (ještě nedodal) → AI upraví/obohatí.
- Po změnách objektů přegenerovat balíček a znovu pushnout.

---
## 7. PRACOVNÍ STYL A SPOLUPRÁCE
- Odpovídat **česky, stručně**, šetřit tokeny; výsledek (soubor, snímek) + 1–2 věty; bez recapu kroků.
- Pro rozhodnutí uživatele ukázat **vizuální srovnání** (snímky); otázky jen když je změna drahá.
- Změny dělat v dílčích krocích, testovat v Godotu screenshotem a výsledek ověřit pohledem, ne jen „kompiluje se".
- Uživatel si všímá detailů (např. obrácená tráva, nesmyslné objekty) – kontrolovat správnost před předáním.
- Zachovat starý stav při experimentech (nové scény vedle, ne přepis).
- Soubory posílat jako zip/PNG; GitHub aktualizovat po dokončení bloku.
- Pozor na plán uživatele: **bezplatný plán Claude** (bez plánovaných úloh, ovládání prohlížeče/počítače).

---
## 8. PŘESNÝ BOD NAVÁZÁNÍ
Poslední hotové: HD-2D ukázka (snímky den/soumrak/noc vs. 2D) byla doručena a nahrána na GitHub (`4140dec`); uživatel následně chtěl tento předávací dokument. **Čeká se na rozhodnutí uživatele, zda pokračovat 2D, nebo HD-2D.** Aktuální úkol: nová AI má
1. přečíst tento dokument a `docs/GENERATOR_A_GRAFIKA.md`, naklonovat/otevřít repo, ověřit, že `tiled_demo.tscn`, `hd2d_demo.tscn` a `data/world/palouk` fungují;
2. zeptat se uživatele jednou krátkou otázkou, kterou cestou jít (2D body 3–4 / HD-2D) a zda potvrdí nejisté objekty;
3. mezitím nic nemazat ani nepřepisovat.

---
# INSTRUKCE PRO NOVÝ CHAT
Text k vložení jako první zpráva:

> Pokračuješ v mém projektu **Hero RPG** (Godot 4.7, GDScript, Final Fantasy/Zelda styl). Repozitář: `https://github.com/Vallhal99/Babrak` (dřív babrak), větev main, soubor **`docs/PREDAVACI_DOKUMENT.md`** je kompletní předávací dokument – přečti ho celý a také `README.md` (základy hry: staty, vybavení, kouzla, vrstvená postava), `docs/GENERATOR_A_GRAFIKA.md` a `docs/TILED.md`. Neznáš naši předchozí konverzaci (příběh a herní cíle jsem ti nemohl předat – zeptej se mě na ně); vše potřebné je v dokumentu.
> Stručně: mapu dělám v Tiledu (24 px mřížka, mé vlastní tilesety), ty ji doplňuješ nástroji v `tools/` (importér, merge, generátor mapy ze skici podle slovníku objektů `data/world/object_catalog.json`). Godot streamuje chunky přes `TiledWorld`. Máme hotovou 2D atmosféru/post-processing a oddělenou HD-2D ukázku (`scenes/demo/hd2d_demo.tscn`, 3D se stíny); stávající 2D verzi nikdy nepřepisuj.
> Pravidla: odpovídej česky a stručně, šetři tokeny; neměň mřížku 24 px ani pořadí tilesetů; změny testuj screenshotem (xvfb + godot, viz dokument; `pkill -f` nepoužívat; import spouštět na pozadí); ukazuj vizuální výsledky; commit zakonči řádky Co-Authored-By/Claude-Session podle dokumentu.
> Nejdřív ověř, že projekt běží, a pak se mě krátce zeptej: (1) zůstaneme u 2D (stíny slunce/ohně, normal mapy) nebo půjdeme do HD-2D? (2) potvrdím ti nejisté objekty ze slovníku (brána `doplnky_007/008`, stojan `doplnky_037`, jáma/pahorek `okoli2_028/030`). Do mé odpovědi nic nepřepisuj ani nemaž.

---
## 9. POSTAVA V2 (5. 11. 2026)
- Nová hlavní postava z balíčku `tools/source_hero/` (kompletní renderované sheety). `python3 tools/build_hero.py` z nich udělá `assets/characters/hero/{body,equipment,weapons}`, ikony a `data/items/*.tres` (18 předmětů: hlava 4, tělo 4, boty, rukavice, zbraně 8 vč. meče). Vrstva = rozdíl proti holému tělu; šest brnění/přileb je už izolovaných (`base="none"`).
- Layout: `AnimCatalog` má 70 řádků (+`slash_1h`, `watering`), `BIG_Y` = 4480. Nové sloty `TORSO`, `HANDS`.
- Původní postava, předměty a nástroje: `archive/hero_v1/` (`.gdignore`). Pochodeň je archivovaná (póza byla kreslená na staré tělo).
- Známé mezery: brnění nemají některé animace (kroužková košile: combat/backslash/halfslash; všechny věci: slash_1h/watering) → postava je v nich bez nich; luk/kuše mají jen animaci `shoot`, střelba není implementovaná (nejsou v obchodě); 192px oversize efekty (Longsword/Blunt), `tool_axe`, `walk_128` luku nejsou využity; ikony rukavic/kabátu/kapuce jsou hrubé.

### 9b. Osm směrů (5. 11. 2026)
- Zdroj `tools/source_hero/Animace_doplnek/` (diagonální chůze 6 snímků, zvedání ze země ve 3 směrech, 80px snímky). `tools/hero8.py` je vycentruje do 64px buňky (patky na y=61) a vybavení pro diagonály **přefituje** z hotových vrstev: hlava = výřez z vrstvy posunutý na novou hlavu, tělo/nohy/boty = přebarvení těla barvami věci (podle světlosti). Není to ručně kreslené – detaily (plechy, kroužky) se ztrácejí.
- Katalog: `Dir` má 8 hodnot; `walk_diag`/`run_diag` (řádky 70–73), `pickup` (74–77, UP = kopie DOWN), `BIG_Y` = 4992. `AnimCatalog.resolve()` pošle diagonálu jen chůzi/běhu, ostatní animace dostanou svislý směr. `Character.facing` zůstává 4směrový (boj), jen vizuál chůze/běhu používá `AnimCatalog.dir8()`.
- Mezery: rukavice a zbraně nemají diagonální chůzi, zvedání ze země je jen tělo, barvy vlasů/kalhot nového těla se liší od 4směrového (hnědé vlasy, šedé šortky vs. zrzavé/bílé).

## 9c. Aktuální stav hry (HD-2D, nahrazuje starší poznámky o test_map / hd2d_demo / BIG_Y)
- První level (`test_map`, `GameMap`) je smazán. `scenes/main.tscn` = `Main` (Node2D) + `World` (`Hd2dWorld`, `scripts/world/hd2d_world.gd`) + UI. `main.gd` po signálu `World.built` vytvoří hrdinu, obchodníka a nepřátele (`world.add_actor(node, pos)`), signál `started`.
- `Hd2dWorld`: 2D logika běží ve SubViewportu `ground_vp` (TiledWorld palouk + uzel `actors`); země i props se kreslí ve 3D. Každá postava/předmět/projektil přidaný do `actors` dostane vlastní SubViewport (192/128 px) + Sprite3D billboard; vrstva viditelnosti = jeden bit (max 19 současně). Pozor: cull maska platí pro celý podstrom, proto má kořen `root2d` i `actors` všechny vrstvy (`0xFFFFF`) a vrstvu řeší až potomci.
- Den/soumrak/noc: `world.set_stage(0..2, instant)`, `cycle_stage()` (klávesa N). Kamera sleduje `world.focus`.
- Postava: `body.png` (bez zbraně, bez vlasů) + `hair.png`; zbraň vždy jako vrstva s vlastními animacemi; helma s `hides_hair` skryje vlasy. Katalog animací `AnimCatalog` (BIG = 192, BIG_Y = 3968, 8 směrů jen pro chůzi/běh, `pickup` experimentálně). Generuje `python3 tools/build_hero.py` (z kořene projektu; zdroje v `tools/source_hero/`).
- Doplněné vybavení je algoritmické (přebarvení těla + přenos hlavy, `tools/hero_fit.py`), ne ručně kreslené; chybí opasek s mečem v animacích, kde ho zdroj nemá; sekera vyřazena; kouzelnický klobouk vlasy neskrývá.
- Test: `tests/smoke_test.tscn` (SMOKE OK), screenshoty v `/tmp/claude-0/shot_*.png`.
- Zbraň v ruce: zdrojové sheety zbraní (mimo meč) mají zbraň jen v útoku/chůzi; `hero_fit.carry` ji přenese do idle/combat/walk/run/spellcast/hurt a diagonál z referenční pózy podle pohybu hlavy.
- Obchodník: `tools/build_merchant.py` z `tools/source_merchant/caba64.jpg` (pixel art 55×55 bloků) → `assets/characters/merchant/merchant.png`; sprite je ve všech buňkách (stojí čelem, bez vlasové vrstvy, bez vybavení).
- **Mapa Babrak** (`data/world/babrak`, 185×151 dlaždic) podle uživatelova nákresu: hory (neprůchozí skála + valy kamenů/jehličnanů, vchod do dungeonu = jeskyně s kamenným dvorkem, zatím nefunkční), les, palouček, louky s plynulým přechodem (edge1/edge2), řeka kolem dokola (voda neprůchozí, písčitý břeh), osada (domy, hostinec, kovárna, zbrojnice, náměstí se studnou a stánky), chata s dvorem, kostel s hřbitovem, cesty. Zdroj: `python3 tools/sketches/make_babrak.py` (kreslí `babrak.png` + `babrak_legenda.json` ze souřadnic nákresu, tam se dají měnit polygony/budovy) → `python3 tools/generate_map.py tools/sketches/babrak.png tools/sketches/babrak_legenda.json tiled_pack/mapy/babrak.tmj --seed 7` → `python3 tools/tiled_import.py tiled_pack/mapy/babrak.tmj --name babrak`. Generátor nově umí `solid` zóny (dlaždice `walls` jen u průchozího okraje), `place` (pevné budovy/rekvizity) a `dist` v scatteru (jen u okraje zóny).
- Prohlídka mapy: `tests/map_tour.tscn` (proměnná prostředí `TOUR=village,church,...`) uloží screenshoty `/tmp/claude-0/tour_*.png`. Na softwarovém rendereru trvá načtení světa minuty, na GPU rychle.
