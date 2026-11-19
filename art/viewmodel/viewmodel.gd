class_name VmRig
extends Node3D

## CS2-style viewmodel animation module. Pure presentation: every duration is
## fitted to the logic constants in fighter.gd (switch cooldown 0.22 s, reload
## 1.55/2.10 s, knife cycle 0.4 s with a 0.26 s visual slash) and no gameplay
## state is written here. States: deploy / idle / reload / inspect, with
## additive fire kick, slash, movement bob, look sway, land dip and idle breath.

const DEPLOY := 0.22
const SWING := 0.26
const INSPECT_TIME := [2.6, 3.6, 3.2]
const BASE_POS := [Vector3(0.24, -0.18, -0.38), Vector3(0.24, -0.19, -0.46), Vector3(0.26, -0.16, -0.40)]
const BASE_ROT := [Vector3(0.0, 0.08, 0.0), Vector3(0.0, 0.10, 0.03), Vector3(0.10, 0.45, 0.15)]

var weapons: Array[Node3D] = []
var _weapon := -1
var _state := "idle"
var _t := 0.0
var _dur := 0.0
var _reload_total := 0.0
var _flash := 0.0
var _slash := 0.0
var _kick := Vector3.ZERO
var _kick_rot := Vector3.ZERO
var _sway := Vector2.ZERO
var _dip := 0.0
var _bob := 0.0
var _clock := 0.0
var _was_grounded := true
var _alt := 1.0


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
	_flash = 0.042
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


func _deploy(index: int) -> void:
	_weapon = index
	_state = "deploy"
	_t = 0.0
	_dur = DEPLOY
	_slash = 0.0
	_reset_parts()
	for i in weapons.size():
		weapons[i].visible = i == index


func _reset_parts() -> void:
	for weapon in weapons:
		var mag: Node3D = weapon.get_node_or_null("Mag")
		if mag:
			mag.position = _mag_home(weapons.find(weapon))
			mag.rotation = Vector3.ZERO
		var slide: Node3D = weapon.get_node_or_null("Slide")
		if slide:
			slide.position = Vector3(0, 0.02, 0.02)
		var handle: Node3D = weapon.get_node_or_null("Handle")
		if handle:
			handle.position = Vector3(0.035, 0.03, 0.06)


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
	elif _state != "idle":
		_t += dt
		if _t >= _dur:
			_state = "idle"
	_flash = maxf(_flash - dt, 0.0)
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
	# Deploy: quick raise from below with a settling tilt, inside the 0.22 s
	# switch cooldown so the first legal shot already lands on a raised gun.
	if _state == "deploy":
		var p := clampf(_t / _dur, 0.0, 1.0)
		var left := pow(1.0 - p, 2.0)
		pos += Vector3(0.0, -0.34 * left, 0.10 * left)
		rot += Vector3(-0.85 * left, 0.25 * left, 0.30 * left)
	elif _state == "reload":
		var pose := _reload_pose(_weapon, clampf(_t / _reload_total, 0.0, 1.0))
		pos += pose[0]
		rot += pose[1]
	elif _state == "inspect":
		var pose := _inspect_pose(_weapon, clampf(_t / _dur, 0.0, 1.0))
		pos += pose[0]
		rot += pose[1]
	if _slash > 0.0:
		var s := 1.0 - _slash / SWING
		pos += Vector3(-0.30 * sin(PI * s), 0.06 * sin(PI * s), -0.06 * sin(PI * s))
		rot += Vector3(0.10 * sin(PI * s), 0.7 - 1.5 * s, 0.6 * sin(PI * s))
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


func _reload_pose(weapon: int, u: float) -> Array:
	var tilt := sin(PI * clampf(u / 0.85, 0.0, 1.0))
	var pos := Vector3(0.02 * tilt, -0.07 * tilt, 0.04 * tilt)
	var rot := Vector3(-0.15 * tilt, 0.35 * tilt, -0.45 * tilt)
	var root := weapons[weapon]
	var mag: Node3D = root.get_node_or_null("Mag")
	if mag:
		var drop := 0.0
		if u < 0.18:
			drop = 0.0
		elif u < 0.42:
			drop = _ease((u - 0.18) / 0.24)
		elif u < 0.70:
			drop = 1.0 - _ease((u - 0.42) / 0.28)
		else:
			drop = 0.0
		mag.position = _mag_home(weapon) + Vector3(0.0, -0.30 * drop, 0.02 * drop)
		mag.rotation = Vector3(0.4 * drop, 0.0, 0.15 * drop)
	if weapon == TrialFighter.RIFLE:
		var handle: Node3D = root.get_node_or_null("Handle")
		if handle:
			var rack := sin(PI * clampf((u - 0.82) / 0.13, 0.0, 1.0))
			handle.position = Vector3(0.035, 0.03, 0.06 + 0.07 * rack)
	else:
		var slide: Node3D = root.get_node_or_null("Slide")
		if slide:
			var rack := sin(PI * clampf((u - 0.80) / 0.15, 0.0, 1.0))
			slide.position = Vector3(0, 0.02, 0.02 + 0.055 * rack)
	return [pos, rot]


func _mag_home(weapon: int) -> Vector3:
	return Vector3(0, -0.045, 0.02) if weapon == TrialFighter.RIFLE else Vector3(0, -0.045, 0.075)


func _inspect_pose(weapon: int, u: float) -> Array:
	if weapon == TrialFighter.KNIFE:
		# Two finger-ring flips with a catch between, karambit style.
		var spin := 0.0
		var lift := 0.0
		if u < 0.12:
			spin = -0.4 * _ease(u / 0.12)
		elif u < 0.50:
			spin = -0.4 + TAU * _ease((u - 0.12) / 0.38)
			lift = 0.06
		elif u < 0.58:
			spin = -0.4
			lift = 0.06 * (1.0 - _ease((u - 0.50) / 0.08))
		elif u < 0.90:
			spin = -0.4 + TAU * _ease((u - 0.58) / 0.32)
			lift = 0.06
		else:
			spin = -0.4 * (1.0 - _ease((u - 0.90) / 0.10))
		return [Vector3(0.0, lift, -0.04), Vector3(0.15, 0.25, spin)]
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


func _ease(p: float) -> float:
	p = clampf(p, 0.0, 1.0)
	return p * p * (3.0 - 2.0 * p)