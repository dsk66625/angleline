class_name VmGeo
extends RefCounted

## Shared procedural geometry for the viewmodel. Every part carries a vertex
## colour, so all static geometry of one material merges into a SINGLE surface
## (one draw call) while still showing wood / steel / glove / sleeve tones.
## Two surface materials only: "matte" (wood, polymer, glove, fabric) and
## "metal" (steel, blade). "flash" stays a separate emissive node.
## Weapon forward is -Z, up +Y, right +X, metres.

const MATTE := "matte"
const METAL := "metal"


static func mats() -> Dictionary:
	var matte := StandardMaterial3D.new()
	matte.vertex_color_use_as_albedo = true
	matte.albedo_color = Color.WHITE
	matte.roughness = 0.82
	matte.metallic = 0.0
	var metal := StandardMaterial3D.new()
	metal.vertex_color_use_as_albedo = true
	metal.albedo_color = Color.WHITE
	metal.roughness = 0.50
	metal.metallic = 0.25
	var flash := StandardMaterial3D.new()
	flash.albedo_color = Color("#ffd9a0")
	flash.emission_enabled = true
	flash.emission = Color("#ffb45e")
	flash.emission_energy_multiplier = 3.0
	flash.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return {MATTE: matte, METAL: metal, "flash": flash}


static func _add(parts: Dictionary, key: String, mesh: Mesh, pos: Vector3, rot: Vector3, col: Color) -> void:
	if not parts.has(key):
		parts[key] = []
	parts[key].append([mesh, Transform3D(Basis.from_euler(rot), pos), col])


static func box(parts: Dictionary, key: String, col: Color, size: Vector3, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_add(parts, key, mesh, pos, rot, col)


## Box with chamfered long edges: octagon cross-section in XY extruded along Z.
static func bevel(parts: Dictionary, key: String, col: Color, size: Vector3, pos: Vector3, rot := Vector3.ZERO, chamfer := 0.004) -> void:
	var w := size.x * 0.5
	var h := size.y * 0.5
	var b := minf(chamfer, minf(w, h) * 0.6)
	var profile := PackedVector2Array([
		Vector2(-w + b, -h), Vector2(w - b, -h), Vector2(w, -h + b), Vector2(w, h - b),
		Vector2(w - b, h), Vector2(-w + b, h), Vector2(-w, h - b), Vector2(-w, -h + b)])
	extrude_z(parts, key, col, profile, size.z, pos, rot)


static func cyl(parts: Dictionary, key: String, col: Color, radius: float, height: float, pos: Vector3, rot := Vector3.ZERO, segments := 10, top_radius := -1.0) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top_radius if top_radius >= 0.0 else radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = segments
	_add(parts, key, mesh, pos, rot, col)


static func sph(parts: Dictionary, key: String, col: Color, radius: float, pos: Vector3, segments := 8, rings := 5) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = segments
	mesh.rings = rings
	_add(parts, key, mesh, pos, Vector3.ZERO, col)


static func torus(parts: Dictionary, key: String, col: Color, radius: float, tube: float, pos: Vector3, rot := Vector3.ZERO) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - tube
	mesh.outer_radius = radius + tube
	mesh.rings = 12
	mesh.ring_segments = 8
	_add(parts, key, mesh, pos, rot, col)


## Closed 2D profile in XY extruded along Z, centred, flat-shaded walls + caps.
static func extrude_z(parts: Dictionary, key: String, col: Color, profile: PackedVector2Array, length: float, pos: Vector3, rot := Vector3.ZERO) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := profile.size()
	var centroid := Vector2.ZERO
	for p in profile:
		centroid += p
	centroid /= float(count)
	var half := length * 0.5
	for i in count:
		var j := (i + 1) % count
		var edge := profile[j] - profile[i]
		var n2 := Vector2(edge.y, -edge.x)
		if n2.dot((profile[i] + profile[j]) * 0.5 - centroid) < 0.0:
			n2 = -n2
		n2 = n2.normalized()
		var normal := Vector3(n2.x, n2.y, 0)
		var a := Vector3(profile[i].x, profile[i].y, -half)
		var b := Vector3(profile[j].x, profile[j].y, -half)
		var c := Vector3(profile[j].x, profile[j].y, half)
		var d := Vector3(profile[i].x, profile[i].y, half)
		for vertex in [a, b, c, a, c, d]:
			tool.set_normal(normal)
			tool.add_vertex(vertex)
	var cap := Geometry2D.triangulate_polygon(profile)
	for i in range(0, cap.size(), 3):
		for side in [-1.0, 1.0]:
			var normal := Vector3(0, 0, side)
			for k in [0, 1, 2]:
				var p := profile[cap[i + k]]
				tool.set_normal(normal)
				tool.add_vertex(Vector3(p.x, p.y, side * half))
	var mesh := ArrayMesh.new()
	tool.commit(mesh)
	_add(parts, key, mesh, pos, rot, col)


## Closed profile given as (z, y) pairs, extruded along X. half_width per vertex
## lets the spine stay thick while the cutting edge tapers to a grind.
static func extrude_x(parts: Dictionary, key: String, col: Color, profile: PackedVector2Array, widths: PackedFloat32Array, pos: Vector3, rot := Vector3.ZERO) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := profile.size()
	var centroid := Vector2.ZERO
	for p in profile:
		centroid += p
	centroid /= float(count)
	for i in count:
		var j := (i + 1) % count
		var ti := widths[i]
		var tj := widths[j]
		var a := Vector3(-ti, profile[i].y, profile[i].x)
		var b := Vector3(-tj, profile[j].y, profile[j].x)
		var c := Vector3(tj, profile[j].y, profile[j].x)
		var d := Vector3(ti, profile[i].y, profile[i].x)
		var normal := (b - a).cross(d - a).normalized()
		var mid := (a + b + c + d) * 0.25
		var outward := Vector3(0, mid.y - centroid.y, mid.z - centroid.x)
		if normal.dot(outward) < 0.0:
			normal = -normal
		for vertex in [a, b, c, a, c, d]:
			tool.set_normal(normal)
			tool.add_vertex(vertex)
	var mesh := ArrayMesh.new()
	tool.commit(mesh)
	_add(parts, key, mesh, pos, rot, col)


## Closed profile in XY with per-vertex half thickness along Z: a blade whose
## curve lies in the profile plane and whose grind tapers spine -> edge.
static func extrude_z_taper(parts: Dictionary, key: String, col: Color, profile: PackedVector2Array, widths: PackedFloat32Array, pos: Vector3, rot := Vector3.ZERO) -> void:
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := profile.size()
	var centroid := Vector2.ZERO
	for p in profile:
		centroid += p
	centroid /= float(count)
	for i in count:
		var j := (i + 1) % count
		var ti := widths[i]
		var tj := widths[j]
		var a := Vector3(profile[i].x, profile[i].y, -ti)
		var b := Vector3(profile[j].x, profile[j].y, -tj)
		var c := Vector3(profile[j].x, profile[j].y, tj)
		var d := Vector3(profile[i].x, profile[i].y, ti)
		var normal := (b - a).cross(d - a).normalized()
		var mid := (a + b + c + d) * 0.25
		var outward := Vector3(mid.x - centroid.x, mid.y - centroid.y, 0)
		if normal.dot(outward) < 0.0:
			normal = -normal
		for vertex in [a, b, c, a, c, d]:
			tool.set_normal(normal)
			tool.add_vertex(vertex)
	var mesh := ArrayMesh.new()
	tool.commit(mesh)
	_add(parts, key, mesh, pos, rot, col)


## Merge every part of each material key into one vertex-coloured surface.
static func merge(parts: Dictionary, materials: Dictionary) -> MeshInstance3D:
	var array := ArrayMesh.new()
	for key in parts:
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var cols := PackedColorArray()
		var indices := PackedInt32Array()
		for entry in parts[key]:
			var mesh: Mesh = entry[0]
			var tf: Transform3D = entry[1]
			var col: Color = entry[2]
			for surface_index in mesh.get_surface_count():
				var data := mesh.surface_get_arrays(surface_index)
				var v: PackedVector3Array = data[Mesh.ARRAY_VERTEX]
				var n: PackedVector3Array = data[Mesh.ARRAY_NORMAL]
				var idx: PackedInt32Array = data[Mesh.ARRAY_INDEX] if data[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
				var base := verts.size()
				for i in v.size():
					verts.append(tf * v[i])
					norms.append((tf.basis * n[i]).normalized())
					cols.append(col)
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
		surface[Mesh.ARRAY_COLOR] = cols
		surface[Mesh.ARRAY_INDEX] = indices
		array.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface)
		array.surface_set_material(array.get_surface_count() - 1, materials[key])
	var instance := MeshInstance3D.new()
	instance.mesh = array
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Same merge, but re-originated at pivot so the node can animate around it.
static func pivot_node(parts: Dictionary, materials: Dictionary, pivot: Vector3, node_name: String) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = pivot
	var shifted := {}
	for key in parts:
		shifted[key] = []
		for entry in parts[key]:
			var tf: Transform3D = entry[1]
			shifted[key].append([entry[0], Transform3D(tf.basis, tf.origin - pivot), entry[2]])
	node.add_child(merge(shifted, materials))
	return node


## Star-shaped muzzle flash: two crossed tapered spikes plus a core ball.
static func flash(materials: Dictionary, pos: Vector3, scale := 1.0) -> MeshInstance3D:
	var parts := {}
	var col := Color("#ffd9a0")
	sph(parts, MATTE, col, 0.020 * scale, Vector3.ZERO, 8, 5)
	for i in 4:
		var angle := PI * 0.25 * i + PI * 0.125
		var dir := Vector3(cos(angle), sin(angle), 0)
		cyl(parts, MATTE, col, 0.010 * scale, 0.085 * scale, dir * 0.045 * scale, Vector3(0, 0, angle - PI * 0.5), 6, 0.001)
	cyl(parts, MATTE, col, 0.012 * scale, 0.07 * scale, Vector3(0, 0, -0.04 * scale), Vector3(PI * 0.5, 0, 0), 6, 0.002)
	var instance := merge(parts, materials)
	instance.material_override = materials["flash"]
	instance.name = "Flash"
	instance.position = pos
	instance.visible = false
	return instance