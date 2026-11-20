class_name VmRig
extends Node3D

## CS2-style viewmodel animation module. Pure presentation: durations are fitted
## to fighter.gd (switch 0.22 s, reload 1.55 s pistol / 2.10 s rifle, knife cycle
## 0.4 s with a 0.26 s visual slash); no gameplay state is written here.
## States deploy / idle / reload / inspect, plus additive fire kick, trigger
## finger, bolt/slide cycle, slash, movement bob, look sway, land dip and breath.
## Reloads are choreographed with the support hand: release -> mag catch -> drop
## -> fetch spare -> seat -> rack (charging handle / slide) -> regrip.

const DEPLOY := 0.22
const SWING := 0.26
const INSPECT_TIME := [3.4, 3.0, 3.2]
const BASE_POS := [Vector3(0.16, -0.075, -0.42), Vector3(0.15, -0.10, -0.52), Vector3(0.17, -0.13, -0.34)]
const BASE_ROT := [Vector3(-0.02, 0.10, 0.02), Vector3(-0.02, 0.10, 0.02), Vector3(0.0, 0.0, 0.5)]

var weapons: Array[Node3D] = []
var _weapon := -1
var _state := "idle"
var _t := 0.0
var _dur := 0.0
var _reload_total := 0.0
var _flash := 0.0
var _slash := 0.0
var _trigger := 0.0
var _cycle := 0.0
var _kick := Vector3.ZERO
var _kick_rot := Vector3.ZERO
var _sway := Vector2.ZERO
var _dip := 0.0
var _bob := 0.0
var _clock := 0.0
var _was_grounded := true
var _alt := 1.0
var _r := {}


func _ready() -> void:
	weapons = VmWeapons.build_all()
	for weapon in weapons:
		weapon.visible = false
		add_child(weapon)


func notify_attack(weapon: int) -> void:
	_cancel_inspect()
	if weapon == TrialFighter.KNIFE:
		_slash = SWING
		return
	_flash = 0.042 if weapon == TrialFighter.RIFLE else 0.030
	_trigger = 0.10
	_cycle = 0.07
	_alt = -_alt
	if weapon == TrialFighter.RIFLE:
		_kick += Vector3(0.0, 0.012, 0.055)
		_kick_rot += Vector3(-0.10, 0.02 * _alt, 0.02 * _alt)
	else:
		_kick += Vector3(0.0, 0.010, 0.040)
		_kick_rot += Vector3(-0.16, 0.0, 0.01 * _alt)


func inspect() -> void:
	if _state == "reload" or _weapon < 0:
		return
	_state = "inspect"
	_t = 0.0
	_dur = INSPECT_TIME[_weapon]


func firing() -> bool:
	return _flash > 0.0


func _cancel_inspect() -> void:
	if _state == "inspect":
		_state = "idle"
		var knife: Node3D = _r.get("knife")
		if knife:
			knife.rotation = Vector3.ZERO
		_rest_hands()


func _deploy(index: int) -> void:
	_weapon = index
	_state = "deploy"
	_t = 0.0
	_dur = DEPLOY
	_slash = 0.0
	var root := weapons[index]
	_r = {
		"mag": root.get_node_or_null("Mag"),
		"spare": root.get_node_or_null("MagSpare"),
		"slide": root.get_node_or_null("Slide"),
		"handle": root.get_node_or_null("Handle"),
		"knife": root.get_node_or_null("HandFire/Knife"),
		"fire": root.get_meta("handfire_rig") if root.has_meta("handfire_rig") else null,
		"support": root.get_meta("handsupport_rig") if root.has_meta("handsupport_rig") else null,
	}
	_reset_parts()
	for i in weapons.size():
		weapons[i].visible = i == index


func _reset_parts() -> void:
	for node_key in ["mag", "slide", "handle"]:
		var node: Node3D = _r.get(node_key)
		if node:
			node.position = node.get_meta("home", node.position)
			node.rotation = Vector3.ZERO
			node.visible = true
	var spare: Node3D = _r.get("spare")
	if spare:
		spare.position = spare.get_meta("home", spare.position)
		spare.rotation = Vector3.ZERO
		spare.visible = false
	var knife: Node3D = _r.get("knife")
	if knife:
		knife.rotation = Vector3.ZERO
	_rest_hands()


func _rest_hands() -> void:
	for key in ["fire", "support"]:
		var rig = _r.get(key)
		if rig == null:
			continue
		var home: Transform3D = rig["root"].get_meta("home")
		rig["root"].transform = home
		var pose := VmHands.pose_grip() if key == "fire" else VmHands.pose_wrap()
		if _weapon == TrialFighter.KNIFE:
			pose = VmHands.pose_ring()
		VmHands.curl_all(rig, pose)


func tick(dt: float, player: TrialFighter, look_delta: Vector2) -> void:
	_clock += dt
	if player.weapon != _weapon:
		_deploy(player.weapon)
	if player.reloading > 0.0 and _state != "reload":
		_state = "reload"
		_reload_total = player.reloading
		_t = 0.0
	if _state == "reload":
		_t = _reload_total - player.reloading
		if player.reloading <= 0.0:
			_state = "idle"
			_reset_parts()
	elif _state != "idle":
		_t += dt
		if _t >= _dur:
			_state = "idle"
			_rest_hands()
	_flash = maxf(_flash - dt, 0.0)
	_trigger = maxf(_trigger - dt, 0.0)
	_cycle = maxf(_cycle - dt, 0.0)
	_slash = maxf(_slash - dt, 0.0) if player.weapon == TrialFighter.KNIFE else 0.0
	var damp := 1.0 - exp(-14.0 * dt)
	_kick = _kick.lerp(Vector3.ZERO, damp)
	_kick_rot = _kick_rot.lerp(Vector3.ZERO, damp)
	_dip = lerpf(_dip, 0.0, 1.0 - exp(-8.0 * dt))
	if player.grounded and not _was_grounded:
		_dip = 0.05
	_was_grounded = player.grounded
	var sway_target := Vector2(clampf(-look_delta.x * 6.0, -0.03, 0.03), clampf(look_delta.y * 6.0, -0.03, 0.03))
	_sway = _sway.lerp(sway_target, 1.0 - exp(-10.0 * dt))
	var ratio := clampf(player.accuracy_speed / (TrialFighter.RUN_SPEED[player.weapon] * TrialFighter.UNIT), 0.0, 1.4)
	_bob += dt * (5.0 + 7.0 * ratio) * ratio
	if _weapon < 0:
		return
	var root := weapons[_weapon]
	var pos: Vector3 = BASE_POS[_weapon]
	var rot: Vector3 = BASE_ROT[_weapon]
	if _state == "deploy":
		var p := clampf(_t / _dur, 0.0, 1.0)
		var left := pow(1.0 - p, 2.0)
		pos += Vector3(0.0, -0.30 * left, 0.08 * left)
		rot += Vector3(-0.75 * left, 0.20 * left, 0.28 * left)
		_deploy_hands(p)
	elif _state == "reload":
		var u := clampf(_t / _reload_total, 0.0, 1.0)
		var tilt := sin(PI * clampf(u / 0.90, 0.0, 1.0))
		pos += Vector3(0.02 * tilt, -0.05 * tilt, 0.03 * tilt)
		rot += Vector3(-0.12 * tilt, 0.30 * tilt, -0.38 * tilt)
		_reload_hands(u)
	elif _state == "inspect":
		var u := clampf(_t / _dur, 0.0, 1.0)
		var pose := _inspect_pose(_weapon, u)
		pos += pose[0]
		rot += pose[1]
		_inspect_hands(u)
	if _slash > 0.0:
		var s := 1.0 - _slash / SWING
		pos += Vector3(-0.28 * sin(PI * s), 0.05 * sin(PI * s), -0.06 * sin(PI * s))
		rot += Vector3(0.10 * sin(PI * s), 0.7 - 1.5 * s, 0.55 * sin(PI * s))
	pos += _kick
	rot += _kick_rot
	pos += Vector3(sin(_bob) * 0.010 * ratio, sin(_bob * 2.0) * 0.014 * ratio - _dip, 0.0)
	rot += Vector3(_dip * 2.0, 0.0, sin(_bob) * 0.02 * ratio)
	pos += Vector3(_sway.x, _sway.y, 0.0)
	rot += Vector3(_sway.y * 1.2, -_sway.x * 1.2, 0.0)
	if not player.grounded:
		pos += Vector3(0.0, 0.02, 0.0)
		rot += Vector3(0.03, 0.0, 0.0)
	pos += Vector3(0.0, sin(_clock * 1.6) * 0.0035, 0.0)
	rot += Vector3(0.0, 0.0, sin(_clock * 1.1) * 0.006)
	root.position = pos
	root.rotation = rot
	var flash := root.get_node_or_null("Flash")
	if flash:
		flash.visible = _flash > 0.0
	_fire_parts()


## Trigger finger pull plus reciprocating charging handle / slide.
func _fire_parts() -> void:
	var pull := sin(PI * clampf(1.0 - _trigger / 0.10, 0.0, 1.0)) if _trigger > 0.0 else 0.0
	var fire = _r.get("fire")
	if fire != null and _weapon != TrialFighter.KNIFE and pull > 0.0:
		VmHands.curl(fire, "index", 0.55 + 0.10 * pull, 0.95 + 0.35 * pull)
	var recip := sin(PI * clampf(1.0 - _cycle / 0.07, 0.0, 1.0)) if _cycle > 0.0 else 0.0
	if _state == "reload":
		return
	var handle: Node3D = _r.get("handle")
	if handle and recip > 0.0:
		handle.position = (handle.get_meta("home") as Vector3) + Vector3(0, 0, 0.024 * recip)
	var slide: Node3D = _r.get("slide")
	if slide and recip > 0.0:
		slide.position = (slide.get_meta("home") as Vector3) + Vector3(0, 0, 0.036 * recip)


func _deploy_hands(p: float) -> void:
	if _weapon == TrialFighter.KNIFE:
		var knife: Node3D = _r.get("knife")
		if knife:
			knife.rotation.x = TAU * (1.0 - _ease(p))
		var fire = _r.get("fire")
		if fire != null:
			VmHands.blend(fire, VmHands.pose_open(), VmHands.pose_ring(), _ease(p))


func _reload_hands(u: float) -> void:
	var mag: Node3D = _r.get("mag")
	var spare: Node3D = _r.get("spare")
	var support = _r.get("support")
	if _weapon == TrialFighter.RIFLE:
		var drop := _track_f(u, [[0.18, 0.0], [0.34, 1.0]])
		if mag:
			mag.visible = u < 0.34
			mag.position = (mag.get_meta("home") as Vector3) + Vector3(0, -0.30 * drop, 0.02 * drop)
			mag.rotation = Vector3(0.5 * drop, 0, 0.2 * drop)
		if spare:
			spare.visible = u >= 0.46 and u < 0.72
		if support != null:
			var move := _track_v(u, [
				[0.00, Vector3.ZERO, Vector3.ZERO],
				[0.10, Vector3.ZERO, Vector3.ZERO],
				[0.22, Vector3(0.034, -0.060, 0.275), Vector3(0.2, 0, 0)],
				[0.34, Vector3(-0.020, -0.180, 0.240), Vector3(0.4, 0.2, -0.3)],
				[0.46, Vector3(-0.060, -0.300, 0.180), Vector3(0.5, 0.3, -0.4)],
				[0.60, Vector3(0.099, -0.130, 0.240), Vector3(0, 0, 2.10)],
				[0.72, Vector3(0.099, -0.030, 0.240), Vector3(0, 0, 2.10)],
				[0.84, Vector3(0.094, 0.050, 0.355), Vector3(-0.5, 0, 0.6)],
				[0.92, Vector3(0.094, 0.045, 0.355), Vector3(-0.5, 0, 0.6)],
				[1.00, Vector3.ZERO, Vector3.ZERO]])
			_place_hand(support, move[0], move[1])
			VmHands.blend(support, _reload_pose_a(u), _reload_pose_b(u), _reload_pose_t(u))
		var handle: Node3D = _r.get("handle")
		if handle:
			var rack := sin(PI * clampf((u - 0.84) / 0.08, 0.0, 1.0))
			handle.position = (handle.get_meta("home") as Vector3) + Vector3(0, 0, 0.07 * rack)
	else:
		var drop := _track_f(u, [[0.12, 0.0], [0.30, 1.0]])
		if mag:
			mag.visible = u < 0.30
			mag.position = (mag.get_meta("home") as Vector3) + Vector3(0, -0.26 * drop, 0.02 * drop)
			mag.rotation = Vector3(0.4 * drop, 0, 0.15 * drop)
		if spare:
			spare.visible = u >= 0.44 and u < 0.74
		if support != null:
			var move := _track_v(u, [
				[0.00, Vector3.ZERO, Vector3.ZERO],
				[0.12, Vector3.ZERO, Vector3.ZERO],
				[0.30, Vector3(-0.020, -0.160, 0.060), Vector3(0.4, 0.2, -0.3)],
				[0.44, Vector3(-0.050, -0.280, 0.040), Vector3(0.5, 0.3, -0.4)],
				[0.60, Vector3(0.012, -0.085, -0.106), Vector3(0, 0, 1.5708)],
				[0.74, Vector3(0.012, 0.015, -0.106), Vector3(0, 0, 1.5708)],
				[0.86, Vector3(0.036, 0.120, -0.050), Vector3(-0.7, 0, 0.4)],
				[0.94, Vector3(0.036, 0.115, -0.050), Vector3(-0.7, 0, 0.4)],
				[1.00, Vector3.ZERO, Vector3.ZERO]])
			_place_hand(support, move[0], move[1])
		var slide: Node3D = _r.get("slide")
		if slide:
			var rack := sin(PI * clampf((u - 0.86) / 0.08, 0.0, 1.0))
			slide.position = (slide.get_meta("home") as Vector3) + Vector3(0, 0, 0.055 * rack)


func _reload_pose_a(u: float) -> Dictionary:
	if u < 0.10:
		return VmHands.pose_wrap()
	if u < 0.46:
		return VmHands.pose_open()
	if u < 0.60:
		return VmHands.pose_open()
	if u < 0.84:
		return _mag_hold()
	return _mag_hold()


func _reload_pose_b(u: float) -> Dictionary:
	if u < 0.10:
		return VmHands.pose_open()
	if u < 0.46:
		var press := VmHands.pose_open()
		press["thumb"] = Vector2(0.9, 0.7)
		return press
	if u < 0.60:
		return _mag_hold()
	if u < 0.84:
		return _mag_hold()
	if u < 0.92:
		return VmHands.pose_fist()
	return VmHands.pose_wrap()


func _reload_pose_t(u: float) -> float:
	if u < 0.10:
		return u / 0.10
	if u < 0.46:
		return 1.0
	if u < 0.60:
		return (u - 0.46) / 0.14
	if u < 0.84:
		return 1.0
	if u < 0.92:
		return (u - 0.84) / 0.08
	return (u - 0.92) / 0.08


func _mag_hold() -> Dictionary:
	return {"index": Vector2(1.0, 1.1), "middle": Vector2(1.2, 1.3),
		"ring": Vector2(1.2, 1.3), "pinky": Vector2(1.1, 1.2),
		"thumb": Vector2(0.7, 0.6)}


func _place_hand(rig: Dictionary, off: Vector3, rot: Vector3) -> void:
	var home: Transform3D = rig["root"].get_meta("home")
	rig["root"].transform = Transform3D(Basis.from_euler(rot) * home.basis, home.origin + off)


func _inspect_hands(u: float) -> void:
	if _weapon != TrialFighter.KNIFE:
		return
	var knife: Node3D = _r.get("knife")
	var fire = _r.get("fire")
	var spin := 0.0
	var open := 0.0
	if u < 0.12:
		spin = -0.4 * _ease(u / 0.12)
	elif u < 0.50:
		spin = -0.4 + TAU * _ease((u - 0.12) / 0.38)
		open = 1.0
	elif u < 0.58:
		spin = -0.4
		open = 1.0 - _ease((u - 0.50) / 0.08)
	elif u < 0.90:
		spin = -0.4 + TAU * _ease((u - 0.58) / 0.32)
		open = 1.0
	else:
		spin = -0.4 * (1.0 - _ease((u - 0.90) / 0.10))
		open = 0.0
	if knife:
		knife.rotation.x = spin
	if fire != null:
		var closed := VmHands.pose_ring()
		var opened := VmHands.pose_ring()
		opened["middle"] = Vector2(0.25, 0.30)
		opened["ring"] = Vector2(0.25, 0.30)
		opened["pinky"] = Vector2(0.25, 0.30)
		VmHands.blend(fire, closed, opened, open)


func _inspect_pose(weapon: int, u: float) -> Array:
	if weapon == TrialFighter.KNIFE:
		var lift := sin(PI * clampf(u / 0.9, 0.0, 1.0)) * 0.05
		return [Vector3(0.0, lift, -0.04), Vector3(0.15, 0.25, 0.0)]
	if weapon == TrialFighter.RIFLE:
		return _keys(u, [
			[0.0, Vector3.ZERO, Vector3.ZERO],
			[0.22, Vector3(0.02, 0.06, -0.06), Vector3(-0.15, 0.55, -0.60)],
			[0.50, Vector3(0.0, 0.08, -0.04), Vector3(-0.10, 0.75, -0.75)],
			[0.72, Vector3(-0.02, 0.05, -0.05), Vector3(0.10, -0.50, 0.50)],
			[1.0, Vector3.ZERO, Vector3.ZERO]])
	return _keys(u, [
		[0.0, Vector3.ZERO, Vector3.ZERO],
		[0.25, Vector3(0.0, 0.07, -0.05), Vector3(-0.20, 0.60, -0.90)],
		[0.50, Vector3(0.0, 0.09, -0.03), Vector3(-0.50, 0.40, -0.60)],
		[0.75, Vector3(0.0, 0.05, -0.04), Vector3(0.15, -0.40, 0.50)],
		[1.0, Vector3.ZERO, Vector3.ZERO]])


func _keys(u: float, keys: Array) -> Array:
	for i in range(1, keys.size()):
		if u <= keys[i][0]:
			var span: float = keys[i][0] - keys[i - 1][0]
			var p := _ease((u - keys[i - 1][0]) / span) if span > 0.0 else 1.0
			var pos: Vector3 = (keys[i - 1][1] as Vector3).lerp(keys[i][1], p)
			var rot: Vector3 = (keys[i - 1][2] as Vector3).lerp(keys[i][2], p)
			return [pos, rot]
	return [Vector3.ZERO, Vector3.ZERO]


func _track_v(u: float, keys: Array) -> Array:
	return _keys(u, keys)


func _track_f(u: float, keys: Array) -> float:
	for i in range(1, keys.size()):
		if u <= keys[i][0]:
			var span: float = keys[i][0] - keys[i - 1][0]
			var p := _ease((u - keys[i - 1][0]) / span) if span > 0.0 else 1.0
			return lerpf(keys[i - 1][1], keys[i][1], p)
	return keys[keys.size() - 1][1]


func _ease(p: float) -> float:
	p = clampf(p, 0.0, 1.0)
	return p * p * (3.0 - 2.0 * p)