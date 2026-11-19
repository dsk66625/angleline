class_name VmWeapons
extends RefCounted

## First-person weapon and hand models, built in code to match the yard's
## flat-shaded finish. Static parts (including hands) are merged into one
## ArrayMesh surface per material; only reload-moving parts stay separate
## nodes so the viewmodel stays under ten draw calls per weapon.
## Weapon forward is -Z, matching the camera. Roots carry a "muzzle" meta
## with the local flash position.

const SKIN := "#c49a7a"
const GLOVE := "#354347"


static func materials() -> Dictionary:
	var out := {}
	for key in ["metal", "wood", "polymer", "bright", "skin", "glove", "dark", "flash"]:
		var material := StandardMaterial3D.new()
		material.roughness = 0.85
		out[key] = material
	out["metal"].albedo_color = Color("#39424a")
	out["metal"].metallic = 0.35
	out["wood"].albedo_color = Color("#7a4a2b")
	out["wood"].roughness = 0.7
	out["polymer"].albedo_color = Color("#22282b")
	out["bright"].albedo_color = Color("#8fa0a6")
	out["bright"].metallic = 0.3
	out["bright"].roughness = 0.5
	out["blade"] = out["bright"].duplicate()
	out["blade"].cull_mode = BaseMaterial3D.CULL_DISABLED
	out["skin"].albedo_color = Color(SKIN)
	out["glove"].albedo_color = Color(GLOVE)
	out["dark"].albedo_color = Color("#1a1f22")
	out["flash"].albedo_color = Color("#f9d38d")
	out["flash"].emission_enabled = true
	out["flash"].emission = Color("#f9d38d")
	out["flash"].emission_energy_multiplier = 2.2
	return out


static func _box(parts: Dictionary, key: String, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add(parts, key, mesh, pos, rot)


static func _cyl(parts: Dictionary, key: String, radius: float, height: float, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	_add(parts, key, mesh, pos, rot)


static func _prism(parts: Dictionary, key: String, size: Vector3, pos: Vector3, rot := Vector3.ZERO, taper := 0.5) -> void:
	var mesh := PrismMesh.new()
	mesh.size = size
	mesh.left_to_right = taper
	_add(parts, key, mesh, pos, rot)


static func _torus(parts: Dictionary, key: String, radius: float, tube: float, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - tube
	mesh.outer_radius = radius + tube
	mesh.rings = 12
	mesh.ring_segments = 8
	_add(parts, key, mesh, pos, rot)


static func _add(parts: Dictionary, key: String, mesh: Mesh, pos: Vector3, rot: Vector3) -> void:
	if not parts.has(key):
		parts[key] = []
	var basis := Basis.from_euler(rot)
	parts[key].append([mesh, Transform3D(basis, pos)])


static func _merged(parts: Dictionary, mats: Dictionary) -> MeshInstance3D:
	var array := ArrayMesh.new()
	for key in parts:
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var indices := PackedInt32Array()
		for entry in parts[key]:
			var mesh: Mesh = entry[0]
			var tf: Transform3D = entry[1]
			for surface_index in mesh.get_surface_count():
				var data := mesh.surface_get_arrays(surface_index)
				var v: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
				var n: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
				var idx: PackedInt32Array = data[Mesh.ARRAY_INDEX] if data[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var base := verts.size()
				for i in v.size():
					verts.append(tf * v[i])
					norms.append(tf.basis * n[i])
				if idx.is_empty():
					for i in v.size():
						indices.append(base + i)
				else:
					for i in idx:
						indices.append(base + i)
		var surface := Array()
		surface.resize(Mesh.ARRAY_MAX)
		surface[Mesh.ARRAY_VERTEX] = verts
		surface[Mesh.ARRAY_NORMAL] = norms
		surface[Mesh.ARRAY_INDEX] = indices
		array.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
		array.surface_set_material(array.get_surface_count() - 1, mats[key])
	var instance := MeshInstance3D.new()
	instance.mesh = array
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _moving(parts: Dictionary, mats: Dictionary, pivot: Vector3) -> Node3D:
	var node := Node3D.new()
	node.position = pivot
	var shifted := {}
	for key in parts:
		shifted[key] = []
		for entry in parts[key]:
			var tf: Transform3D = entry[1]
			shifted[key].append([entry[0], Transform3D(tf.basis, tf.origin - pivot)])
	node.add_child(_merged(shifted, mats))
	return node


static func _flash(mats: Dictionary, pos: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.075, 0.075, 0.10)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = mats["flash"]
	instance.name = "Flash"
	instance.position = pos
	instance.visible = false
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _forearm(parts: Dictionary, pos: Vector3, rot: Vector3, length := 0.16) -> void:
	_box(parts, "glove", Vector3(0.052, 0.052, length), pos, rot)
	var wrist := Basis.from_euler(rot) * Vector3(0, 0, length * 0.5 + 0.012)
	_box(parts, "skin", Vector3(0.046, 0.046, 0.03), pos + wrist, rot)


static func build_rifle(mats: Dictionary, hands := true) -> Node3D:
	var root := Node3D.new()
	root.name = "RifleAK"
	var parts := {}
	# Receiver, dust cover and sights.
	_box(parts, "metal", Vector3(0.058, 0.085, 0.33), Vector3(0, 0, 0.02))
	_box(parts, "metal", Vector3(0.05, 0.02, 0.30), Vector3(0, 0.05, 0.02))
	_box(parts, "dark", Vector3(0.02, 0.025, 0.03), Vector3(0, 0.068, 0.13))
	_box(parts, "metal", Vector3(0.03, 0.03, 0.02), Vector3(0, 0.055, -0.14))
	# Barrel, gas tube, front sight and slant brake.
	_cyl(parts, "metal", 0.011, 0.30, Vector3(0, 0.012, -0.42), Vector3(PI * 0.5, 0, 0))
	_cyl(parts, "metal", 0.009, 0.20, Vector3(0, 0.045, -0.33), Vector3(PI * 0.5, 0, 0))
	_box(parts, "metal", Vector3(0.024, 0.045, 0.025), Vector3(0, 0.045, -0.52))
	_box(parts, "dark", Vector3(0.026, 0.026, 0.05), Vector3(0, 0.012, -0.585), Vector3(0, 0, 0.5))
	# Wood handguard with groove ribs, stock and grip.
	_box(parts, "wood", Vector3(0.056, 0.062, 0.20), Vector3(0, -0.005, -0.26))
	_box(parts, "wood", Vector3(0.06, 0.014, 0.16), Vector3(0, 0.032, -0.26))
	_box(parts, "dark", Vector3(0.058, 0.006, 0.012), Vector3(0, -0.005, -0.22))
	_box(parts, "dark", Vector3(0.058, 0.006, 0.012), Vector3(0, -0.005, -0.30))
	_box(parts, "wood", Vector3(0.048, 0.085, 0.20), Vector3(0, -0.02, 0.26), Vector3(-0.12, 0, 0))
	_box(parts, "dark", Vector3(0.05, 0.095, 0.02), Vector3(0, -0.032, 0.36), Vector3(-0.12, 0, 0))
	_box(parts, "wood", Vector3(0.036, 0.09, 0.045), Vector3(0, -0.085, 0.10), Vector3(0.35, 0, 0))
	_box(parts, "dark", Vector3(0.012, 0.03, 0.07), Vector3(0, -0.06, 0.045))
	# Trigger guard.
	_box(parts, "dark", Vector3(0.01, 0.008, 0.075), Vector3(0, -0.075, 0.02))
	_box(parts, "dark", Vector3(0.01, 0.03, 0.008), Vector3(0, -0.06, -0.015))
	# Firing hand on the grip plus support hand under the handguard.
	if hands:
		_box(parts, "glove", Vector3(0.055, 0.075, 0.06), Vector3(0.005, -0.095, 0.10), Vector3(0.35, 0, 0))
		_box(parts, "glove", Vector3(0.05, 0.035, 0.045), Vector3(0.005, -0.082, 0.055), Vector3(0.2, 0, 0))
		_box(parts, "glove", Vector3(0.016, 0.022, 0.05), Vector3(0.032, -0.062, 0.09), Vector3(0.3, 0, -0.2))
		_forearm(parts, Vector3(0.06, -0.15, 0.20), Vector3(-0.5, -0.25, 0))
		_box(parts, "glove", Vector3(0.06, 0.05, 0.095), Vector3(-0.005, -0.048, -0.26))
		_box(parts, "glove", Vector3(0.02, 0.045, 0.085), Vector3(-0.036, -0.018, -0.26), Vector3(0, 0, 0.35))
		_box(parts, "glove", Vector3(0.02, 0.02, 0.075), Vector3(0.03, 0.012, -0.26), Vector3(0, 0, -0.2))
		_forearm(parts, Vector3(-0.07, -0.13, -0.14), Vector3(-0.6, 0.35, 0), 0.18)
	root.add_child(_merged(parts, mats))
	# Curved magazine: three canted segments, pivoted at the well.
	var mag := {}
	_box(mag, "metal", Vector3(0.042, 0.075, 0.055), Vector3(0, -0.035, 0), Vector3(0.10, 0, 0))
	_box(mag, "metal", Vector3(0.04, 0.07, 0.05), Vector3(0, -0.095, -0.012), Vector3(0.30, 0, 0))
	_box(mag, "metal", Vector3(0.038, 0.06, 0.046), Vector3(0, -0.145, -0.038), Vector3(0.52, 0, 0))
	_box(mag, "dark", Vector3(0.044, 0.012, 0.056), Vector3(0, -0.005, 0))
	var mag_node := _moving(mag, mats, Vector3(0, -0.045, 0.02))
	mag_node.name = "Mag"
	root.add_child(mag_node)
	var handle := {}
	_box(handle, "metal", Vector3(0.012, 0.016, 0.05), Vector3(0.035, 0.03, 0))
	var handle_node := _moving(handle, mats, Vector3(0.035, 0.03, 0.06))
	handle_node.name = "Handle"
	root.add_child(handle_node)
	var muzzle := Vector3(0, 0.012, -0.62)
	root.add_child(_flash(mats, muzzle))
	root.set_meta("muzzle", muzzle)
	return root


static func build_pistol(mats: Dictionary, hands := true) -> Node3D:
	var root := Node3D.new()
	root.name = "PistolUSP"
	var parts := {}
	# Frame, grip and trigger guard.
	_box(parts, "polymer", Vector3(0.03, 0.045, 0.155), Vector3(0, -0.012, 0.02))
	_box(parts, "polymer", Vector3(0.032, 0.095, 0.042), Vector3(0, -0.075, 0.075), Vector3(0.28, 0, 0))
	_box(parts, "dark", Vector3(0.01, 0.008, 0.06), Vector3(0, -0.045, 0.01))
	_box(parts, "dark", Vector3(0.01, 0.028, 0.008), Vector3(0, -0.032, -0.018))
	_box(parts, "dark", Vector3(0.012, 0.02, 0.012), Vector3(0, -0.03, 0.02))
	# Suppressor with ring bands, front sight on the slide line.
	_cyl(parts, "dark", 0.017, 0.17, Vector3(0, 0.02, -0.20), Vector3(PI * 0.5, 0, 0))
	_cyl(parts, "polymer", 0.018, 0.012, Vector3(0, 0.02, -0.13), Vector3(PI * 0.5, 0, 0))
	_cyl(parts, "polymer", 0.018, 0.012, Vector3(0, 0.02, -0.27), Vector3(PI * 0.5, 0, 0))
	_box(parts, "dark", Vector3(0.008, 0.014, 0.01), Vector3(0, 0.045, -0.10))
	# Two-hand grip: firing hand high, support hand wrapped around it.
	if hands:
		_box(parts, "glove", Vector3(0.05, 0.07, 0.055), Vector3(0.004, -0.085, 0.085), Vector3(0.28, 0, 0))
		_box(parts, "glove", Vector3(0.046, 0.032, 0.04), Vector3(0.004, -0.062, 0.045), Vector3(0.15, 0, 0))
		_box(parts, "glove", Vector3(0.016, 0.02, 0.045), Vector3(0.028, -0.05, 0.08), Vector3(0.25, 0, -0.2))
		_box(parts, "glove", Vector3(0.052, 0.06, 0.06), Vector3(-0.012, -0.10, 0.075), Vector3(0.28, 0, 0.15))
		_box(parts, "glove", Vector3(0.044, 0.028, 0.045), Vector3(-0.008, -0.078, 0.038), Vector3(0.15, 0, 0.1))
		_forearm(parts, Vector3(0.05, -0.16, 0.17), Vector3(-0.5, -0.2, 0))
		_forearm(parts, Vector3(-0.06, -0.17, 0.15), Vector3(-0.55, 0.3, 0))
	root.add_child(_merged(parts, mats))
	# Slide with rear serrations; racks on reload.
	var slide := {}
	_box(slide, "metal", Vector3(0.032, 0.042, 0.19), Vector3(0, 0.02, -0.02))
	_box(slide, "dark", Vector3(0.034, 0.03, 0.006), Vector3(0, 0.02, 0.062))
	_box(slide, "dark", Vector3(0.034, 0.03, 0.006), Vector3(0, 0.02, 0.074))
	_box(slide, "dark", Vector3(0.034, 0.03, 0.006), Vector3(0, 0.02, 0.086))
	_box(slide, "dark", Vector3(0.01, 0.012, 0.012), Vector3(0, 0.046, 0.07))
	var slide_node := _moving(slide, mats, Vector3(0, 0.02, 0.02))
	slide_node.name = "Slide"
	root.add_child(slide_node)
	var mag := {}
	_box(mag, "metal", Vector3(0.026, 0.085, 0.036), Vector3(0, -0.04, 0))
	_box(mag, "dark", Vector3(0.03, 0.012, 0.04), Vector3(0, -0.082, 0))
	var mag_node := _moving(mag, mats, Vector3(0, -0.045, 0.075))
	mag_node.name = "Mag"
	root.add_child(mag_node)
	var muzzle := Vector3(0, 0.02, -0.29)
	root.add_child(_flash(mats, muzzle))
	root.set_meta("muzzle", muzzle)
	return root


static func build_knife(mats: Dictionary, hands := true) -> Node3D:
	var root := Node3D.new()
	root.name = "KnifeKarambit"
	var parts := {}
	# Reverse-grip fist; the ring sits at the pinky end of the handle.
	if hands:
		_box(parts, "glove", Vector3(0.06, 0.07, 0.055), Vector3(0, 0, 0.01))
		_box(parts, "glove", Vector3(0.056, 0.05, 0.04), Vector3(0, -0.012, -0.032), Vector3(0.25, 0, 0))
		_box(parts, "glove", Vector3(0.016, 0.022, 0.045), Vector3(0.032, 0.012, 0.0), Vector3(0.2, 0, -0.25))
		_forearm(parts, Vector3(0.045, -0.09, 0.12), Vector3(-0.55, -0.2, 0))
	# Handle through the fist, finger ring behind.
	_box(parts, "dark", Vector3(0.018, 0.026, 0.10), Vector3(0, -0.005, 0.02))
	_torus(parts, "bright", 0.026, 0.006, Vector3(0, -0.005, 0.085), Vector3(PI * 0.5, 0, 0))
	# Hawkbill blade: a closed spine/edge profile extruded across the thickness.
	var blade := _blade_mesh()
	_add(parts, "blade", blade, Vector3.ZERO, Vector3.ZERO)
	root.add_child(_merged(parts, mats))
	root.set_meta("muzzle", Vector3.ZERO)
	return root


static func _blade_mesh() -> ArrayMesh:
	# Profile in (z, y): spine hooks forward-down, edge returns concave.
	var profile := PackedVector2Array([
		Vector2(-0.015, -0.030), Vector2(-0.055, -0.048), Vector2(-0.090, -0.075),
		Vector2(-0.110, -0.105), Vector2(-0.118, -0.135), Vector2(-0.108, -0.158),
		Vector2(-0.098, -0.140), Vector2(-0.088, -0.112), Vector2(-0.068, -0.085),
		Vector2(-0.040, -0.062), Vector2(-0.012, -0.048)])
	var thickness := 0.0035
	var count := profile.size()
	var centroid := Vector2.ZERO
	for p in profile:
		centroid += p
	centroid /= float(count)
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Side walls: outward normal perpendicular to each profile edge.
	for i in count:
		var j := (i + 1) % count
		var edge := profile[j] - profile[i]
		var n2 := Vector2(edge.y, -edge.x)
		if n2.dot((profile[i] + profile[j]) * 0.5 - centroid) < 0.0:
			n2 = -n2
		n2 = n2.normalized()
		var normal := Vector3(0, n2.y, n2.x)
		var a := Vector3(-thickness, profile[i].y, profile[i].x)
		var b := Vector3(-thickness, profile[j].y, profile[j].x)
		var c := Vector3(thickness, profile[j].y, profile[j].x)
		var d := Vector3(thickness, profile[i].y, profile[i].x)
		for vertex in [a, b, c, a, c, d]:
			tool.set_normal(normal)
			tool.add_vertex(vertex)
	# Caps face along the thickness axis.
	var cap := Geometry2D.triangulate_polygon(profile)
	for i in range(0, cap.size(), 3):
		for side in [-1.0, 1.0]:
			var normal := Vector3(side, 0, 0)
			for k in [0, 1, 2]:
				var p := profile[cap[i + k]]
				tool.set_normal(normal)
				tool.add_vertex(Vector3(side * thickness, p.y, p.x))
	var out := ArrayMesh.new()
	tool.commit(out)
	return out


static func build_all() -> Array[Node3D]:
	var mats := materials()
	var out: Array[Node3D] = [build_pistol(mats), build_rifle(mats), build_knife(mats)]
	return out