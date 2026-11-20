extends SceneTree
## godot --path . --audio-driver Dummy --script res://vm_solo.gd
## Model-review bench: shows each viewmodel weapon alone under a key light from
## two external cameras (right side, right-front-top) so grip / finger placement
## can be judged without the map. Presentation tooling only.

var _pending := ""


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-0.9, 0.5, 0.2)
	light.light_energy = 1.6
	scene.add_child(light)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(-0.4, -2.2, 0.0)
	fill.light_energy = 0.5
	scene.add_child(fill)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#5a6a72")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#8fa0a8")
	environment.ambient_light_energy = 0.7
	env.environment = environment
	scene.add_child(env)
	var camera := Camera3D.new()
	camera.fov = 40
	camera.near = 0.01
	scene.add_child(camera)
	camera.current = true
	var mats := VmWeapons.materials()
	var builds := [VmWeapons.build_rifle(mats), VmWeapons.build_pistol(mats), VmWeapons.build_knife(mats)]
	var names := ["rifle", "pistol", "knife"]
	for i in builds.size():
		var weapon: Node3D = builds[i]
		scene.add_child(weapon)
		for view in 2:
			if view == 0:
				camera.position = Vector3(1.15, 0.22, -0.05)
				camera.look_at(Vector3(0, -0.02, -0.10), Vector3.UP)
			else:
				camera.position = Vector3(0.60, 0.50, 0.75)
				camera.look_at(Vector3(0, -0.04, -0.12), Vector3.UP)
			await _shot("%s-solo%d" % [names[i], view])
		weapon.queue_free()
		await process_frame
	print("VM_SOLO done")
	quit(0)


func _shot(name_of_view: String) -> void:
	_pending = name_of_view
	RenderingServer.frame_post_draw.connect(_save, CONNECT_ONE_SHOT)
	await process_frame
	await process_frame


func _save() -> void:
	var image := root.get_texture().get_image()
	var filename := "vm-%s.png" % _pending
	var error := image.save_png("user://" + filename)
	print("VM_VIEW ", ProjectSettings.globalize_path("user://" + filename), " code=", error)