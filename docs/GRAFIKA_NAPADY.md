# Co dělají hry pro „dokonalou“ grafiku (a co z toho dává smysl pro Babrak)

Seřazeno podle poměru **efekt / práce** pro náš HD-2D styl (Octopath, Triangle Strategy, Sea of Stars).

## Už máme
Billboardy se skutečnými stíny, nakloněná kamera s perspektivou, tilt-shift/DOF, glow, mlha, grading + vinětace, denní doba s klíčovými snímky (`data/lighting.json`), kontaktní stíny (falešné AO), stíny mraků, lampy a táborák jako 3D světla, prach/světlušky, ladicí panel (F2).

## Světlo a stín (největší dopad)
1. **Barevný kontrast teplá/studená** – stíny jsou chladné a světla teplá (grading `gain`/`shadow_tint`). Soumrak = oranžová × fialová, noc = modrá × teplá světla lamp. Ladit v F2.
2. **Okluze (SSAO/SSIL)** – ztmavení v koutech a pod stromy; SSIL přidá barevné odrazy světla. Forward+ ho umí, v F2 je přepínač.
3. **Objemové světlo (god rays) a objemová mlha** – paprsky mezi stromy v lese, zejména ráno a navečer. Dá se i levně: šikmé průsvitné pruhy (shader `shafts`).
4. **Okenní světla a emisivní prvky** – v noci svítí okna domů, lucerny, hřbitovní lampy, runy, oči netvorů. Potřebuje „emisní masku“ ke spritům (druhá textura, nebo ručně vyznačené plochy).
5. **Dynamické stíny postav a rozptyl světla** – měkké okraje stínů (už `light_angular_distance`), delší stíny při západu slunce (výška slunce v profilu).
6. **Mokré povrchy a odrazy** – po dešti se země leskne, louže odrážejí oblohu a lampy (screen-space reflections / planar odraz).

## Obraz a „šťáva“
7. **Color grading přes LUT** – ručně doladěné barevné tabulky pro každou denní dobu/lokaci (hřbitov studený a vyšisovaný, les sytě zelený).
8. **Bloom jen na jasné věci**, jemná chromatická aberace a zrno filmu na okrajích; důsledně **žádný bílý clip** (filmic/ACES tonemap – máme filmic).
9. **Parallax a vrstvy popředí** – listí a větve v popředí (rozmazané), které se posunují rychleji než kamera; mlha ve vrstvách.
10. **Hloubka ostrosti** podle vzdálenosti od hrdiny (máme), u dialogů a obchodu zaostření na postavu.
11. **Počasí** – déšť s odrazy a kapkami na kameře, sníh se zasněžením země, mlha, bouřka s bleskem, který na okamžik osvětlí scénu.

## Svět a živost
12. **Vítr** – koruny, tráva, květiny, závěsy a plameny se vlní synchronně podle jednoho větru (shader `sway` už je; sjednotit směr a sílu).
13. **Animovaná voda** – pěna na břehu, vlnky, odlesk slunce, průhlednost u břehu s viditelným dnem, plynulý přechod písek→voda.
14. **Přechody terénu** (máme shader) + **dekály**: stopy v blátě, kolejnice vozů, vyšlapané cesty, mech, listí na cestě, kaluže.
15. **Ambientní život** – ptáci, motýli, světlušky, kouř z komínů, prach při chůzi, listí padající ze stromů, ryby v řece.
16. **Opakování a náhoda** – variace sprite (barevný posun, zrcadlení, měřítko ±5 %), aby les nebyl „razítkový“; ruční „příběhové“ detaily u důležitých míst.

## Postavy a boj
17. **Světlo na postavě** – barva okolního světla a obrys (rim light) od ohně/slunce; v noci se postava zahřívá u táborníku.
18. **Hit-stop, otřes kamery, záblesk** při zásahu; částice kouzel osvětlují okolí (dynamické světlo z ohnivé koule).
19. **Stíny postav na zdi/stromy**, měkké kontaktní stíny pod nohama (máme u props, přidat u postav).
20. **Plynulá animace**: dostatek snímků, anticipace/dohra úderu, ruční úpravy póz zbraně v ruce (dnes přenášené algoritmem).

## Výkon (aby to šlo na každém stroji)
21. Profily kvality (nízká/střední/vysoká), culling mimo obrazovku, sloučení statických props do MultiMeshů, atlasy textur, předpočítané stíny pro statické objekty (lightmapy), omezení dosahu stínů – vše se dá vypnout v F2.

## Jak ladit
Ve hře **F2** → vyber denní dobu, posuvníky, **Uložit** zapíše `data/lighting.json`. **F12** = screenshot bez panelu (`user://shots`). Kontaktní arch všech denních dob na vybraných místech: `tests/light_sheet.tscn` (proměnná `LIGHT_SPOTS`).

## Stav implementace (body 1–16 a 21; postavy a boj 17–20 záměrně vynechány)
Kód: `scripts/world/world_fx.gd` (počasí, nálada oblasti, život), `shaders/ground3d.gdshader` (voda, louže, sníh, mech),
`shaders/prop3d.gdshader` (vítr, okna, sníh na střechách), `shaders/post_fx.gdshader` (paprsky, zrno, aberace, LUT, ostření dialogu),
`tools/make_luts.py` (LUT nálady), `zones.png` z `tools/sketches/make_babrak.py` (maska vody a oblastí).
Ovládání: F2 laboratoř (počasí, předvolby kvality Nízká/Střední/Vysoká), F3 přepíná počasí.
- Ověřeno snímky (Compatibility): teplá/studená grading, LUT nálady, okna svítí v noci, počasí (déšť/bouřka/sníh/mlha) včetně desaturace a zatažení, listí v popředí, variace spritů, vítr.
- NEOVĚŘENO (jen Forward+, v sandboxu nelze spustit): SSAO/SSIL, objemová mlha, DOF kamery, měkké stíny (PCSS). Jsou zapojené a přepínatelné v F2.
- Zjednodušeno: odrazy v loužích a vodě jsou falešné (barva oblohy + fresnel), ne screen-space; koleje vozů nejsou; stopy jsou plošné otisky.
