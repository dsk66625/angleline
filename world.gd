class_name TrialWorld
extends Node3D

## Static practice yard. Non-interactive rectangular geometry is submitted
## as one MultiMesh per finish. Targets retain their own physics identities.

var _materials: Dictionary = {}
var _boxes: Dictionary = {}
var _disc_mesh := CylinderMesh.new()

## Finishes whose batched boxes get a small per-instance value jitter so large
## flat surfaces do not read as a single CAD colour.
const _JITTERED := ["floor", "concrete", "cream", "steel", "teal", "deep", "charcoal", "rubber"]


func _ready() -> void:
	_palette()
	_lighting()
	_structure()
	_range_markings()
	_jump_course()
	_target(1, Vector3(-4.7, 1.52, -9.5), 0.57)
	_target(2, Vector3(0.15, 1.52, -17.0), 0.62)
	_target(3, Vector3(4.15, 1.64, -27.5), 0.70)
	_target(4, Vector3(-2.35, 1.68, -38.0), 0.78)
	_build_batches()


func _palette() -> void:
	var colors := {
		"floor": "#707b78", "concrete": "#9da6a0", "cream": "#d3cdb6",
		"charcoal": "#26383d", "steel": "#476268", "deep": "#203137",
		"teal": "#3d7376", "mint": "#a0cfbe", "yellow": "#efba4f",
		"orange": "#f27c40", "chalk": "#ebe8d5", "rubber": "#354347"
	}
	for finish in colors:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(colors[finish])
		material.roughness = 0.92
		material.vertex_color_use_as_albedo = true
		_materials[finish] = material
		_boxes[finish] = []
	# Procedural concrete: mottling plus an expansion joint per tile. The floor
	# tile is 2 m; wall panels reuse the same image at a wider period.
	var floor_material: StandardMaterial3D = _materials["floor"]
	floor_material.albedo_texture = _surface_texture(71, 0.16)
	floor_material.uv1_scale = Vector3(13, 29, 1)
	var concrete_material: StandardMaterial3D = _materials["concrete"]
	concrete_material.albedo_texture = _surface_texture(143, 0.07)
	concrete_material.uv1_scale = Vector3(14.5, 2, 1)
	# Emissive finishes keep the target ring and gantry lamps readable far down
	# the range without adding real lights.
	var ring := StandardMaterial3D.new()
	ring.albedo_color = Color(colors["orange"])
	ring.roughness = 0.6
	ring.emission_enabled = true
	ring.emission = Color(colors["orange"])
	ring.emission_energy_multiplier = 0.35
	ring.vertex_color_use_as_albedo = true
	_materials["ring"] = ring
	_boxes["ring"] = []
	var lamp := StandardMaterial3D.new()
	lamp.albedo_color = Color("#f6efd8")
	lamp.roughness = 0.5
	lamp.emission_enabled = true
	lamp.emission = Color("#f6e7bd")
	lamp.emission_energy_multiplier = 1.4
	lamp.vertex_color_use_as_albedo = true
	_materials["lamp"] = lamp
	_boxes["lamp"] = []
	_disc_mesh.top_radius = 1.0
	_disc_mesh.bottom_radius = 1.0
	_disc_mesh.height = 1.0
	_disc_mesh.radial_segments = 32
	_disc_mesh.rings = 0


func _surface_texture(seed_value: int, frequency: float) -> ImageTexture:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	var image := Image.create(128, 128, false, Image.FORMAT_RGB8)
	for y in 128:
		for x in 128:
			var value := 0.95 + 0.05 * noise.get_noise_2d(x, y)
			# Low-contrast 2 px joint: a 1 px hard line moires at grazing angles
			# once mipmaps kick in on the long walls.
			if x < 2 or y < 2:
				value = 0.80
			image.set_pixel(x, y, Color(value, value, value))
	return ImageTexture.create_from_image(image)


func _lighting() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#6f96a6")
	sky_material.sky_horizon_color = Color("#dfe3d4")
	sky_material.ground_horizon_color = sky_material.sky_horizon_color
	sky_material.ground_bottom_color = Color("#7b8581")
	sky_material.sun_angle_max = 6.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#d7e4e6")
	env.ambient_light_energy = 0.45
	env.fog_enabled = true
	env.fog_light_color = Color("#c9d4cf")
	env.fog_density = 0.0055
	env.fog_sky_affect = 0.25
	var environment_node := WorldEnvironment.new()
	environment_node.environment = env
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-56.0, -32.0, 0.0)
	sun.light_color = Color("#ffe9c8")
	sun.light_energy = 1.12
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 52.0
	add_child(sun)


func _box(center: Vector3, size: Vector3, finish: String, solid: bool = false) -> void:
	var transforms: Array = _boxes[finish]
	transforms.append(Transform3D(Basis.from_scale(size), center))
	if solid:
		var body := StaticBody3D.new()
		body.position = center
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		body.add_child(collider)
		add_child(body)


func _build_batches() -> void:
	var unit := BoxMesh.new()
	unit.size = Vector3.ONE
	for finish in _boxes:
		var transforms: Array = _boxes[finish]
		if transforms.is_empty():
			continue
		var batch := MultiMesh.new()
		batch.transform_format = MultiMesh.TRANSFORM_3D
		batch.use_colors = true
		batch.mesh = unit
		batch.instance_count = transforms.size()
		for index in transforms.size():
			batch.set_instance_transform(index, transforms[index])
			var tint := Color.WHITE
			if finish in _JITTERED:
				var value := 1.0 + (float(absi(hash(finish + str(index))) % 997) / 997.0 - 0.5) * 0.06
				tint = Color(value, value, value)
			batch.set_instance_color(index, tint)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = batch
		instance.material_override = _materials[finish]
		add_child(instance)


func _structure() -> void:
	_box(Vector3(0, -0.25, -15), Vector3(26, 0.5, 58), "floor", true)
	_box(Vector3(0, 2.25, 13.7), Vector3(26, 4.5, 0.6), "concrete", true)
	_box(Vector3(0, 3.5, -43.6), Vector3(26, 7, 0.7), "cream", true)
	_box(Vector3(0, 0.85, -43.17), Vector3(26, 1.7, 0.15), "teal")
	_box(Vector3(0, 1.82, -43.17), Vector3(26, 0.13, 0.15), "orange")
	_box(Vector3(0, 6.98, -43.5), Vector3(26.3, 0.27, 0.85), "charcoal")
	for x in [-12.7, 12.7]:
		_box(Vector3(x, 2.0, -15), Vector3(0.6, 4, 58), "concrete", true)
		_box(Vector3(x, 3.99, -15), Vector3(0.8, 0.20, 58.2), "charcoal")
		_box(Vector3(x * 0.974, 0.46, -15), Vector3(0.08, 0.92, 57.3), "steel")
		for z in range(-40, 13, 6):
			_box(Vector3(x * 0.964, 2.0, z), Vector3(0.27, 4.0, 0.32), "cream")
	# A ribbed service annex and clerestory form the western skyline.
	# Inner face recessed 6 cm behind the side wall face: coplanar faces
	# z-fought at grazing angles over the shared z span.
	_box(Vector3(-15.06, 3.3, -19), Vector3(5.2, 6.6, 29), "teal")
	_box(Vector3(-14.9, 6.67, -19), Vector3(6.1, 0.24, 30), "charcoal")
	for z in range(-32, -4, 2):
		_box(Vector3(-12.33, 5.45, z), Vector3(0.12, 1.05, 1.72), "deep")
		_box(Vector3(-12.23, 5.89, z), Vector3(0.12, 0.10, 1.72), "mint")
	# A simple gantry gives the sight line a readable frame.
	for x in [-10.7, 10.7]:
		_box(Vector3(x, 2.6, -30), Vector3(0.44, 5.2, 0.55), "steel", true)
		_box(Vector3(x, 0.6, -30), Vector3(0.66, 1.2, 0.72), "yellow", true)
	_box(Vector3(0, 5.25, -30), Vector3(21.9, 0.52, 0.62), "steel", true)
	_box(Vector3(0, 5.25, -29.68), Vector3(3.9, 0.49, 0.05), "yellow")
	_sign("RANGE    /    03", Vector3(0, 5.25, -29.63), 0.0047, Color("#233437"))
	_sign("ANGLE   /   FIELD", Vector3(0, 4.3, -43.18), 0.021, Color("#324e52"))
	# The right edge of this panel sits just left of the spawn aim line.
	_box(Vector3(-1.85, 1.28, 1.00), Vector3(3.2, 2.56, 0.65), "teal", true)
	_box(Vector3(-1.85, 2.53, 1.0), Vector3(3.27, 0.12, 0.72), "charcoal")
	_box(Vector3(-0.37, 1.26, 1.34), Vector3(0.18, 2.38, 0.035), "orange")
	_sign("C   /   01", Vector3(-1.9, 1.58, 1.35), 0.0095, Color("#e9e5d0"))
	_sign("CORNER", Vector3(-1.9, 1.06, 1.35), 0.0042, Color("#b5dbcb"))
	# Distant silhouettes give the skyline depth; they sit outside the walls
	# and carry no collision.
	_box(Vector3(-23, 5.0, -26), Vector3(9, 10, 16), "deep")
	_box(Vector3(-21, 8.6, -12), Vector3(6, 4.4, 9), "steel")
	_box(Vector3(21, 3.5, -9), Vector3(7, 7, 12), "steel")
	_box(Vector3(25, 6.0, -31), Vector3(11, 12, 18), "deep")
	_box(Vector3(19, 10.4, -24), Vector3(4, 1.6, 5), "charcoal")
	# Roof plant on the western annex.
	for z in [-28, -19, -10]:
		_box(Vector3(-15.2, 7.15, z), Vector3(1.5, 0.8, 1.5), "charcoal")
		_box(Vector3(-15.2, 7.62, z), Vector3(1.1, 0.14, 1.1), "steel")
	_box(Vector3(-12.6, 6.95, -19), Vector3(0.22, 0.22, 28), "steel")
	# Lamp fixtures under the gantry beam (emissive only, no extra lights).
	for x in [-8.0, -2.7, 2.7, 8.0]:
		_box(Vector3(x, 4.94, -30), Vector3(0.62, 0.10, 0.34), "lamp")
		_box(Vector3(x, 5.02, -30), Vector3(0.10, 0.16, 0.10), "charcoal")
	# Ready bench against the rear wall, seen when turning around at spawn.
	_box(Vector3(0, 0.46, 13.05), Vector3(7, 0.14, 0.55), "steel", true)
	_box(Vector3(0, 0.86, 13.32), Vector3(7, 0.62, 0.10), "steel", true)
	for x in [-3.2, -1.1, 1.1, 3.2]:
		_box(Vector3(x, 0.20, 13.05), Vector3(0.12, 0.40, 0.5), "rubber", true)
	_sign("READY   /   LINE", Vector3(0, 2.7, 13.38), 0.012, Color("#324e52"), PI)


func _range_markings() -> void:
	for x in [-7.3, 6.2]:
		_box(Vector3(x, 0.009, -15.1), Vector3(0.10, 0.018, 54.0), "chalk")
	for z in range(-39, 10, 3):
		_box(Vector3(-6.94, 0.011, z), Vector3(0.6, 0.02, 0.075), "chalk")
		_box(Vector3(6.47, 0.011, z), Vector3(0.4, 0.02, 0.075), "chalk")
	_box(Vector3(0, 0.012, 3.6), Vector3(12.5, 0.024, 0.10), "yellow")
	for x in range(-6, 7, 2):
		_box(Vector3(x, 0.013, 3.85), Vector3(0.09, 0.024, 0.44), "yellow")
	for z in [-10, -20, -30, -39]:
		_box(Vector3(-8.7, 0.37, z), Vector3(1.48, 0.74, 0.22), "charcoal", true)
		_sign("%02d" % absi(z), Vector3(-8.7, 0.39, z + 0.13), 0.0074, Color("#f5c36b"))
	# Service lane dressing between the distance boards and the west wall.
	# Kept clear of the speed lane (z~8) and the Plate_01 melee area.
	var stack := 0
	for z in [-33, -23, -13, -3, 5]:
		_box(Vector3(-11.1, 0.475, z), Vector3(1.15, 0.95, 1.15), "cream", true)
		_box(Vector3(-11.1, 0.99, z), Vector3(1.19, 0.08, 1.19), "charcoal")
		if stack % 2 == 1:
			_box(Vector3(-11.0, 1.38, z + 0.1), Vector3(0.8, 0.7, 0.8), "steel", true)
		stack += 1
	for z in [-26.4, -6.4, 3.6]:
		_barrel(Vector3(-10.3, 0.45, z))


func _barrel(center: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = center
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.34
	shape.height = 0.9
	collider.shape = shape
	body.add_child(collider)
	add_child(body)
	var shell := MeshInstance3D.new()
	shell.mesh = _disc_mesh
	shell.material_override = _materials["rubber"]
	shell.transform = Transform3D(Basis.from_scale(Vector3(0.34, 0.9, 0.34)), Vector3.ZERO)
	body.add_child(shell)
	var band := MeshInstance3D.new()
	band.mesh = _disc_mesh
	band.material_override = _materials["mint"]
	band.transform = Transform3D(Basis.from_scale(Vector3(0.345, 0.12, 0.345)), Vector3(0, 0.18, 0))
	body.add_child(band)


func _jump_course() -> void:
	var heights := [0.35, 0.70, 1.05, 1.4]
	for index in heights.size():
		var height: float = heights[index]
		var z: float = 2.0 - index * 2.8
		_box(Vector3(9.0, height * 0.5, z), Vector3(2.15, height, 1.8), "steel", true)
		_box(Vector3(9.0, height - 0.08, z + 0.91), Vector3(2.12, 0.12, 0.035), "yellow")
		_box(Vector3(8.05, height + 0.007, z), Vector3(0.08, 0.014, 1.75), "chalk")
		_sign("0%d" % (index + 1), Vector3(9.0, height * 0.5 - 0.075, z + 0.905), 0.003, Color("#e9e5d0"))
	_box(Vector3(9.0, 1.0, -11.0), Vector3(3.1, 2.0, 0.35), "teal", true)
	_sign("JUMP   /   04", Vector3(9.0, 1.36, -10.79), 0.0075, Color("#e9e5d0"))


func _target(id: int, center: Vector3, radius: float) -> void:
	_box(Vector3(center.x, 0.09, center.z), Vector3(1.38, 0.18, 0.88), "rubber", true)
	_box(Vector3(center.x, center.y * 0.48, center.z - 0.13), Vector3(0.19, center.y, 0.23), "steel", true)
	var body := StaticBody3D.new()
	body.name = "Plate_%02d" % id
	body.position = center
	body.add_to_group("practice_target")
	body.set_meta("target_id", id)
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.height = 0.14
	shape.radius = radius
	collider.shape = shape
	collider.rotation.x = PI * 0.5
	body.add_child(collider)
	add_child(body)
	_disc(body, radius, 0.0, 0.14, "charcoal")
	_disc(body, radius * 0.88, 0.074, 0.012, "ring")
	_disc(body, radius * 0.59, 0.085, 0.010, "chalk")
	_disc(body, radius * 0.42, 0.096, 0.010, "teal")
	_disc(body, radius * 0.14, 0.107, 0.010, "chalk")
	_sign("%02d" % id, Vector3(center.x, 0.09, center.z + 0.445), 0.003, Color("#ebe8d5"))


func _disc(parent: Node3D, radius: float, z: float, depth: float, finish: String) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _disc_mesh
	mesh.material_override = _materials[finish]
	var oriented_scale := Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(radius, depth, radius))
	mesh.transform = Transform3D(oriented_scale, Vector3(0, 0, z))
	parent.add_child(mesh)


func _sign(caption: String, center: Vector3, pixel: float, tint: Color, rotation_y: float = 0.0) -> void:
	var label := Label3D.new()
	label.text = caption
	label.font_size = 64
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = tint
	label.position = center
	label.rotation.y = rotation_y
	label.double_sided = false
	add_child(label)
