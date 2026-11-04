"""Definice terenu z uzivatelovych sheetu: (jmeno, sheet, x, y) v pixelech sheetu, vzdy 48x48 plna (seamless) dlazdice.
Poradi = priorita (nizsi = zaklad, vyssi se kresli pres nizsi). 'blok' = interior autotilu (offset +24,+72 od rohu bloku 96x144)."""
Z1, Z2, Z3 = "titleset_zem", "tileset_zem2", "titleset_zem3"
def t(col, row): return col * 48, row * 48
def blok(col, row): return col * 48 + 24, row * 48 + 72
TERRAINS = [
    ("grass",        Z1, *t(0, 0)),     # svetla trava
    ("grass_meadow", Z2, *t(2, 0)),     # travnik
    ("grass_dark",   Z1, *t(2, 9)),     # tmava trava
    ("leaf_grass",   Z2, *t(10, 5)),    # listnata trava
    ("flowers",      Z2, *t(10, 0)),    # trava s kvetinami
    ("forest_floor", Z2, *t(4, 0)),     # lesni podrost
    ("dry_grass",    Z2, *t(14, 0)),    # suchá trava
    ("dirt",         Z2, *t(6, 0)),     # hlina
    ("dirt_rock",    Z1, *blok(4, 0)),  # hlina s kameny
    ("sand",         Z1, *blok(2, 0)),  # pisek
    ("cobble",       Z1, *blok(0, 3)),  # svetla dlazba
    ("stone_dark",   Z2, *t(0, 0)),     # tmava dlazba
    ("brick_tan",    Z1, *t(10, 0)),    # cihly
    ("wood_floor",   Z2, *t(6, 3)),     # drevena podlaha
    ("marble",       Z1, *t(12, 0)),    # mramor
    ("mossy_ground", Z1, *t(0, 15)),    # zarostla zem
]
