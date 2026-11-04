class_name DayNight
extends CanvasModulate
## Denní doba 0 = den, 0.5 = soumrak, 1 = noc. Plynulý přechod barvy + signál pro světla a efekty.

signal time_changed(t: float)

const STAGES: Array[float] = [0.0, 0.5, 1.0]
const DAY := Color(1.0, 0.98, 0.93)
const DUSK := Color(0.86, 0.66, 0.6)
const NIGHT := Color(0.2, 0.25, 0.44)

var time := 0.0
var _tween: Tween


func set_time(t: float) -> void:
	time = clampf(t, 0.0, 1.0)
	color = DAY.lerp(DUSK, minf(time / 0.5, 1.0)) if time <= 0.5 else DUSK.lerp(NIGHT, (time - 0.5) / 0.5)
	time_changed.emit(time)


func go_to(t: float, duration := 2.0) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(set_time, time, t, duration)


func cycle() -> void:
	var i := 0
	for k in STAGES.size():
		if absf(STAGES[k] - time) < 0.01 or time > STAGES[k]:
			i = k
	go_to(STAGES[(i + 1) % STAGES.size()])


## Barva, která vyruší ztmavení (pro svítící efekty: plameny, světlušky).
func counter_color() -> Color:
	return Color(1.0 / maxf(color.r, 0.05), 1.0 / maxf(color.g, 0.05), 1.0 / maxf(color.b, 0.05), 1.0)
