class_name VmHands
extends RefCounted

## Articulated gloved hands, finger level. Canonical hand space: extended
## fingers point -Z, palm faces -Y, thumb sits at -X for a RIGHT hand (+X LEFT).
## Curl is a positive radian value applied as rotation.x = -curl, so fingers
## fold toward the palm. Each live finger exposes an MCP node and (optionally)
## a PIP node; fingers not listed in `live` are baked into the palm mesh in
## their posed curl and cost zero extra draw calls.
## The whole hand (palm + wrist + cuff + sleeve) is one vertex-coloured surface.

const RIGHT := 0
const LEFT := 1

const GLOVE := Color("#2e353a")
const GLOVE_PAD := Color("#3a4247")
const GLOVE_TIP := Color("#434b50")
const SEAM := Color("#20262a")
const CUFF := Color("#22282c")
const SLEEVE := Color("#3c4a56")

const FINGERS := ["index", "middle", "ring", "pinky"]
# x offset of each finger root (RIGHT hand; mirrored for LEFT), phalanx lengths.
const ROOT_X := {"index": -0.026, "middle": -0.009, "ring": 0.009, "pinky": 0.026}
const LEN := {
	"index": Vector3(0.032, 0.020, 0.016),
	"middle": Vector3(0.036, 0.023, 0.017),
	"ring": Vector3(0.033, 0.021, 0.016),
	"pinky": Vector3(0.026, 0.016, 0.014)}
const RADIUS := {"index": 0.0085, "middle": 0.0088, "ring": 0.0082, "pinky": 0.0072}


static func pose_open() -> Dictionary:
	return {"index": Vector2(0.12, 0.18), "middle": Vector2(0.12, 0.18),
		"ring": Vector2(0.12, 0.18), "pinky": Vector2(0.12, 0.18),
		"thumb": Vector2(0.25, 0.20)}


static func pose_fist() -> Dictionary:
	return {"index": Vector2(1.42, 1.50), "middle": Vector2(1.48, 1.55),
		"ring": Vector2(1.48, 1.55), "pinky": Vector2(1.42, 1.50),
		"thumb": Vector2(0.95, 0.85)}


static func pose_grip() -> Dictionary:
	# Wrapped around a vertical grip, index hooked on the trigger.
	return {"index": Vector2(0.55, 0.95), "middle": Vector2(1.15, 1.25),
		"ring": Vector2(1.20, 1.30), "pinky": Vector2(1.15, 1.25),
		"thumb": Vector2(0.35, 0.30)}


static func pose_wrap() -> Dictionary:
	# Support hand cupping a horizontal handguard / another hand.
	return {"index": Vector2(1.20, 1.30), "middle": Vector2(1.30, 1.40),
		"ring": Vector2(1.30, 1.40), "pinky": Vector2(1.25, 1.35),
		"thumb": Vector2(0.55, 0.45)}


static func pose_ring() -> Dictionary:
	# Karambit reverse grip: index loops through the pommel ring, rest fist.
	var out := pose_fist()
	out["index"] = Vector2(0.45, 0.55)
	out["thumb"] = Vector2(0.80, 0.70)
	return out


## live maps finger name -> joint count (2 = MCP+PIP nodes, 1 = MCP only).
static func build(materials: Dictionary, side: int, pose: Dictionary, live: Dictionary) -> Dictionary:
	var mirror := -1.0 if side == RIGHT else 1.0
	var root := Node3D.new()
	root.name = "HandR" if side == RIGHT else "HandL"
	var palm := {}
	VmGeo.bevel(palm, VmGeo.MATTE, GLOVE, Vector3(0.072, 0.026, 0.088), Vector3(0, 0, -0.040), Vector3.ZERO, 0.008)
	VmGeo.bevel(palm, VmGeo.MATTE, GLOVE_PAD, Vector3(0.070, 0.020, 0.016), Vector3(0, 0.003, -0.086), Vector3.ZERO, 0.006)
	VmGeo.sph(palm, VmGeo.MATTE, GLOVE, 0.015, Vector3(mirror * -0.030, -0.006, -0.030))
	VmGeo.cyl(palm, VmGeo.MATTE, GLOVE, 0.024, 0.030, Vector3(0, 0, 0.014), Vector3(PI * 0.5, 0, 0), 10)
	VmGeo.bevel(palm, VmGeo.MATTE, CUFF, Vector3(0.056, 0.050, 0.024), Vector3(0, 0, 0.038), Vector3.ZERO, 0.008)
	VmGeo.box(palm, VmGeo.MATTE, SEAM, Vector3(0.058, 0.010, 0.006), Vector3(0, 0.024, 0.038))
	VmGeo.cyl(palm, VmGeo.MATTE, SLEEVE, 0.028, 0.150, Vector3(0, 0, 0.125), Vector3(PI * 0.5, 0, 0), 10, 0.036)
	var nodes := {}
	for finger in FINGERS:
		var curl: Vector2 = pose.get(finger, Vector2(0.12, 0.18))
		var root_pos := Vector3(mirror * ROOT_X[finger], 0.002, -0.090)
		var joints: int = live.get(finger, 0)
		if joints == 0:
			_bake_finger(palm, finger, root_pos, curl)
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
				_dist(dist, finger)
				pip_node.add_child(VmGeo.merge(dist, materials))
			else:
				var rest := {}
				_dist(rest, finger, curl.y)
				mcp.add_child(VmGeo.merge(rest, materials))
			nodes[finger] = [mcp, pip_node]
	# Thumb: yawed outward at the base, two joints when live.
	var thumb_curl: Vector2 = pose.get("thumb", Vector2(0.25, 0.20))
	var thumb_yaw := mirror * -0.85
	var thumb_pos := Vector3(mirror * -0.040, -0.004, -0.026)
	if live.get("thumb", 0) == 0:
		var baked := {}
		_prox(baked, "thumb")
		_dist(baked, "thumb", thumb_curl.y)
		var tf := Transform3D(Basis.from_euler(Vector3(-thumb_curl.x, thumb_yaw, 0)), thumb_pos)
		_bake_parts(palm, baked, tf)
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
			pip_node.position = Vector3(0, 0, -0.030)
			pip_node.rotation.x = -thumb_curl.y
			mcp.add_child(pip_node)
			var dist := {}
			_dist(dist, "thumb")
			pip_node.add_child(VmGeo.merge(dist, materials))
		else:
			var rest := {}
			_dist(rest, "thumb", thumb_curl.y)
			mcp.add_child(VmGeo.merge(rest, materials))
		nodes["thumb"] = [mcp, pip_node]
	root.add_child(VmGeo.merge(palm, materials))
	return {"root": root, "nodes": nodes, "side": side}


static func _prox(parts: Dictionary, finger: String) -> void:
	var length: float = LEN[finger].x if finger != "thumb" else 0.030
	var radius: float = RADIUS.get(finger, 0.0095)
	VmGeo.sph(parts, VmGeo.MATTE, GLOVE_PAD, radius * 1.08, Vector3.ZERO, 8, 5)
	VmGeo.cyl(parts, VmGeo.MATTE, GLOVE, radius, length, Vector3(0, 0, -length * 0.5), Vector3(PI * 0.5, 0, 0), 8, radius * 0.94)
	VmGeo.torus(parts, VmGeo.MATTE, SEAM, radius * 0.96, 0.0012, Vector3(0, 0, -length * 0.55), Vector3(PI * 0.5, 0, 0))


static func _dist(parts: Dictionary, finger: String, baked_pip := 0.0) -> void:
	var lengths: Vector3 = LEN[finger] if finger != "thumb" else Vector3(0.030, 0.020, 0.016)
	var radius: float = RADIUS.get(finger, 0.0095)
	var tf := Transform3D(Basis.from_euler(Vector3(-baked_pip, 0, 0)), Vector3.ZERO)
	var local := {}
	VmGeo.sph(local, VmGeo.MATTE, GLOVE_PAD, radius * 0.98, Vector3.ZERO, 8, 5)
	VmGeo.cyl(local, VmGeo.MATTE, GLOVE, radius * 0.94, lengths.y, Vector3(0, 0, -lengths.y * 0.5), Vector3(PI * 0.5, 0, 0), 8, radius * 0.86)
	VmGeo.torus(local, VmGeo.MATTE, SEAM, radius * 0.88, 0.0011, Vector3(0, 0, -lengths.y), Vector3(PI * 0.5, 0, 0))
	VmGeo.cyl(local, VmGeo.MATTE, GLOVE_TIP, radius * 0.86, lengths.z, Vector3(0, 0, -lengths.y - lengths.z * 0.5), Vector3(PI * 0.5, 0, 0), 8, radius * 0.62)
	VmGeo.sph(local, VmGeo.MATTE, GLOVE_TIP, radius * 0.66, Vector3(0, 0, -lengths.y - lengths.z), 8, 5)
	_bake_parts(parts, local, tf)


static func _bake_finger(parts: Dictionary, finger: String, root_pos: Vector3, curl: Vector2) -> void:
	var prox := {}
	_prox(prox, finger)
	var mcp_tf := Transform3D(Basis.from_euler(Vector3(-curl.x, 0, 0)), root_pos)
	_bake_parts(parts, prox, mcp_tf)
	var dist := {}
	_dist(dist, finger)
	var pip_tf := mcp_tf * Transform3D(Basis.from_euler(Vector3(-curl.y, 0, 0)), Vector3(0, 0, -LEN[finger].x))
	_bake_parts(parts, dist, pip_tf)


static func _bake_parts(target: Dictionary, source: Dictionary, tf: Transform3D) -> void:
	for key in source:
		if not target.has(key):
			target[key] = []
		for entry in source[key]:
			target[key].append([entry[0], tf * entry[1], entry[2]])


## Aim a built hand around a gripped cylinder: axis = the cylinder / curl axis
## (canonical +X, running from the knuckle end toward the wrist end of the
## grip), palm = direction the palm faces. Finger direction and wrist direction
## follow from those two, so fingers always wrap the grip the anatomical way.
static func orient(rig: Dictionary, pos: Vector3, axis: Vector3, palm: Vector3) -> void:
	var a := axis.normalized()
	var p := (palm - a * palm.dot(a)).normalized()
	var finger := a.cross(p)
	rig["root"].transform = Transform3D(Basis(a, -p, -finger), pos)


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


## Blend two poses; t in [0,1]. Only touches live fingers.
static func blend(rig: Dictionary, from: Dictionary, to: Dictionary, t: float) -> void:
	for finger in rig["nodes"]:
		var a: Vector2 = from.get(finger, Vector2(0.12, 0.18))
		var b: Vector2 = to.get(finger, Vector2(0.12, 0.18))
		curl(rig, finger, lerpf(a.x, b.x, t), lerpf(a.y, b.y, t))