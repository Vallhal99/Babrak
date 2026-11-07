class_name LightingProfile
extends RefCounted
## Osvětlení světa podle denní doby: klíčové snímky (hodina → parametry) v data/lighting.json, mezi nimi se plynule prolíná.
## Parametry (PARAMS) řídí slunce/měsíc, ambient, mlhu, záři, lampy, stíny mraků, světlušky i post-processing (grading, tilt-shift).
## Upravuje je nástroj LightingLab (F2 ve hře); uložení přepíše data/lighting.json.

const PATH := "res://data/lighting.json"
## [klíč, popisek, skupina, min, max, krok] – "color" místo rozsahu = barva; "angle" = úhel (prolíná se nejkratší cestou)
const PARAMS := [
	["sun_elev", "Výška slunce/měsíce °", "Slunce", 2.0, 88.0, 1.0],
	["sun_azim", "Směr stínů (azimut) °", "Slunce", 0.0, 360.0, 1.0, "angle"],
	["sun_color", "Barva slunce", "Slunce", "color"],
	["sun_energy", "Síla slunce", "Slunce", 0.0, 3.0, 0.01],
	["shadow_opacity", "Tmavost stínů", "Slunce", 0.0, 1.0, 0.01],
	["ambient_color", "Barva ambientu", "Okolí", "color"],
	["ambient_energy", "Síla ambientu", "Okolí", 0.0, 2.0, 0.01],
	["sky_color", "Barva pozadí", "Okolí", "color"],
	["fog_color", "Barva mlhy", "Okolí", "color"],
	["fog_density", "Hustota mlhy", "Okolí", 0.0, 0.05, 0.0005],
	["glow_intensity", "Záře (glow)", "Okolí", 0.0, 2.0, 0.01],
	["glow_threshold", "Práh záře", "Okolí", 0.0, 2.0, 0.01],
	["lamp_energy", "Lampy a pochodně", "Světla", 0.0, 8.0, 0.05],
	["fire_energy", "Táborák", "Světla", 0.0, 8.0, 0.05],
	["cloud_shadow", "Stíny mraků", "Atmosféra", 0.0, 1.0, 0.01],
	["fireflies", "Světlušky/prach", "Atmosféra", 0.0, 1.0, 0.01],
	["tilt_px", "Tilt-shift (rozostření okrajů)", "Obraz", 0.0, 8.0, 0.05],
	["tilt_width", "Šířka ostré pásky", "Obraz", 0.0, 1.0, 0.01],
	["bloom", "Bloom", "Obraz", 0.0, 2.0, 0.01],
	["saturation", "Sytost", "Obraz", 0.0, 2.0, 0.01],
	["contrast", "Kontrast", "Obraz", 0.5, 1.5, 0.01],
	["gain", "Barva světel (grading)", "Obraz", "color"],
	["shadow_tint", "Barva stínů (grading)", "Obraz", "color"],
	["vignette", "Vinětace", "Obraz", 0.0, 1.0, 0.01],
]
## Kvalita/efekty (jen Forward+/Mobile umí SSAO, DOF, objemovou mlhu; Compatibility je ignoruje)
const QUALITY := {"ssao": true, "ssao_radius": 1.2, "ssao_intensity": 1.6, "dof": true, "dof_amount": 0.08,
	"volumetric_fog": false, "volumetric_density": 0.012, "contact_shadows": true, "shadow_distance": 60.0}

var keys: Array = []
var quality: Dictionary = QUALITY.duplicate()


static func load_file(path := PATH) -> LightingProfile:
	var p := LightingProfile.new()
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		p.keys = d.get("keys", [])
		p.quality.merge(d.get("quality", {}), true)
	p.keys.sort_custom(func(a, b): return float(a.hour) < float(b.hour))
	return p


func save_file(path := PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"keys": keys, "quality": quality}, "\t"))


func value(k: Dictionary, key: String) -> Variant:
	for p in PARAMS:
		if p[0] == key:
			return Color.html(String(k[key])) if p[3] is String else float(k[key])
	return null


## Parametry v dané hodině (0–24): Dictionary klíč → float / Color.
func sample(hour: float) -> Dictionary:
	hour = fposmod(hour, 24.0)
	var n := keys.size()
	var i := 0
	while i < n and float(keys[i].hour) <= hour:
		i += 1
	var a: Dictionary = keys[(i - 1 + n) % n]
	var b: Dictionary = keys[i % n]
	var ha := float(a.hour)
	var hb := float(b.hour) + (24.0 if i >= n else 0.0)
	var h := hour + (24.0 if hour < ha else 0.0)
	var t := 0.0 if hb == ha else clampf((h - ha) / (hb - ha), 0.0, 1.0)
	t = t * t * (3.0 - 2.0 * t)
	var out := {}
	for p in PARAMS:
		var k: String = p[0]
		if p[3] is String:
			out[k] = Color.html(String(a[k])).lerp(Color.html(String(b[k])), t)
		elif p.size() > 6 and p[6] == "angle":
			out[k] = fposmod(float(a[k]) + angle_difference(deg_to_rad(float(a[k])), deg_to_rad(float(b[k]))) * t * 57.29578, 360.0)
		else:
			out[k] = lerpf(float(a[k]), float(b[k]), t)
	return out


func key_index_near(hour: float) -> int:
	var best := 0
	var bd := 99.0
	for i in keys.size():
		var d := absf(fposmod(float(keys[i].hour) - hour + 12.0, 24.0) - 12.0)
		if d < bd:
			bd = d
			best = i
	return best
