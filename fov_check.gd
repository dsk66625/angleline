extends SceneTree
## godot --headless --resolution 2560x1440 --path . --script res://fov_check.gd
## All coordinates start at the top left. Pixels denote continuous image positions.

const OUTPUT := Vector2i(2560, 1440)
const CLASSIC := Vector2i(1280, 960)
const TESTS := [
	{"label": "16:9 native", "view": 0, "size": OUTPUT},
	{"label": "4:3 centered", "view": 1, "size": CLASSIC},
	{"label": "4:3 stretched", "view": 2, "size": CLASSIC},
]
const ANGLES := {
	"center": Vector2.ZERO,
	"left_45": Vector2(-45, 0), "right_45": Vector2(45, 0),
	"left_30": Vector2(-30, 0), "right_30": Vector2(30, 0),
	"up_30": Vector2(0, 30), "down_30": Vector2(0, -30),
	"up_45": Vector2(0, 45), "down_45": Vector2(0, -45),
}
const ANGLE_TOLERANCE := 0.002
const PIXEL_TOLERANCE := 0.02

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() != "headless":
		push_error("Use --headless. The probe does not require a desktop window.")
		quit(1)
		return
	root.size = OUTPUT
	if change_scene_to_file("res://main.tscn") != OK:
		push_error("Failed to instantiate the game scene.")
		quit(1)
		return
	await scene_changed
	var game := current_scene
	var camera: Camera3D = game.get("camera")
	for setting: Dictionary in TESTS:
		var size: Vector2i = setting["size"]
		var options: Dictionary = game.get("options")
		options["resolution"] = size
		options["view"] = setting["view"]
		options["fullscreen"] = false
		game.call("_apply_options")
		await process_frame
		var viewport_size := root.get_visible_rect().size
		var window_transform := root.get_screen_transform()
		window_transform.origin -= Vector2(root.position)
		var h := _ray_angles(camera, Vector2(viewport_size.x, viewport_size.y * 0.5)).x - _ray_angles(camera, Vector2(0.0, viewport_size.y * 0.5)).x
		var v := _ray_angles(camera, Vector2(viewport_size.x * 0.5, 0.0)).y - _ray_angles(camera, Vector2(viewport_size.x * 0.5, viewport_size.y)).y
		_expect(viewport_size == Vector2(size), "%s viewport %s" % [setting["label"], viewport_size])
		_expect(absf(h - (106.260205 if setting["view"] == 0 else 90.0)) < ANGLE_TOLERANCE, "Horizontal FOV: %s" % h)
		_expect(absf(v - 73.739795) < ANGLE_TOLERANCE, "Vertical FOV: %s" % v)
		var output_left: Vector2 = window_transform * Vector2.ZERO
		var output_right: Vector2 = window_transform * viewport_size
		var inset := 320.0 if setting["view"] == 1 else 0.0
		_expect(output_left.distance_to(Vector2(inset, 0)) < PIXEL_TOLERANCE, "Output top left: %s" % output_left)
		_expect(output_right.distance_to(Vector2(OUTPUT.x - inset, OUTPUT.y)) < PIXEL_TOLERANCE, "Output bottom right: %s" % output_right)
		print("FOV %s | internal=%s output=%s..%s | H=%.6f V=%.6f" % [setting["label"], size, output_left, output_right, h, v])

		for label: String in ANGLES:
			var angles: Vector2 = ANGLES[label]
			# Position a marker 8 metres forward relative to the real scene camera.
			var tangent := Vector2(tan(deg_to_rad(angles.x)), tan(deg_to_rad(angles.y)))
			var marker := camera.get_camera_transform() * Vector3(tangent.x * 8.0, tangent.y * 8.0, -8.0)
			var point := camera.unproject_position(marker)
			var expected := Vector2(size) * 0.5 + Vector2(tangent.x, -tangent.y) * (size.y * 2.0 / 3.0)
			_expect(point.distance_to(expected) < PIXEL_TOLERANCE, "%s %s measured=%s expected=%s" % [setting["label"], label, point, expected])
			var recovered := _ray_angles(camera, point)
			_expect(recovered.distance_to(angles) < ANGLE_TOLERANCE, "%s inverse angles %s" % [label, recovered])
			print("  %s | internal=(%.3f, %.3f) | output=(%.3f, %.3f)" % [label, point.x, point.y,
				(window_transform * point).x, (window_transform * point).y])
	for problem in failures:
		push_error(problem)
	print("FOV_CHECK errors=", failures.size())
	quit(0 if failures.is_empty() else 1)


func _ray_angles(camera: Camera3D, pixel: Vector2) -> Vector2:
	var ray := camera.get_camera_transform().basis.inverse() * camera.project_ray_normal(pixel)
	return Vector2(rad_to_deg(atan2(ray.x, -ray.z)), rad_to_deg(atan2(ray.y, Vector2(ray.x, ray.z).length())))


func _expect(ok: bool, problem: String) -> void:
	if not ok:
		failures.append(problem)
