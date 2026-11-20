class_name VmWeapons
extends RefCounted

## First-person weapon models rebuilt against CS2 side-view references, with
## finger-level articulated hands (VmHands). Static geometry of each material
## merges into one vertex-coloured surface; only reload/fire-moving parts and
## live fingers stay separate nodes. Weapon forward -Z, up +Y, right +X, metres.
## Roots carry meta "muzzle"; hands are children named HandFire / HandSupport
## with meta "home" holding their rest transform.

const WOOD := Color("#7a4a2b")
const WOOD_LIGHT := Color("#8a5632")
const BAKELITE := Color("#6b3a2a")
const STEEL := Color("#4a555e")
const STEEL_DARK := Color("#333c44")
const PARKER := Color("#363e45")
const POLYMER := Color("#22282b")
const BLADE := Color("#c2cfd4")
const BLADE_EDGE := Color("#c8d4d8")


static func materials() -> Dictionary:
	return VmGeo.mats()


static func _hand(materials: Dictionary, parent: Node3D, node_name: String, side: int, pose: Dictionary, live: Dictionary, pos: Vector3, axis: Vector3, palm: Vector3, dual := false) -> Dictionary:
	var rig := VmHands.build(materials, side, pose, live, dual)
	VmHands.orient(rig, pos, axis, palm)
	rig["root"].name = node_name
	rig["root"].set_meta("home", rig["root"].transform)
	parent.add_child(rig["root"])
	parent.set_meta(node_name.to_lower() + "_rig", rig)
	return rig


static func build_rifle(mats: Dictionary, hands := true) -> Node3D:
	var root := Node3D.new()
	root.name = "RifleAK"
	var parts := {}
	# Receiver, ribbed dust cover, rear sight leaf and mag well.
	VmGeo.bevel(parts, VmGeo.METAL, STEEL, Vector3(0.040, 0.072, 0.320), Vector3(0, 0, 0), Vector3.ZERO, 0.006)
	VmGeo.bevel(parts, VmGeo.METAL, STEEL, Vector3(0.036, 0.018, 0.290), Vector3(0, 0.043, 0.005), Vector3.ZERO, 0.006)
	for i in 4:
		VmGeo.box(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.037, 0.004, 0.006), Vector3(0, 0.052, -0.10 + i * 0.07))
	VmGeo.bevel(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.030, 0.020, 0.030), Vector3(0, 0.052, -0.145), Vector3.ZERO, 0.004)
	VmGeo.box(parts, VmGeo.METAL, STEEL, Vector3(0.026, 0.006, 0.040), Vector3(0, 0.064, -0.135), Vector3(-0.10, 0, 0))
	VmGeo.bevel(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.042, 0.030, 0.060), Vector3(0, -0.045, -0.020), Vector3.ZERO, 0.004)
	# Selector lever and mag catch on the right side.
	VmGeo.box(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.004, 0.012, 0.095), Vector3(0.021, 0.012, 0.030))
	VmGeo.box(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.004, 0.020, 0.014), Vector3(0.021, -0.002, 0.075))
	VmGeo.box(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.006, 0.016, 0.012), Vector3(0.020, -0.040, 0.012))
	# Barrel, gas tube, cleaning rod, hooded front sight, slant brake.
	VmGeo.cyl(parts, VmGeo.METAL, STEEL, 0.008, 0.340, Vector3(0, 0.012, -0.330), Vector3(PI * 0.5, 0, 0), 10)
	VmGeo.cyl(parts, VmGeo.METAL, STEEL_DARK, 0.007, 0.200, Vector3(0, 0.040, -0.260), Vector3(PI * 0.5, 0, 0), 8)
	VmGeo.cyl(parts, VmGeo.METAL, STEEL_DARK, 0.0025, 0.260, Vector3(0, -0.006, -0.330), Vector3(PI * 0.5, 0, 0), 6)
	VmGeo.bevel(parts, VmGeo.METAL, STEEL, Vector3(0.020, 0.030, 0.022), Vector3(0, 0.028, -0.455), Vector3.ZERO, 0.003)
	VmGeo.torus(parts, VmGeo.METAL, STEEL, 0.011, 0.0025, Vector3(0, 0.048, -0.455), Vector3(PI * 0.5, 0, 0))
	VmGeo.cyl(parts, VmGeo.METAL, STEEL_DARK, 0.002, 0.020, Vector3(0, 0.046, -0.455), Vector3.ZERO, 6)
	VmGeo.cyl(parts, VmGeo.METAL, STEEL_DARK, 0.010, 0.045, Vector3(0, 0.012, -0.520), Vector3(PI * 0.5 + 0.35, 0, 0), 10)
	# Wood handguards with palm swell and groove ribs, gas block cap.
	VmGeo.bevel(parts, VmGeo.MATTE, WOOD, Vector3(0.046, 0.050, 0.190), Vector3(0, -0.006, -0.260), Vector3.ZERO, 0.010)
	VmGeo.bevel(parts, VmGeo.MATTE, WOOD_LIGHT, Vector3(0.050, 0.026, 0.100), Vector3(0, -0.024, -0.255), Vector3.ZERO, 0.010)
	VmGeo.box(parts, VmGeo.MATTE, WOOD_LIGHT, Vector3(0.047, 0.005, 0.010), Vector3(0, 0.012, -0.215))
	VmGeo.box(parts, VmGeo.MATTE, WOOD_LIGHT, Vector3(0.047, 0.005, 0.010), Vector3(0, 0.012, -0.300))
	VmGeo.bevel(parts, VmGeo.MATTE, WOOD, Vector3(0.034, 0.022, 0.160), Vector3(0, 0.046, -0.255), Vector3.ZERO, 0.008)
	VmGeo.bevel(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.040, 0.052, 0.018), Vector3(0, 0.012, -0.360), Vector3.ZERO, 0.004)
	# Trigger group, bakelite grip, wood stock and butt plate.
	VmGeo.box(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.008, 0.006, 0.070), Vector3(0, -0.072, 0.030))
	VmGeo.box(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.008, 0.026, 0.006), Vector3(0, -0.060, -0.004))
	VmGeo.box(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.006, 0.020, 0.008), Vector3(0, -0.056, 0.020), Vector3(0.25, 0, 0))
	VmGeo.bevel(parts, VmGeo.MATTE, BAKELITE, Vector3(0.032, 0.095, 0.046), Vector3(0, -0.085, 0.075), Vector3(0.30, 0, 0), 0.008)
	VmGeo.bevel(parts, VmGeo.MATTE, BAKELITE, Vector3(0.034, 0.012, 0.048), Vector3(0, -0.128, 0.088), Vector3(0.30, 0, 0), 0.004)
	VmGeo.bevel(parts, VmGeo.MATTE, WOOD, Vector3(0.036, 0.070, 0.200), Vector3(0, -0.012, 0.260), Vector3(-0.10, 0, 0), 0.010)
	VmGeo.bevel(parts, VmGeo.MATTE, WOOD_LIGHT, Vector3(0.037, 0.030, 0.090), Vector3(0, 0.014, 0.230), Vector3(-0.10, 0, 0), 0.010)
	VmGeo.bevel(parts, VmGeo.MATTE, STEEL_DARK, Vector3(0.038, 0.088, 0.014), Vector3(0, -0.024, 0.360), Vector3(-0.10, 0, 0), 0.004)
	VmGeo.torus(parts, VmGeo.METAL, STEEL_DARK, 0.008, 0.002, Vector3(-0.020, -0.030, 0.300), Vector3(0, 0, PI * 0.5))
	root.add_child(VmGeo.merge(parts, mats))
	# Curved ribbed magazine, pivoted at the well.
	var mag := {}
	var cant := [0.10, 0.30, 0.52, 0.72]
	var drop := [0.0, -0.062, -0.118, -0.164]
	var fwd := [0.0, -0.010, -0.034, -0.070]
	for i in 4:
		var seg := Vector3(0.036 - i * 0.001, 0.068, 0.048 - i * 0.002)
		var pos := Vector3(0, drop[i] - 0.030, fwd[i])
		VmGeo.bevel(mag, VmGeo.METAL, STEEL, seg, pos, Vector3(cant[i], 0, 0), 0.005)
		for side in [-1.0, 1.0]:
			VmGeo.box(mag, VmGeo.METAL, STEEL_DARK, Vector3(0.002, 0.060, 0.006), pos + Vector3(side * 0.018, 0, 0.012), Vector3(cant[i], 0, 0))
			VmGeo.box(mag, VmGeo.METAL, STEEL_DARK, Vector3(0.002, 0.060, 0.006), pos + Vector3(side * 0.018, 0, -0.012), Vector3(cant[i], 0, 0))
	VmGeo.bevel(mag, VmGeo.METAL, STEEL_DARK, Vector3(0.040, 0.012, 0.052), Vector3(0, -0.002, 0), Vector3(0.10, 0, 0), 0.003)
	var mag_node := VmGeo.pivot_node(mag, mats, Vector3(0, -0.050, -0.020), "Mag")
	mag_node.set_meta("home", mag_node.position)
	root.add_child(mag_node)
	var spare := VmGeo.pivot_node(mag, mats, Vector3(0, -0.100, -0.020), "MagSpare")
	spare.visible = false
	# Charging handle on the right, reciprocates on fire and racks on reload.
	var handle := {}
	VmGeo.box(handle, VmGeo.METAL, STEEL_DARK, Vector3(0.014, 0.014, 0.030), Vector3(0.026, 0.030, 0))
	VmGeo.cyl(handle, VmGeo.METAL, STEEL, 0.005, 0.030, Vector3(0.016, 0.030, 0), Vector3(0, 0, PI * 0.5), 8)
	var handle_node := VmGeo.pivot_node(handle, mats, Vector3(0.026, 0.030, 0.100), "Handle")
	handle_node.set_meta("home", handle_node.position)
	root.add_child(handle_node)
	if hands:
		_hand(mats, root, "HandFire", VmHands.RIGHT, VmHands.pose_grip(),
			{"index": 2, "thumb": 2}, Vector3(0.026, -0.070, 0.145), Vector3(0, -0.954, -0.295), Vector3(-1, 0, 0), true)
		var support := _hand(mats, root, "HandSupport", VmHands.LEFT, VmHands.pose_wrap(),
			{"index": 2, "thumb": 2, "middle": 1, "ring": 1, "pinky": 1},
			Vector3(-0.030, -0.030, -0.260), Vector3(0, 0, 1), Vector3(0.85, -0.5, 0), true)
		support["root"].add_child(spare)
		spare.position = Vector3(0.0, -0.03, -0.07)
		spare.set_meta("home", spare.position)
	var muzzle := Vector3(0, 0.012, -0.545)
	root.add_child(VmGeo.flash(mats, muzzle, 1.0))
	root.set_meta("muzzle", muzzle)
	return root


static func build_pistol(mats: Dictionary, hands := true) -> Node3D:
	var root := Node3D.new()
	root.name = "PistolUSP"
	var parts := {}
	# Frame, dust cover, grip with panels, trigger group, controls.
	VmGeo.bevel(parts, VmGeo.MATTE, POLYMER, Vector3(0.028, 0.030, 0.150), Vector3(0, -0.008, 0.010), Vector3.ZERO, 0.005)
	VmGeo.bevel(parts, VmGeo.MATTE, POLYMER, Vector3(0.030, 0.095, 0.042), Vector3(0, -0.062, 0.062), Vector3(0.26, 0, 0), 0.007)
	for side in [-1.0, 1.0]:
		VmGeo.box(parts, VmGeo.MATTE, Color("#2b3236"), Vector3(0.002, 0.070, 0.030), Vector3(side * 0.0155, -0.062, 0.062), Vector3(0.26, 0, 0))
		for i in 4:
			VmGeo.box(parts, VmGeo.MATTE, STEEL_DARK, Vector3(0.0025, 0.003, 0.032), Vector3(side * 0.016, -0.038 - i * 0.016, 0.056 + i * 0.004), Vector3(0.26, 0, 0))
	VmGeo.box(parts, VmGeo.MATTE, STEEL_DARK, Vector3(0.008, 0.006, 0.055), Vector3(0, -0.038, 0.005))
	VmGeo.box(parts, VmGeo.MATTE, STEEL_DARK, Vector3(0.008, 0.028, 0.006), Vector3(0, -0.026, -0.020))
	VmGeo.sph(parts, VmGeo.MATTE, STEEL_DARK, 0.005, Vector3(0, -0.036, -0.018), 8, 5)
	VmGeo.box(parts, VmGeo.MATTE, STEEL_DARK, Vector3(0.006, 0.020, 0.008), Vector3(0, -0.026, 0.008), Vector3(0.20, 0, 0))
	VmGeo.box(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.003, 0.008, 0.030), Vector3(-0.0155, -0.002, 0.020))
	VmGeo.box(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.004, 0.012, 0.014), Vector3(-0.0155, 0.006, 0.055))
	VmGeo.box(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.008, 0.014, 0.010), Vector3(0, 0.028, 0.082), Vector3(-0.3, 0, 0))
	# Suppressor: fluted body, base collar, perforated tip; tall front sight.
	VmGeo.cyl(parts, VmGeo.METAL, PARKER, 0.0145, 0.160, Vector3(0, 0.020, -0.185), Vector3(PI * 0.5, 0, 0), 12)
	for i in 6:
		var angle := TAU * i / 6.0
		VmGeo.cyl(parts, VmGeo.METAL, STEEL_DARK, 0.0022, 0.120, Vector3(cos(angle) * 0.0142, 0.020 + sin(angle) * 0.0142, -0.180), Vector3(PI * 0.5, 0, 0), 6)
	VmGeo.cyl(parts, VmGeo.METAL, STEEL_DARK, 0.016, 0.014, Vector3(0, 0.020, -0.112), Vector3(PI * 0.5, 0, 0), 12)
	for i in 8:
		var angle := TAU * i / 8.0
		VmGeo.cyl(parts, VmGeo.MATTE, Color("#15191c"), 0.0022, 0.004, Vector3(cos(angle) * 0.0125, 0.020 + sin(angle) * 0.0125, -0.252), Vector3(PI * 0.5, 0, 0), 6)
	VmGeo.box(parts, VmGeo.METAL, STEEL_DARK, Vector3(0.004, 0.014, 0.006), Vector3(0, 0.042, -0.095))
	root.add_child(VmGeo.merge(parts, mats))
	# Slide with rear serrations and ejection port; cycles on fire / reload.
	var slide := {}
	VmGeo.bevel(slide, VmGeo.METAL, STEEL, Vector3(0.026, 0.030, 0.185), Vector3(0, 0.020, -0.015), Vector3.ZERO, 0.005)
	for i in 6:
		VmGeo.box(slide, VmGeo.METAL, STEEL_DARK, Vector3(0.027, 0.024, 0.003), Vector3(0, 0.020, 0.052 + i * 0.006))
	VmGeo.box(slide, VmGeo.METAL, STEEL_DARK, Vector3(0.002, 0.014, 0.035), Vector3(0.0135, 0.024, -0.010))
	VmGeo.box(slide, VmGeo.METAL, STEEL_DARK, Vector3(0.016, 0.008, 0.008), Vector3(0, 0.038, 0.065))
	var slide_node := VmGeo.pivot_node(slide, mats, Vector3(0, 0.020, 0.020), "Slide")
	slide_node.set_meta("home", slide_node.position)
	root.add_child(slide_node)
	var mag := {}
	VmGeo.bevel(mag, VmGeo.METAL, STEEL, Vector3(0.024, 0.085, 0.034), Vector3(0, -0.040, 0), Vector3.ZERO, 0.004)
	VmGeo.bevel(mag, VmGeo.MATTE, POLYMER, Vector3(0.028, 0.010, 0.038), Vector3(0, -0.082, 0), Vector3.ZERO, 0.003)
	var mag_node := VmGeo.pivot_node(mag, mats, Vector3(0, -0.045, 0.062), "Mag")
	mag_node.set_meta("home", mag_node.position)
	root.add_child(mag_node)
	var spare := VmGeo.pivot_node(mag, mats, Vector3(0, -0.040, 0.0), "MagSpare")
	spare.visible = false
	if hands:
		_hand(mats, root, "HandFire", VmHands.RIGHT, VmHands.pose_grip(),
			{"index": 2, "thumb": 2}, Vector3(0.026, -0.060, 0.125), Vector3(0, -0.966, -0.259), Vector3(-1, 0, 0), true)
		var support := _hand(mats, root, "HandSupport", VmHands.LEFT, VmHands.pose_wrap(), {},
			Vector3(-0.030, -0.070, 0.100), Vector3(0, 0.966, 0.259), Vector3(1, 0, 0))
		support["root"].add_child(spare)
		spare.position = Vector3(0.0, -0.03, -0.07)
		spare.set_meta("home", spare.position)
	var muzzle := Vector3(0, 0.020, -0.268)
	root.add_child(VmGeo.flash(mats, muzzle, 0.55))
	root.set_meta("muzzle", muzzle)
	return root


static func build_knife(mats: Dictionary, hands := true) -> Node3D:
	var root := Node3D.new()
	root.name = "KnifeKarambit"
	var holder: Node3D
	if hands:
		var rig := VmHands.build(mats, VmHands.RIGHT, VmHands.pose_ring(),
			{"middle": 1, "ring": 1, "pinky": 1}, true)
		VmHands.orient(rig, Vector3.ZERO, Vector3(-0.203, -0.913, -0.355), Vector3(-0.916, 0.227, -0.061))
		rig["root"].name = "HandFire"
		rig["root"].set_meta("home", rig["root"].transform)
		root.add_child(rig["root"])
		root.set_meta("handfire_rig", rig)
		holder = rig["root"]
	else:
		holder = Node3D.new()
		holder.name = "HandFire"
		var a := Vector3(-0.203, -0.913, -0.355).normalized()
		var p := Vector3(-0.916, 0.227, -0.061)
		p = (p - a * p.dot(a)).normalized()
		holder.transform = Transform3D(Basis(a, -p, -a.cross(p)), Vector3.ZERO)
		holder.set_meta("home", holder.transform)
		root.add_child(holder)
	# Handle through the fist, pommel ring at the index loop, hawkbill blade
	# with a real grind (spine thick, edge tapered) leaving the pinky side.
	var knife := {}
	VmGeo.bevel(knife, VmGeo.MATTE, POLYMER, Vector3(0.030, 0.024, 0.085), Vector3(0.010, -0.035, -0.105), Vector3(0, PI * 0.5, 0), 0.006)
	for i in 3:
		VmGeo.cyl(knife, VmGeo.MATTE, STEEL_DARK, 0.006, 0.026, Vector3(-0.006 + i * 0.018, -0.024, -0.105), Vector3(0, 0, PI * 0.5), 8)
	VmGeo.torus(knife, VmGeo.METAL, BLADE, 0.019, 0.004, Vector3(-0.040, -0.035, -0.105), Vector3(0, 0, PI * 0.5))
	var profile := PackedVector2Array([
		Vector2(0.040, -0.022), Vector2(0.072, -0.030), Vector2(0.096, -0.052),
		Vector2(0.108, -0.084), Vector2(0.104, -0.118), Vector2(0.088, -0.146),
		Vector2(0.080, -0.124), Vector2(0.076, -0.096), Vector2(0.068, -0.068),
		Vector2(0.054, -0.046), Vector2(0.038, -0.034)])
	var widths := PackedFloat32Array([0.0035, 0.0035, 0.0032, 0.0026, 0.0016, 0.0005, 0.0008, 0.0014, 0.0022, 0.0030, 0.0035])
	VmGeo.extrude_z_taper(knife, VmGeo.METAL, BLADE, profile, widths, Vector3(0, 0, -0.105))
	var pivot := Vector3(-0.040, -0.035, -0.105)
	var knife_node := VmGeo.pivot_node(knife, mats, pivot, "Knife")
	holder.add_child(knife_node)
	root.set_meta("muzzle", Vector3.ZERO)
	return root


static func build_all() -> Array[Node3D]:
	var mats := materials()
	var out: Array[Node3D] = [build_pistol(mats), build_rifle(mats), build_knife(mats)]
	return out