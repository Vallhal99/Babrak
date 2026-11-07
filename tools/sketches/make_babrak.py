#!/usr/bin/env python3
"""Nakreslí skicu světa Babrak podle uživatelova nákresu (souřadnice v px nákresu 1039x929) a legendu.
    python3 tools/sketches/make_babrak.py        -> tools/sketches/babrak.png + babrak_legenda.json
    python3 tools/generate_map.py tools/sketches/babrak.png tools/sketches/babrak_legenda.json /tmp/babrak.tmj --seed 7
    python3 tools/tiled_import.py /tmp/babrak.tmj --name babrak
1 px skici = 1 dlaždice = 6 px nákresu."""
import json, math, os, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, os.path.join(HERE, ".."))
from generate_map import noise

S = 6.0                       # px nákresu na dlaždici
X0, Y0, X1, Y1 = -20, 80, 1090, 990
W, H = int((X1 - X0) / S), int((Y1 - Y0) / S)
SS = 3                        # supersampling kreslení


def T(x, y): return ((x - X0) / S, (y - Y0) / S)


def smooth(pts, n=2):
    for _ in range(n):
        out = []
        for a, b in zip(pts, pts[1:] + pts[:1]):
            out += [(.75 * a[0] + .25 * b[0], .75 * a[1] + .25 * b[1]), (.25 * a[0] + .75 * b[0], .25 * a[1] + .75 * b[1])]
        pts = out
    return pts


def poly(pts, round_=True):
    im = Image.new("L", (W * SS, H * SS), 0)
    p = smooth(list(pts)) if round_ else list(pts)
    ImageDraw.Draw(im).polygon([(T(*q)[0] * SS, T(*q)[1] * SS) for q in p], fill=255)
    return np.array(im.resize((W, H), Image.BILINEAR)) > 127


def stroke(pts, width):
    im = Image.new("L", (W * SS, H * SS), 0); d = ImageDraw.Draw(im); p = [(T(*q)[0] * SS, T(*q)[1] * SS) for q in pts]
    d.line(p, fill=255, width=int(width * SS), joint="curve")
    for q in p: d.ellipse([q[0] - width * SS / 2, q[1] - width * SS / 2, q[0] + width * SS / 2, q[1] + width * SS / 2], fill=255)
    return np.array(im.resize((W, H), Image.BILINEAR)) > 127


def ellipse(cx, cy, rx, ry):
    im = Image.new("L", (W * SS, H * SS), 0)
    (a, b), (c, d) = T(cx - rx, cy - ry), T(cx + rx, cy + ry)
    ImageDraw.Draw(im).ellipse([a * SS, b * SS, c * SS, d * SS], fill=255)
    return np.array(im.resize((W, H), Image.BILINEAR)) > 127


def dist_to(mask): return ndimage.distance_transform_edt(~mask)


ZONES = {  # název: (barva, terén, mix, profil, scatter, solid)
    "deep_water": ("#0a2a5a", "deep_water", [], "water", [], True),
    "water": ("#2a6aa8", "water", [["deep_water", .12]], "water", [], True),
    "shore": ("#d8c890", "sand", [["dry_grass", .3]], "meadow", [{"tags": ["grass"], "density": .01, "min_dist": 30, "max_h": 40},
                                                              {"tags": ["rock"], "density": .004, "min_dist": 60, "max_h": 70}], False),
    "meadow": ("#5aa83a", "grass", [["grass_meadow", .25], ["flowers", .08]], "meadow",
               [{"tags": ["grass"], "density": .025, "min_dist": 16, "max_h": 50}, {"tags": ["flower"], "density": .014, "min_dist": 22, "max_h": 60},
                {"tags": ["bush"], "density": .004, "min_dist": 70}, {"tags": ["tree"], "density": .0015, "min_dist": 160, "min_h": 110},
                {"tags": ["rock"], "density": .0008, "min_dist": 90, "max_h": 80}, {"tags": ["log", "stump"], "density": .0007, "min_dist": 100, "max_h": 80},
               {"tags": ["mushroom", "fern"], "density": .004, "min_dist": 40}], False),
    "edge1": ("#4a9a3a", "grass", [["leaf_grass", .3], ["grass_dark", .2]], "meadow",
              [{"tags": ["tree"], "density": .03, "min_dist": 90, "min_h": 110}, {"tags": ["bush"], "density": .014, "min_dist": 45},
               {"tags": ["grass", "fern"], "density": .02, "min_dist": 18, "max_h": 50}], False),
    "edge2": ("#52a03a", "grass", [["grass_meadow", .2], ["leaf_grass", .15]], "meadow",
              [{"tags": ["tree"], "density": .009, "min_dist": 120, "min_h": 110}, {"tags": ["bush"], "density": .008, "min_dist": 55},
               {"tags": ["grass", "flower"], "density": .02, "min_dist": 18, "max_h": 50}], False),
    "forest": ("#1d4d1a", "forest_floor", [["leaf_grass", .2], ["grass_dark", .2]], "forest",
               [{"tags": ["tree"], "density": .045, "min_dist": 70, "min_h": 110}, {"tags": ["bush"], "density": .02, "min_dist": 40},
                {"tags": ["fern", "mushroom"], "density": .02, "min_dist": 16}, {"tags": ["log", "stump"], "density": .004, "min_dist": 60},
                {"tags": ["rock"], "density": .004, "min_dist": 50, "max_h": 80}], False),
    "glade": ("#6ab84a", "grass_meadow", [["flowers", .3]], "meadow",
              [{"tags": ["flower"], "density": .05, "min_dist": 18, "max_h": 60}, {"tags": ["grass"], "density": .03, "min_dist": 16, "max_h": 50},
               {"tags": ["mushroom", "bush"], "density": .01, "min_dist": 40}], False),
    "path": ("#b08a50", "dirt", [], "path", [{"tags": ["grass"], "density": .01, "min_dist": 24, "max_h": 30}], False),
    "camp": ("#966466", "dirt", [["dirt_rock", .2]], "camp", [{"tags": ["grass"], "density": .01, "min_dist": 30, "max_h": 30}], False),
    "village": ("#8a9a5a", "grass", [["grass_meadow", .3], ["flowers", .06]], "village",
                [{"tags": ["flowerbed"], "density": .004, "min_dist": 70}, {"tags": ["grass"], "density": .012, "min_dist": 20, "max_h": 40},
                 {"tags": ["hay"], "density": .0025, "min_dist": 50}, {"tags": ["hedge"], "density": .0015, "min_dist": 90},
                 {"tags": ["barrel", "crate", "sack", "bucket", "pot"], "density": .009, "min_dist": 36, "max_h": 70}, {"tags": ["firewood", "log", "stump"], "density": .003, "min_dist": 50, "max_h": 70},
                 {"ids": ["v_sud_a", "v_sud_b", "v_bedna", "v_zelenina_a", "v_zelenina_b", "v_klada"], "density": .006, "min_dist": 40}], False),
    "square": ("#a0a0a0", "cobble", [["dirt_rock", .08]], "village", [], False),
    "graveyard": ("#5a5a48", "mossy_ground", [["dry_grass", .3], ["dirt_rock", .1]], "village",
                  [{"ids": ["g_hrob_a", "g_hrob_b", "g_hrob_c", "g_kriz_a", "g_kriz_b", "g_kriz_c", "g_kriz_d"], "density": .06, "min_dist": 34},
                   {"ids": ["g_kamen_a", "g_kamen_b", "g_andel", "g_socha", "g_lavice", "g_rakev"], "density": .006, "min_dist": 60},
                   {"ids": ["g_mrtvy_strom_a", "g_mrtvy_strom_b", "g_mrtvy_strom_c", "g_mrtvy_strom_d", "g_mrtvy_strom_e", "g_mrtvy_strom_f"],
                    "density": .012, "min_dist": 90}, {"ids": ["g_lampa_a", "g_lampa_b"], "density": .003, "min_dist": 120}, {"tags": ["bones", "grave"], "density": .004, "min_dist": 50},
                   {"ids": ["g_parez"], "density": .004, "min_dist": 50}], False),
    "yard": ("#8a6a40", "dirt", [["dirt_rock", .1], ["grass", .2]], "village",
             [{"tags": ["hay"], "density": .01, "min_dist": 50}, {"tags": ["grass"], "density": .02, "min_dist": 20, "max_h": 30},
             {"tags": ["barrel", "crate", "sack", "bucket", "pot"], "density": .08, "min_dist": 36, "max_h": 70}, {"tags": ["firewood", "log", "stump", "tool"], "density": .015, "min_dist": 45, "max_h": 70}], False),
    "court": ("#444455", "stone_dark", [["cobble", .3]], "forest", [{"tags": ["rock"], "density": .03, "min_dist": 50, "max_h": 80}], False),
    "mountain_edge": ("#787878", "rock", [["rock_dark", .35]], "forest",
                      [{"tags": ["boulder", "cliff"], "density": .05, "min_dist": 60, "dist": [1, 13]},
                       {"tags": ["conifer"], "density": .018, "min_dist": 80, "min_h": 110, "dist": [1, 13]},
                       {"tags": ["rock"], "density": .03, "min_dist": 40, "max_h": 80, "dist": [1, 13]}], True),
    "mountain_deep": ("#606060", "rock_dark", [["rock", .2]], "forest", [], True),
}


def build():
    names = list(ZONES); idx = {n: i for i, n in enumerate(names)}
    z = np.full((H, W), idx["deep_water"], int)

    def paint(mask, name, only=None):
        m = mask if only is None else mask & np.isin(z, [idx[o] for o in only])
        z[m] = idx[name]

    river = [(105, 135), (95, 230), (75, 350), (72, 715), (55, 790), (40, 870), (60, 905), (300, 905), (700, 915), (950, 915), (1010, 870), (1015, 600), (1015, 300), (1030, 128)]
    land = poly(river, False)
    paint(land, "meadow")
    mountain = poly([(80, 325), (70, 230), (90, 60), (1060, 60), (1060, 300), (900, 285), (800, 280), (690, 268), (640, 215), (570, 180), (520, 190),
                     (480, 188), (440, 212), (380, 222), (300, 226), (180, 246), (110, 296)]) & land
    forest = poly([(180, 262), (300, 226), (440, 212), (520, 190), (570, 185), (640, 215), (690, 268), (722, 320), (722, 540), (775, 615), (700, 656), (520, 640),
                   (430, 610), (330, 640), (250, 640), (150, 662), (100, 600), (92, 540), (108, 445), (92, 380), (112, 325), (150, 290)])
    forest |= poly([(180, 270), (660, 270), (660, 605), (180, 605)], False)
    forest &= land & ~mountain
    d_forest = dist_to(forest)
    paint((d_forest <= 5) & land & ~mountain, "edge1", ["meadow"])
    paint((d_forest <= 11) & land & ~mountain, "edge2", ["meadow"])
    paint(forest, "forest")
    paint(ellipse(150, 480, 52, 42) & forest, "glade")
    paint(poly([(105, 790), (300, 790), (305, 860), (220, 872), (120, 868)]) & land, "graveyard")
    paint(ellipse(830, 775, 165, 92) & land, "village")
    paint(ellipse(885, 395, 24, 20), "yard", ["meadow", "edge1", "edge2"])
    water = stroke(river[:-1], 7)
    paint(mountain, "mountain_deep")
    paint(water, "water")
    shore = (dist_to(water) <= 2.5) & land & ~mountain
    paint(shore, "shore", ["meadow", "edge1", "edge2", "glade", "forest", "village", "graveyard"])
    walk = ~np.isin(z, [idx[n] for n in ("deep_water", "water", "mountain_deep")])
    paint((dist_to(walk) <= 14) & (z == idx["mountain_deep"]), "mountain_edge")
    ok = ["meadow", "edge1", "edge2", "forest", "glade", "shore", "village", "graveyard", "yard"]
    for pts, w in [([(150, 470), (180, 440), (250, 432), (330, 438), (420, 438), (500, 445), (580, 430), (660, 436), (780, 425), (850, 410), (885, 398)], 2.2),
                   ([(420, 440), (432, 500), (405, 560), (412, 605), (418, 640), (450, 690), (520, 740), (640, 770), (720, 790), (780, 785), (830, 790)], 2.2),
                   ([(440, 650), (520, 725), (620, 790), (680, 806), (740, 805), (830, 790)], 1.8),
                   ([(415, 640), (380, 700), (300, 770), (240, 800)], 1.8),
                   ([(690, 790), (830, 800), (975, 790)], 2.0), ([(830, 715), (830, 790), (830, 860)], 2.0),
                   ([(590, 218), (585, 260), (570, 330), (575, 430)], 1.8)]:
        paint(stroke(pts, w), "path", ok)
    paint(ellipse(420, 440, 33, 28), "camp", ok + ["path"])
    paint(ellipse(830, 790, 33, 28), "square", ok + ["path"])
    paint(ellipse(590, 215, 22, 18) & land, "court", ["forest", "mountain_edge", "mountain_deep", "path", "edge1"])
    # organický okraj: jemné posunutí hranic zón šumem
    rng = np.random.default_rng(3)
    dx, dy = (noise(W, H, 9, rng) - .5) * 3.0, (noise(W, H, 9, rng) - .5) * 3.0
    yy, xx = np.mgrid[0:H, 0:W]
    z = z[np.clip((yy + dy).round().astype(int), 0, H - 1), np.clip((xx + dx).round().astype(int), 0, W - 1)]
    img = np.zeros((H, W, 3), np.uint8)
    for n, i in idx.items(): img[z == i] = [int(ZONES[n][0][k:k + 2], 16) for k in (1, 3, 5)]
    Image.fromarray(img).save(os.path.join(HERE, "babrak.png"))
    return names


def tile(px, py): return T(px, py)


def place():
    """Pevně umístěné budovy a rekvizity: (id, x_px, y_px nákresu = střed paty). Řady domů v osadě, hřbitov, chata, vchod do dungeonu."""
    out = []
    def add(i, x, y, r=None):
        tx, ty = T(x, y); out.append({"id": i, "x": round(tx, 2), "y": round(ty, 2), **({"r": r} if r else {})})
    A, B = 748, 880          # řady domů v osadě (y nákresu)
    for i, x in [("v_dum_cihla_a", 715), ("v_dum_vysoky", 780), ("v_hostinec", 862), ("v_dum_stit", 935)]: add(i, x, A)
    for i, x, y in [("v_zbrojirna", 735, B), ("v_kovarna", 850, B), ("v_dum_hodiny", 945, B + 5)]: add(i, x, y)
    for i, x, y in [("okoli1_017", 830, 790), ("v_stanek_lektvary", 786, 770), ("v_stanek_zbrane", 878, 772), ("v_lampa", 800, 748), ("v_lampa", 862, 748),
                    ("v_lampa", 800, 836), ("v_lampa", 862, 836), ("v_lavice", 790, 818), ("v_lavice", 872, 818), ("v_ukazatel_b", 680, 770),
                    ("v_sud_a", 740, 752), ("v_sud_b", 748, 756), ("v_bedna", 905, 752), ("v_zelenina_a", 750, 812), ("v_zelenina_b", 915, 812),
                    ("v_klada", 905, 860), ("v_sud_a", 795, 880), ("v_bedna", 800, 884)]: add(i, x, y, 14)
    # chata s dvorem
    for i, x, y in [("v_dum_cerveny", 885, 405), ("v_stodola", 815, 400), ("v_klada", 945, 415), ("v_sud_a", 925, 418), ("v_bedna", 855, 418),
                    ("v_zelenina_a", 868, 440), ("v_zelenina_b", 905, 440)]: add(i, x, y)
    # kostel a hřbitov
    for i, x, y in [("v_kostel", 262, 800), ("g_mauzoleum", 140, 805), ("g_krypta", 188, 800), ("g_brana", 215, 868), ("g_lampa_c", 170, 860),
                    ("g_andel", 235, 835), ("g_lavice", 130, 848)]: add(i, x, y)
    # rozcestníky a cedule u cest
    for i, x, y in [("doplnky_014", 455, 470), ("doplnky_006", 440, 625), ("doplnky_014", 665, 450), ("doplnky_006", 335, 700)]: add(i, x, y, 30)
    # vchod do dungeonu (zatím nefunkční, jen vzhled)
    add("okoli3_004", 590, 200, 60)
    return out


def legend(names):
    leg = {"colors": {ZONES[n][0]: n for n in names}, "zones": {}, "place": place()}
    for n in names:
        _, terrain, mix, profile, scatter, solid = ZONES[n]
        z = {"terrain": terrain, "profile": profile, "scatter": scatter}
        if mix: z["mix"] = mix
        if solid: z["solid"] = True
        if n == "camp": z["camp"] = True
        leg["zones"][n] = z
    json.dump(leg, open(os.path.join(HERE, "babrak_legenda.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    legend(build()); print("OK", W, "x", H, "dlaždic")
