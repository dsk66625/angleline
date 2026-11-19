class_name TrialFighter
extends CharacterBody3D

const UNIT := 0.0254
const RUN_SPEED := [240.0, 215.0]
const CAPACITY := [13, 30]
const FIRE_CYCLE := [0.15, 0.10]
const STAND_EYE := 64.0 * UNIT
const DUCK_EYE := 46.0 * UNIT
const GRAVITY := 800.0 * UNIT
const JUMP_SPEED := 301.99 * UNIT
const ACCEL := 5.5
const FRICTION := 5.2
const STOP_SPEED := 80.0 * UNIT
const GROUND_STOP_EPSILON := 3.5 * UNIT
const GROUND_REFERENCE_HZ := 64.0
const BASE_SPREAD := [0.38, 0.40165]
const SHOT_PENALTY := [0.32, 0.4469]
const RIFLE_SINGLE_RECOVERY := 0.368
const RIFLE_MOVEMENT_SPREAD := 0.17506
const RIFLE_MOVEMENT_CURVE := 0.25
const RIFLE_MAX_SPREAD_SPEED_RATIO := 0.95
const FIRE_RECOVERY_FRACTION := 0.1
const MIN_FIRE_INACCURACY := 0.00001
const ACCURATE_SPEED_RATIO := 0.34

var yaw := 0.0
var pitch := 0.0
var eye := STAND_EYE
var weapon := 1
var rounds := PackedInt32Array([13, 30])
var fire_inaccuracy := 0.0
var accuracy_recovery_shots := 0
var cooldown := 0.0
var reloading := 0.0
var streak := 0
var shots := 0
var recoil := Vector2.ZERO
var grounded := false
var accuracy_speed := 0.0
var last_fire := 0.0

var _collider: CollisionShape3D
var _shape: CapsuleShape3D
var _avatar: Node3D
var _stance := 0.0
var _fire_held := false

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.19
	floor_stop_on_slope = true
	safe_margin = 0.002
	_shape = CapsuleShape3D.new()
	_shape.radius = 16.0 * UNIT
	_collider = CollisionShape3D.new()
	_collider.shape = _shape
	add_child(_collider)
	_apply_stance()

func show_avatar(color: Color) -> void:
	if is_instance_valid(_avatar):
		return
	_avatar = Node3D.new()
	add_child(_avatar)
	var vest := StandardMaterial3D.new()
	vest.albedo_color = color
	vest.roughness = 0.9
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color("#252e33")
	trim.roughness = 0.9
	_piece(Vector3(0.58, 0.69, 0.35), Vector3(0, 1.06, 0), vest)
	_piece(Vector3(0.32, 0.32, 0.30), Vector3(0, 1.55, 0), trim)
	_piece(Vector3(0.18, 0.58, 0.19), Vector3(-0.16, 0.42, 0), trim)
	_piece(Vector3(0.18, 0.58, 0.19), Vector3(0.16, 0.42, 0), trim)
	_piece(Vector3(0.15, 0.13, 0.65), Vector3(0.27, 1.17, -0.33), trim)
	_apply_stance()

func _piece(size: Vector3, location: Vector3, material: Material) -> void:
	var instance := MeshInstance3D.new()
	var geometry := BoxMesh.new()
	geometry.size = size
	geometry.material = material
	instance.mesh = geometry
	instance.position = location
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_avatar.add_child(instance)

func _apply_stance() -> void:
	eye = lerpf(STAND_EYE, DUCK_EYE, _stance)
	_shape.height = lerpf(72.0, 54.0, _stance) * UNIT
	_collider.position.y = _shape.height * 0.5
	if is_instance_valid(_avatar):
		_avatar.scale.y = lerpf(1.0, 0.75, _stance)
		_avatar.rotation.y = yaw

func eye_position() -> Vector3:
	return global_position + Vector3.UP * eye

func reset_equipment() -> void:
	rounds = PackedInt32Array(CAPACITY)
	fire_inaccuracy = 0.0
	accuracy_recovery_shots = 0
	cooldown = 0.0
	reloading = 0.0
	streak = 0
	recoil = Vector2.ZERO
	_fire_held = false

static func look_direction(yaw_angle: float, pitch_angle: float) -> Vector3:
	return Vector3(-sin(yaw_angle) * cos(pitch_angle), sin(pitch_angle),
		-cos(yaw_angle) * cos(pitch_angle))

static func turn_delta(counts: Vector2, sensitivity: float, axis_scale: Vector2) -> Vector2:
	return -counts * axis_scale * deg_to_rad(0.022 * sensitivity)

func step(command: Dictionary, dt: float) -> Dictionary:
	yaw = command.get("yaw", yaw)
	pitch = command.get("pitch", pitch)
	var next_weapon: int = command.get("weapon", weapon)
	if next_weapon != weapon:
		weapon = next_weapon
		cooldown = maxf(cooldown, 0.22)
		reloading = 0.0
		fire_inaccuracy = 0.0
		accuracy_recovery_shots = 0
		streak = 0

	var direction: Vector2 = command.get("move", Vector2.ZERO)
	var ducking: bool = command.get("crouch", false)
	var walking: bool = command.get("walk", false)
	_update_stance(ducking, dt)
	var max_speed := float(RUN_SPEED[weapon]) * UNIT
	var speed_limit := max_speed
	if walking:
		speed_limit *= 0.52
	if _stance > 0.0:
		speed_limit = minf(speed_limit, max_speed * lerpf(1.0, 0.34, _stance))
	move_player(direction, speed_limit, bool(command.get("jump", false)), dt)

	cooldown = maxf(cooldown - dt, -dt)
	_recover_accuracy(dt)
	recoil = recoil.move_toward(Vector2.ZERO, dt * (18.0 if streak > 0 else 25.0))
	if reloading > 0.0:
		reloading = maxf(0.0, reloading - dt)
		if reloading == 0.0:
			rounds[weapon] = CAPACITY[weapon]
	if bool(command.get("reload", false)) and reloading == 0.0 and rounds[weapon] < CAPACITY[weapon]:
		reloading = 1.55 if weapon == 0 else 2.10

	var held: bool = command.get("fire", false)
	var pressed: bool = command.get("fire_pressed", false)
	var wants_shot := pressed or (held and (weapon == 1 or not _fire_held))
	_fire_held = held
	if not wants_shot or cooldown > 0.00001 or reloading > 0.0 or rounds[weapon] <= 0:
		return {}

	var fire_interval: float = FIRE_CYCLE[weapon]
	cooldown = (cooldown if streak > 0 and held and weapon == 1 else 0.0) + fire_interval
	rounds[weapon] -= 1
	shots += 1
	last_fire = spread_degrees()
	fire_inaccuracy += SHOT_PENALTY[weapon]
	streak += 1
	accuracy_recovery_shots = streak
	var rng := RandomNumberGenerator.new()
	rng.seed = int(shots * 9619 + weapon * 401)
	var offset := Vector2.from_angle(rng.randf_range(0.0, TAU)) * sqrt(rng.randf()) * last_fire
	var direction_of_shot := look_direction(yaw + deg_to_rad(recoil.x + offset.x),
		pitch + deg_to_rad(recoil.y + offset.y))
	var drift := sin(float(streak) * 0.63) * minf(float(streak) * 0.12, 1.10)
	var lift := 1.45 if weapon == 0 else minf(0.88 + float(streak) * 0.21, 2.65)
	recoil += Vector2(drift, lift)
	return {"origin": eye_position(), "direction": direction_of_shot, "weapon": weapon, "shots": shots}

func _recover_accuracy(dt: float) -> void:
	if fire_inaccuracy == 0.0:
		return
	var recovery_time := 0.27
	if weapon == 1:
		var burst_weight := clampf((accuracy_recovery_shots - 2) / 3.0, 0.0, 1.0)
		var standing := lerpf(RIFLE_SINGLE_RECOVERY, 0.506, burst_weight)
		var crouching := lerpf(0.305, 0.420, burst_weight)
		recovery_time = lerpf(standing, crouching, _stance)
	fire_inaccuracy *= pow(FIRE_RECOVERY_FRACTION, dt / recovery_time)
	if fire_inaccuracy <= SHOT_PENALTY[weapon] * FIRE_RECOVERY_FRACTION:
		streak = 0
	if fire_inaccuracy <= MIN_FIRE_INACCURACY:
		fire_inaccuracy = 0.0
		accuracy_recovery_shots = 0

func _update_stance(ducking: bool, dt: float) -> void:
	if not ducking and _stance > 0.0 and test_move(global_transform, Vector3.UP * (18.0 * UNIT * _stance)):
		ducking = true
	_stance = move_toward(_stance, 1.0 if ducking else 0.0, dt * (7.0 if ducking else 5.0))
	_apply_stance()

func move_player(input_direction: Vector2, speed_limit: float, jump: bool, dt: float) -> void:
	var wish := Vector3(input_direction.x, 0, input_direction.y).rotated(Vector3.UP, yaw)
	var magnitude := minf(wish.length(), 1.0)
	wish = wish.normalized()
	var previous_lateral := Vector3(velocity.x, 0, velocity.z)
	var lateral := previous_lateral
	var acceleration_step := dt
	if grounded and jump:
		velocity.y = JUMP_SPEED
		grounded = false
	elif grounded:
		var speed := lateral.length()
		acceleration_step = ground_friction_step(speed, dt)
		var next_speed := maxf(0.0, speed - maxf(speed, STOP_SPEED) * FRICTION * acceleration_step)
		if magnitude == 0.0 and next_speed < GROUND_STOP_EPSILON:
			next_speed = 0.0
		if speed > 0.0:
			lateral *= next_speed / speed
		velocity.y = -0.2
	else:
		velocity.y -= GRAVITY * dt
	var desired := speed_limit * magnitude
	var cap := desired if grounded else minf(desired, 30.0 * UNIT)
	var acceleration := ACCEL if grounded else 12.0
	var available := cap - lateral.dot(wish)
	if available > 0.0:
		lateral += wish * minf(available, desired * acceleration * acceleration_step)
	var integrate_ground := grounded
	# Ground displacement follows the average speed before and after acceleration.
	var travel := previous_lateral.lerp(lateral, 0.5) if integrate_ground else lateral
	velocity.x = travel.x
	velocity.z = travel.z
	move_and_slide()
	if integrate_ground:
		var min_floor_normal := cos(floor_max_angle)
		for index in get_slide_collision_count():
			var normal := get_slide_collision(index).get_normal()
			if normal.y < min_floor_normal:
				var wall := Vector3(normal.x, 0, normal.z).normalized()
				if lateral.dot(wall) < 0.0:
					lateral = lateral.slide(wall)
		velocity.x = lateral.x
		velocity.z = lateral.z
	grounded = is_on_floor()
	if grounded:
		velocity.y = 0.0
	accuracy_speed = Vector2(velocity.x, velocity.z).length()

static func ground_friction_step(speed: float, dt: float) -> float:
	if speed <= STOP_SPEED:
		return dt
	# Match the reference velocity loss per 64 Hz interval even when the interval is split.
	var reference_retained := 1.0 - FRICTION / GROUND_REFERENCE_HZ
	return (1.0 - pow(reference_retained, dt * GROUND_REFERENCE_HZ)) / FRICTION

func spread_degrees() -> float:
	if grounded and is_zero_approx(accuracy_speed):
		return 0.0
	var ratio := accuracy_speed / (float(RUN_SPEED[weapon]) * UNIT)
	var excess_speed := maxf(ratio - ACCURATE_SPEED_RATIO, 0.0)
	var airborne := 5.0 if not grounded else 0.0
	if weapon == 1:
		var moving := minf(excess_speed / (RIFLE_MAX_SPREAD_SPEED_RATIO - ACCURATE_SPEED_RATIO), 1.0)
		var stationary_cone := tan(deg_to_rad(BASE_SPREAD[weapon] + fire_inaccuracy))
		var movement_cone := pow(moving, RIFLE_MOVEMENT_CURVE) * RIFLE_MOVEMENT_SPREAD
		return rad_to_deg(atan(stationary_cone + movement_cone)) + airborne
	var moving := minf(excess_speed / (1.0 - ACCURATE_SPEED_RATIO), 1.0)
	return BASE_SPREAD[weapon] + pow(moving, 1.5) * 4.6 + airborne + fire_inaccuracy

func state() -> Dictionary:
	return {"position": global_position, "velocity": velocity, "yaw": yaw, "pitch": pitch,
		"stance": _stance, "grounded": grounded, "weapon": weapon, "rounds": rounds.duplicate(),
		"fire_inaccuracy": fire_inaccuracy, "accuracy_recovery_shots": accuracy_recovery_shots,
		"cooldown": cooldown, "reloading": reloading, "streak": streak,
		"shots": shots, "recoil": recoil, "fire_held": _fire_held}

func restore(data: Dictionary) -> void:
	global_position = data["position"]
	velocity = data["velocity"]
	yaw = data["yaw"]
	pitch = data["pitch"]
	_stance = data["stance"]
	grounded = data["grounded"]
	weapon = data["weapon"]
	rounds = data["rounds"].duplicate()
	fire_inaccuracy = data.get("fire_inaccuracy", 0.0)
	accuracy_recovery_shots = data.get("accuracy_recovery_shots", data["streak"])
	cooldown = data["cooldown"]
	reloading = data["reloading"]
	streak = data["streak"]
	shots = data["shots"]
	recoil = data["recoil"]
	_fire_held = data["fire_held"]
	accuracy_speed = Vector2(velocity.x, velocity.z).length()
	_apply_stance()
