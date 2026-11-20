class_name VmHands
extends RefCounted

## Articulated gloved hands, finger level, placed by a cylinder-grip solver so
## geometry never intersects the held object. Canonical hand space: extended
## fingers -Z, palm faces -Y, thumb -X for RIGHT (+X LEFT). Curl is a positive
## radian applied as rotation.x = -curl (fingers fold toward the palm).
##
## wrap_pose() treats the grip as a cylinder (center, axis, radius). Finger
## phalanges become chords of a circle at radius + finger thickness, joint
## angles derived from chord turns, and the palm sits outside the cylinder.
## That makes penetration geometrically impossible in the solved pose.
##
## live maps finger -> joint count (2 = MCP+PIP nodes, 1 = MCP only); other
## fingers bake into the palm. dual=true also bakes a rest copy ("RestFingers")
## so idle costs one surface; set_live swaps to the joints during actions.

const RIGHT := 0
const LEFT := 1

const GLOVE := Color("#333b41")
const GLOVE_PAD := Color("#3d464c")
const GLOVE_TIP := Color("#485157")
const CUFF := Color("#242a2e")
const SLEEVE := Color("#41505c")

const FINGERS := ["index", "middle", "ring", "pinky"]
const ROOT_X := {"index": -0.026, "middle": -0.009, "ring": 0.009, "pinky": 0.026}
const LEN := {
	"index": Vector3(0.030, 0.019, 0.015),
	"middle": Vector3(0.034, 0.022, 0.016),
	"ring": Vector3(0.031, 0.020, 0.015),
	"pinky": Vector3(0.024, 0.015, 0.013)}
const RADIUS := {"index": 0.0082, "middle": 0.0085, "ring": 0.0079, "pinky": 0.0069}
const KNUCKLE_Z := -0.066


static func pose_open() -> Dictionary:
	return {"index": Vector2(0.10, 0.14), "middle": Vector2(0.10, 0.14),
		"ring": Vector2(0.10, 0.14), "pinky": Vector2(0.10, 0.14),
		"thumb": Vector2(0.22, 0.18)}


## Solve a wrap around a cylinder. Returns {basis, origin, pose, dip} where dip
## is the baked DIP bend per finger. phi0 = how far the knuckle line sits from
## the palm direction toward the wrap direction.
static func wrap_pose(center: Vector3, axis: Vector3, palm_dir: Vector3, wrap_dir: Vector3, radius: float, phi0 := 0.35) -> Dictionary:
	var a := axis.normalized()
	var p := (palm_dir - a * palm_dir.dot(a)).normalized()
	var w := wrap_dir - a * wrap_dir.dot(a) - p * wrap_dir.dot(p)
	w = w.normalized()
	var reach := radius + 0.009
	var root_dir := -p * cos(phi0) + w * sin(phi0)
	var t0 := p * sin(phi0) + w * cos(phi0)
	var pose := {}
	var dip := {}
	for finger in FINGERS:
		var lengths: Vector3 = LEN[finger]
		var d1 := 2.0 * asin(clampf(lengths.x / (2.0 * reach), 0.0, 0.9))
		var d2 := 2.0 * asin(clampf(lengths.y / (2.0 * reach), 0.0, 0.9))
		var d3 := 2.0 * asin(clampf(lengths.z / (2.0 * reach), 0.0, 0.9))
		pose[finger] = Vector2(d1 * 0.5, (d1 + d2) * 0.5)
		dip[finger] = (d2 + d3) * 0.5
	pose["thumb"] = Vector2(0.30, 0.26)
	var origin := center + root_dir * reach + p * 0.002 + t0 * KNUCKLE_Z
	return {"basis": Basis(a, -p, -t0), "origin": origin, "pose": pose, "dip": dip}


## Local-space wrap used for fist / magazine hold (curl axis = canonical X).
static func fist_pose(center := Vector3(0, -0.030, -0.070), radius := 0.017) -> Dictionary:
	return wrap_pose(center, Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1), radius, 0.5)


static func build(materials: Dictionary, side: int, pose: Dictionary, live: Dictionary, dual := false, dip := {}) -> Dictionary:
	var mirror := -1.0 if side == RIGHT else 1.0
	var root := Node3D.new()
	root.name = "HandR" if side == RIGHT else "HandL"
	var palm := {}
	# Curved-look palm: short block plus thenar / hypothenar pads, kept outside
	# the grip cylinder by the solver.
	VmGeo.bevel(palm, VmGeo.MATTE, GLOVE, Vector3(0.070, 0.026, 0.058), Vector3(0, 0.007, -0.030), Vector3.ZERO, 0.009)
	VmGeo.bevel(palm, VmGeo.MATTE, GLOVE_PAD, Vector3(0.068, 0.020, 0.014), Vector3(0, 0.010, -0.062), Vector3.ZERO, 0.006)
	VmGeo.sph(palm, VmGeo.MATTE, GLOVE, 0.011, Vector3(mirror * -0.026, 0.004, -0.024), 8, 4)
	VmGeo.sph(palm, VmGeo.MATTE, GLOVE, 0.010, Vector3(mirror * 0.026, 0.005, -0.024), 8, 4)
	VmGeo.cyl(palm, VmGeo.MATTE, GLOVE, 0.023, 0.026, Vector3(0, 0, 0.012), Vector3(PI * 0.5, 0, 0), 10)
	VmGeo.bevel(palm, VmGeo.MATTE, CUFF, Vector3(0.054, 0.048, 0.022), Vector3(0, 0, 0.032), Vector3.ZERO, 0.008)
	VmGeo.box(palm, VmGeo.MATTE, CUFF, Vector3(0.056, 0.008, 0.006), Vector3(0, 0.023, 0.032))
	VmGeo.cyl(palm, VmGeo.MATTE, SLEEVE, 0.021, 0.100, Vector3(0, 0, 0.092), Vector3(PI * 0.5, 0, 0), 10, 0.027)
	var nodes := {}
	var rest_parts := {}
	for finger in FINGERS:
		var curl: Vector2 = pose.get(finger, Vector2(0.10, 0.14))
		var bend: float = dip.get(finger, 0.35)
		var root_pos := Vector3(mirror * ROOT_X[finger], 0.002, KNUCKLE_Z)
		var joints: int = live.get(finger, 0)
		if joints == 0:
			_bake_finger(palm, finger, root_pos, curl, bend)
		else:
			var mcp := Node3D.new()
			mcp.name = finger.capitalize() + "MCP"
			mcp.position = root_pos
			mcp.rotation.x = -curl.x
			root.add_child(mcp)
			var prox := {}
			_prox(prox, finger)
			mcp.add_child(VmGeo.merge(prox, materials))
			var pip_node: Node3D = null
			if joints == 2:
				pip_node = Node3D.new()
				pip_node.name = finger.capitalize() + "PIP"
				pip_node.position = Vector3(0, 0, -LEN[finger].x)
				pip_node.rotation.x = -curl.y
				mcp.add_child(pip_node)
				var dist := {}
				_dist(dist, finger, 0.0, bend)
				pip_node.add_child(VmGeo.merge(dist, materials))
			else:
				var rest := {}
				_dist(rest, finger, curl.y, bend)
				mcp.add_child(VmGeo.merge(rest, materials))
			nodes[finger] = [mcp, pip_node]
			if dual:
				_bake_finger(rest_parts, finger, root_pos, curl, bend)
	var thumb_curl: Vector2 = pose.get("thumb", Vector2(0.22, 0.18))
	var thumb_yaw := mirror * -0.85
	var thumb_pos := Vector3(mirror * -0.038, -0.004, -0.024)
	if live.get("thumb", 0) == 0:
		var baked := {}
		_prox(baked, "thumb")
		_dist(baked, "thumb", thumb_curl.y, 0.30)
		_bake_parts(palm, baked, Transform3D(Basis.from_euler(Vector3(-thumb_curl.x, thumb_yaw, 0)), thumb_pos))
	else:
		var mcp := Node3D.new()
		mcp.name = "ThumbMCP"
		mcp.position = thumb_pos
		mcp.rotation = Vector3(-thumb_curl.x, thumb_yaw, 0)
		mcp.set_meta("yaw", thumb_yaw)
		root.add_child(mcp)
		var prox := {}
		_prox(prox, "thumb")
		mcp.add_child(VmGeo.merge(prox, materials))
		var pip_node: Node3D = null
		if live["thumb"] == 2:
			pip_node = Node3D.new()
			pip_node.name = "ThumbPIP"
			pip_node.position = Vector3(0, 0, -0.028)
			pip_node.rotation.x = -thumb_curl.y
			mcp.add_child(pip_node)
			var dist := {}
			_dist(dist, "thumb", 0.0, 0.30)
			pip_node.add_child(VmGeo.merge(dist, materials))
		else:
			var rest := {}
			_dist(rest, "thumb", thumb_curl.y, 0.30)
			mcp.add_child(VmGeo.merge(rest, materials))
		nodes["thumb"] = [mcp, pip_node]
		if dual:
			var baked := {}
			_prox(baked, "thumb")
			_dist(baked, "thumb", thumb_curl.y, 0.30)
			_bake_parts(rest_parts, baked, Transform3D(Basis.from_euler(Vector3(-thumb_curl.x, thumb_yaw, 0)), thumb_pos))
	var rest_node: MeshInstance3D = null
	if dual and not rest_parts.is_empty():
		rest_node = VmGeo.merge(rest_parts, materials)
		rest_node.name = "RestFingers"
		root.add_child(rest_node)
	root.add_child(VmGeo.merge(palm, materials))
	return {"root": root, "nodes": nodes, "side": side, "rest": rest_node}


## Continuous tapered phalanges (no bead-like joint balls).
static func _prox(parts: Dictionary, finger: String) -> void:
	var length: float = LEN[finger].x if finger != "thumb" else 0.028
	var radius: float = RADIUS.get(finger, 0.0092)
	VmGeo.cyl(parts, VmGeo.MATTE, GLOVE, radius, length, Vector3(0, 0, -length * 0.5), Vector3(PI * 0.5, 0, 0), 8, radius * 0.93)
	VmGeo.sph(parts, VmGeo.MATTE, GLOVE_PAD, radius * 0.95, Vector3(0, 0, -length * 0.06), 8, 4)


static func _dist(parts: Dictionary, finger: String, baked_pip := 0.0, baked_dip := 0.35) -> void:
	var lengths: Vector3 = LEN[finger] if finger != "thumb" else Vector3(0.028, 0.019, 0.015)
	var radius: float = RADIUS.get(finger, 0.0092)
	var local := {}
	VmGeo.cyl(local, VmGeo.MATTE, GLOVE, radius * 0.93, lengths.y, Vector3(0, 0, -lengths.y * 0.5), Vector3(PI * 0.5, 0, 0), 8, radius * 0.85)
	var tip := {}
	VmGeo.cyl(tip, VmGeo.MATTE, GLOVE_TIP, radius * 0.85, lengths.z, Vector3(0, 0, -lengths.z * 0.5), Vector3(PI * 0.5, 0, 0), 8, radius * 0.58)
	VmGeo.sph(tip, VmGeo.MATTE, GLOVE_TIP, radius * 0.60, Vector3(0, 0, -lengths.z), 8, 4)
	_bake_parts(local, tip, Transform3D(Basis.from_euler(Vector3(-baked_dip, 0, 0)), Vector3(0, 0, -lengths.y)))
	_bake_parts(parts, local, Transform3D(Basis.from_euler(Vector3(-baked_pip, 0, 0)), Vector3.ZERO))


static func _bake_finger(parts: Dictionary, finger: String, root_pos: Vector3, curl: Vector2, bend: float) -> void:
	var prox := {}
	_prox(prox, finger)
	var mcp_tf := Transform3D(Basis.from_euler(Vector3(-curl.x, 0, 0)), root_pos)
	_bake_parts(parts, prox, mcp_tf)
	var dist := {}
	_dist(dist, finger, 0.0, bend)
	var pip_tf := mcp_tf * Transform3D(Basis.from_euler(Vector3(-curl.y, 0, 0)), Vector3(0, 0, -LEN[finger].x))
	_bake_parts(parts, dist, pip_tf)


static func _bake_parts(target: Dictionary, source: Dictionary, tf: Transform3D) -> void:
	for key in source:
		if not target.has(key):
			target[key] = []
		for entry in source[key]:
			target[key].append([entry[0], tf * entry[1], entry[2]])


## Place a built hand by a solved wrap (see wrap_pose).
static func place(rig: Dictionary, solved: Dictionary) -> void:
	rig["root"].transform = Transform3D(solved["basis"], solved["origin"])
	rig["root"].set_meta("home", rig["root"].transform)
	curl_all(rig, solved["pose"])


static func curl(rig: Dictionary, finger: String, mcp: float, pip: float) -> void:
	var pair: Array = rig["nodes"].get(finger, [])
	if pair.is_empty():
		return
	var mcp_node: Node3D = pair[0]
	if finger == "thumb":
		mcp_node.rotation = Vector3(-mcp, mcp_node.get_meta("yaw", 0.0), 0)
	else:
		mcp_node.rotation.x = -mcp
	if pair[1] != null:
		(pair[1] as Node3D).rotation.x = -pip


static func curl_all(rig: Dictionary, pose: Dictionary) -> void:
	for finger in pose:
		var c: Vector2 = pose[finger]
		curl(rig, finger, c.x, c.y)


static func blend(rig: Dictionary, from: Dictionary, to: Dictionary, t: float) -> void:
	for finger in rig["nodes"]:
		var a: Vector2 = from.get(finger, Vector2(0.10, 0.14))
		var b: Vector2 = to.get(finger, Vector2(0.10, 0.14))
		curl(rig, finger, lerpf(a.x, b.x, t), lerpf(a.y, b.y, t))


static func set_live(rig: Dictionary, live: bool) -> void:
	var rest: MeshInstance3D = rig.get("rest")
	if rest == null:
		return
	rest.visible = not live
	for finger in rig["nodes"]:
		(rig["nodes"][finger][0] as Node3D).visible = live