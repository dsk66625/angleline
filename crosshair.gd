extends Control

enum Shape { CROSS, T, DOT }

const LENGTH_MIN := 1
const LENGTH_MAX := 24
const GAP_MIN := 0
const GAP_MAX := 24
const THICKNESS_MIN := 1
const THICKNESS_MAX := 8
const REFERENCE_HEIGHT := 960.0
const DEFAULTS := {
	"shape": Shape.CROSS, "color": Color("#cdff7a"), "length": 5, "gap": 4,
	"thickness": 2, "dot": false, "outline": true, "dynamic": true,
}
const CS2_STATIC := {
	"shape": Shape.CROSS, "color": Color.GREEN, "length": 2, "gap": 1,
	"thickness": 2, "dot": false, "outline": false, "dynamic": false,
}
const OUTLINE_COLOR := Color("#202729")
const HIT_ARMS := [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]

var _style := DEFAULTS.duplicate()
var _spread := 0.0
var _pulsed := false
var _hit := false
var _render_height := 960


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
	set_notify_transform(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		queue_redraw()


func set_render_height(height: int) -> void:
	if height != _render_height:
		_render_height = height
		queue_redraw()


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
	# Draw on the render-target grid before the window applies black bars or stretch.
	# The preview and the HUD can each have a different scale and fractional origin.
	var canvas := get_global_transform_with_canvas()
	var origin := (canvas * (size * 0.5)).floor()
	draw_set_transform_matrix(canvas.affine_inverse() * Transform2D(0.0, origin))
	var pixels := float(_render_height) / REFERENCE_HEIGHT
	var color: Color = Color.WHITE if _pulsed else _style["color"]
	var thickness := maxi(1, roundi(float(_style["thickness"]) * pixels))
	var edge := -floori(thickness * 0.5)
	var odd := thickness % 2
	if _style["shape"] != Shape.DOT:
		var gap_units := float(_style["gap"])
		if _style["dynamic"]:
			gap_units += clampf(_spread * 4.0, 0.0, 26.0)
		var gap := roundi(gap_units * pixels)
		var length := maxi(1, roundi(float(_style["length"]) * pixels))
		var arms: Array[Rect2] = [
			Rect2(-gap - length, edge, length, thickness),
			Rect2(gap + odd, edge, length, thickness),
			Rect2(edge, gap + odd, thickness, length),
		]
		if _style["shape"] == Shape.CROSS:
			arms.append(Rect2(edge, -gap - length, thickness, length))
		if gap == 0 and odd == 1:
			arms.append(Rect2(0, 0, 1, 1))
		if _style["outline"]:
			for arm in arms:
				draw_rect(arm.grow(1.0), OUTLINE_COLOR)
		for arm in arms:
			draw_rect(arm, color)
	var center := Vector2.ONE * (odd * 0.5)
	if _style["dot"] or _style["shape"] == Shape.DOT:
		var radius := thickness * 0.5
		if _style["outline"]:
			draw_circle(center, radius + 1.0, OUTLINE_COLOR, true, -1.0, true)
		draw_circle(center, radius, color, true, -1.0, true)
	if _hit:
		draw_set_transform_matrix(Transform2D.IDENTITY)
		var hud_center := size * 0.5
		for direction: Vector2 in HIT_ARMS:
			draw_line(hud_center + direction * 7.0, hud_center + direction * 12.0, Color.WHITE, 2.0)
