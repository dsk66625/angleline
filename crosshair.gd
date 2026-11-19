extends Control

enum Shape { CROSS, T, DOT }

const LENGTH_MIN := 1
const LENGTH_MAX := 24
const GAP_MIN := 0
const GAP_MAX := 24
const THICKNESS_MIN := 1
const THICKNESS_MAX := 8
const DEFAULTS := {
	"shape": Shape.CROSS, "color": Color("#cdff7a"), "length": 5, "gap": 4,
	"thickness": 2, "dot": false, "outline": true, "dynamic": true,
}
const OUTLINE_COLOR := Color("#202729")
const ARMS := [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]
const HIT_ARMS := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]

var _style := DEFAULTS.duplicate()
var _spread := 0.0
var _pulsed := false
var _hit := false


static func normalize(raw: Variant) -> Dictionary:
	var style := DEFAULTS.duplicate()
	if raw is not Dictionary:
		return style
	for key in DEFAULTS:
		if raw.has(key) and typeof(raw[key]) == typeof(DEFAULTS[key]):
			style[key] = raw[key]
	if style["shape"] not in [Shape.CROSS, Shape.T, Shape.DOT]:
		style["shape"] = Shape.CROSS
	style["length"] = clampi(style["length"], LENGTH_MIN, LENGTH_MAX)
	style["gap"] = clampi(style["gap"], GAP_MIN, GAP_MAX)
	style["thickness"] = clampi(style["thickness"], THICKNESS_MIN, THICKNESS_MAX)
	var color: Color = style["color"]
	if is_finite(color.r) and is_finite(color.g) and is_finite(color.b):
		style["color"] = Color(clampf(color.r, 0.0, 1.0), clampf(color.g, 0.0, 1.0), clampf(color.b, 0.0, 1.0))
	else:
		style["color"] = DEFAULTS["color"]
	return style


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func apply_style(values: Dictionary) -> void:
	var style := normalize(values)
	if style != _style:
		_style = style
		queue_redraw()


func set_feedback(spread: float, pulsed: bool, hit: bool) -> void:
	if pulsed != _pulsed or hit != _hit or (spread != _spread and _style["dynamic"] and _style["shape"] != Shape.DOT):
		queue_redraw()
	_spread = spread
	_pulsed = pulsed
	_hit = hit


func _draw() -> void:
	var center := size * 0.5
	var color: Color = Color.WHITE if _pulsed else _style["color"]
	var thickness := float(_style["thickness"])
	if _style["shape"] != Shape.DOT:
		var gap := float(_style["gap"])
		if _style["dynamic"]:
			gap += clampf(_spread * 4.0, 0.0, 26.0)
		for direction: Vector2 in ARMS:
			if _style["shape"] == Shape.T and direction == Vector2.UP:
				continue
			var start := center + direction * gap
			var finish := start + direction * float(_style["length"])
			if _style["outline"]:
				draw_line(start, finish, OUTLINE_COLOR, thickness + 2.0)
			draw_line(start, finish, color, thickness)
	if _style["dot"] or _style["shape"] == Shape.DOT:
		var radius := thickness * 0.5
		if _style["outline"]:
			draw_circle(center, radius + 1.0, OUTLINE_COLOR, true, -1.0, true)
		draw_circle(center, radius, color, true, -1.0, true)
	if _hit:
		for direction: Vector2 in HIT_ARMS:
			draw_line(center + direction * 7.0, center + direction * 12.0, Color.WHITE, 2.0)
