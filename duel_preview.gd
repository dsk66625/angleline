extends SceneTree
## godot --path . --script res://duel_preview.gd [--fly]
## Art review for D/01: captures fixed review stands to
## .toolchain/duel-map-qa/duel-<name>.png. With --fly the camera stays open
## afterwards: WASD move, E/Q up/down, Shift boost, mouse look, Esc quit.

const Duel = preload("res://duel_world.gd")

## name, eye position, yaw, pitch. Yaw 0 looks -Z; PI looks +Z.
const VIEWS := [
	["spawn-a", Vector3(0, 1.65, 14.5), 0.0, -0.04],
	["mid", Vector3(-1.5, 1.65, 6.5), 0.15, -0.06],
	["high-line", Vector3(10.85, 2.72, 9.8), 1.35, -0.18],
	["corner", Vector3(-8.2, 1.65, 10.8), 0.0, -0.05],
	["low-line", Vector3(-10.85, 1.25, 8.6), 0.0, -0.08],
	["drop", Vector3(10.85, 2.72, 1.0), 1.9, -0.35],
	["spawn-b", Vector3(0, 1.65, -14.5), PI, -0.04],
	["overview", Vector3(0, 30, 24), 0.0, -0.95],
]

var world: Duel
var camera: Camera3D
var fly := false
var fly_yaw := 0.0
var fly_pitch := -0.4


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("duel_preview needs a graphics client; run without --headless.")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	world = Duel.new()
	root.add_child(world)
	camera = Camera3D.new()
	camera.fov = 73.739795
	camera.near = 0.035
	camera.far = 220.0
	root.add_child(camera)
	camera.current = true
	await physics_frame
	var boxes := 0
	for finish in world._boxes:
		boxes += world._boxes[finish].size()
	var solids := 0
	for child in world.get_children():
		if child is StaticBody3D:
			solids += 1
	print("DUEL_MAP id=", Duel.MAP_ID, " name=", Duel.MAP_NAME, " boxes=", boxes, " solids=", solids, " bounds=", Duel.BOUNDS)
	var directory := ProjectSettings.globalize_path("res://.toolchain/duel-map-qa")
	DirAccess.make_dir_recursive_absolute(directory)
	for view in VIEWS:
		camera.position = view[1]
		camera.rotation = Vector3(view[3], view[2], 0.0)
		await physics_frame
		await RenderingServer.frame_post_draw
		_save(directory, view[0])
	if "--fly" in OS.get_cmdline_user_args():
		fly = true
		fly_yaw = camera.rotation.y
		fly_pitch = camera.rotation.x
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		print("DUEL_FLY WASD move | E/Q up/down | Shift boost | mouse look | Esc quit")
	else:
		print("DUEL_PREVIEW done")
		quit(0)


func _save(directory: String, name_of_view: String) -> void:
	var image := root.get_texture().get_image()
	var path := directory + "/duel-%s.png" % name_of_view
	var error := image.save_png(path)
	print("DUEL_VIEW ", path, " code=", error, " size=", image.get_size())


func _process(delta: float) -> bool:
	if not fly:
		return false
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		direction.z -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		direction.z += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE):
		direction.y += 1.0
	if Input.is_physical_key_pressed(KEY_Q):
		direction.y -= 1.0
	var speed := 16.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 5.0
	if direction.length_squared() > 0.0:
		camera.position += camera.global_basis * (direction.normalized() * speed * delta)
	camera.rotation = Vector3(fly_pitch, fly_yaw, 0.0)
	return false


func _input(event: InputEvent) -> void:
	if not fly:
		return
	if event is InputEventMouseMotion:
		fly_yaw -= event.relative.x * 0.0022
		fly_pitch = clampf(fly_pitch - event.relative.y * 0.0022, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and event.physical_keycode == KEY_ESCAPE:
		quit(0)