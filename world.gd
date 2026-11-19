class_name TrialWorld
extends Node3D

## Static practice yard. Non-interactive rectangular geometry is submitted
## as one MultiMesh per finish. Targets retain their own physics identities.

var _materials: Dictionary = {}
var _boxes: Dictionary = {}
var _disc_mesh := CylinderMesh.new()


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
		_materials[finish] = material
		_boxes[finish] = []
	_disc_mesh.top_radius = 1.0
	_disc_mesh.bottom_radius = 1.0
	_disc_mesh.height = 1.0
	_disc_mesh.radial_segments = 32
	_disc_mesh.rings = 0


func _lighting() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("#779ca8")
	sky_material.sky_horizon_color = Color("#d8ddd0")
	sky_material.ground_horizon_color = sky_material.sky_horizon_color
	sky_material.ground_bottom_color = Color("#7b8581")
	sky_material.sun_angle_max = 8.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#dce8e9")
	env.ambient_light_energy = 0.62
	var environment_node := WorldEnvironment.new()
	environment_node.environment = env
	add_child(environment_node)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-53.0, -32.0, 0.0)
	sun.light_color = Color("#fff0d6")
	sun.light_energy = 1.0
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
		batch.mesh = unit
		batch.instance_count = transforms.size()
		for index in transforms.size():
			batch.set_instance_transform(index, transforms[index])
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
	_box(Vector3(-15.0, 3.3, -19), Vector3(5.2, 6.6, 29), "teal")
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


func _jump_course() -> void:
	var heights := [0.35, 0.70, 1.05, 1.4]
	for index in heights.size():
		var height: float = heights[index]
		var z: float = 2.0 - index * 2.8
		_box(Vector3(9.0, height * 0.5, z), Vector3(2.15, height, 1.8), "steel", true)
		_box(Vector3(9.0, height - 0.08, z + 0.91), Vector3(2.12, 0.12, 0.035), "yellow")
		_box(Vector3(8.05, height + 0.007, z), Vector3(0.08, 0.014, 1.75), "chalk")
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
	_disc(body, radius * 0.88, 0.074, 0.012, "orange")
	_disc(body, radius * 0.59, 0.085, 0.010, "chalk")
	_disc(body, radius * 0.42, 0.096, 0.010, "teal")
	_disc(body, radius * 0.14, 0.107, 0.010, "chalk")


func _disc(parent: Node3D, radius: float, z: float, depth: float, finish: String) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = _disc_mesh
	mesh.material_override = _materials[finish]
	var oriented_scale := Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(radius, depth, radius))
	mesh.transform = Transform3D(oriented_scale, Vector3(0, 0, z))
	parent.add_child(mesh)


func _sign(caption: String, center: Vector3, pixel: float, tint: Color) -> void:
	var label := Label3D.new()
	label.text = caption
	label.font_size = 64
	label.pixel_size = pixel
	label.outline_size = 0
	label.modulate = tint
	label.position = center
	label.double_sided = false
	add_child(label)
