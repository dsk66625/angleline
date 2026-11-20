extends RefCounted

# AK angular impulses measured from CS2 demo 14129. X is yaw left, Y is pitch up (deg/s).
const IMPULSES := [
	Vector2(-10.330194, 19.988424), Vector2(6.623972, 20.593727), Vector2(-2.320100, 22.837868),
	Vector2(-0.717850, 25.142819), Vector2(7.452341, 26.802100), Vector2(4.670539, 28.640161),
	Vector2(9.157417, 28.104024), Vector2(-6.451948, 29.094439), Vector2(-20.777478, 21.515995),
	Vector2(-11.432227, 27.692794), Vector2(2.602806, 29.868695), Vector2(-15.330448, 25.777671),
	Vector2(-19.731888, 22.592749), Vector2(-9.851860, 28.334462), Vector2(10.074676, 28.256973),
	Vector2(1.212947, 29.975134), Vector2(2.717597, 29.876501), Vector2(11.656461, 27.642769),
	Vector2(18.673956, 23.479388), Vector2(-7.848667, 28.955092), Vector2(9.609986, 28.419143),
	Vector2(0.239027, 29.999046), Vector2(0.374599, 29.997655), Vector2(14.419018, 26.307643),
	Vector2(6.481427, 29.291483), Vector2(-5.478941, 29.495443), Vector2(-12.813542, 27.125881),
	Vector2(-21.770970, 20.640367), Vector2(-11.027329, 27.899784), Vector2(3.922194, 29.742499),
]
const STEP := 1.0 / 128.0
const CYCLE := 0.1
const SERVER_HZ := 64.0
const ANGLE_RETAINED := exp(-8.0 * STEP)
const VELOCITY_DECAY := 4.5
const VELOCITY_RETAINED := exp(-VELOCITY_DECAY * STEP)
const CENTER_EPSILON_DEG := 0.0625

# State immediately after the last shot, anchored to its scheduled time.
var base_angle := Vector2.ZERO
var base_velocity := Vector2.ZERO
var simulation_time := 0.0
var last_shot_time := 0.0
var index_after_shot := 0.0
var elapsed: float:
	get:
		return simulation_time - last_shot_time if index_after_shot > 0.0 else 0.0

func reset() -> void:
	base_angle = Vector2.ZERO
	base_velocity = Vector2.ZERO
	last_shot_time = simulation_time
	index_after_shot = 0.0

func advance(dt: float) -> void:
	simulation_time += dt
	# Even after a full magazine both the aim and the impulse index have settled.
	if elapsed >= 2.0:
		reset()

func _angle_at(seconds: float) -> Vector2:
	var angle := base_angle
	var velocity := base_velocity
	var steps := seconds / STEP
	var sample_count := ceili(steps)
	var previous_angle := angle
	# Use whole reference steps and interpolate their endpoints for a fractional shot time.
	for _i in sample_count:
		previous_angle = angle
		var next_velocity := velocity * VELOCITY_RETAINED
		angle = (angle * ANGLE_RETAINED).move_toward(Vector2.ZERO, 18.0 * STEP)
		angle += (velocity + next_velocity) * (0.5 * STEP)
		velocity = next_velocity
	return angle.lerp(previous_angle, sample_count - steps)

func aim_offset(seconds: float) -> Vector2:
	if index_after_shot == 0.0:
		return Vector2.ZERO
	var offset := 2.0 * _angle_at(maxf(0.0, seconds - STEP))
	return Vector2.ZERO if offset.length_squared() < CENTER_EPSILON_DEG * CENTER_EPSILON_DEG else offset

func fire(lateness: float) -> Vector2:
	var interval := maxf(0.0, elapsed - lateness)
	var shot_offset := aim_offset(interval)
	var shot_time := simulation_time - lateness
	var shot_tick := floori(shot_time * SERVER_HZ + 1e-8)
	var recovery_tick := floori((last_shot_time + CYCLE) * SERVER_HZ + 1e-8)
	var decay_ticks := maxi(0, shot_tick - recovery_tick - 1)
	var index := index_after_shot * pow(10.0, -decay_ticks / 32.0)
	if index < 0.1:
		index = 0.0
	var impulse: Vector2 = IMPULSES[clampi(floori(index), 0, IMPULSES.size() - 1)]
	# The outgoing ray samples the old state one reference step early. CS2 rebases
	# the next impulse one step late. Both offsets are visible in shot telemetry.
	base_angle = _angle_at(interval + STEP)
	base_velocity = base_velocity * exp(-VELOCITY_DECAY * interval) + impulse
	index_after_shot = index + 1.0
	last_shot_time = shot_time
	return shot_offset

func state() -> Dictionary:
	return {"angle": base_angle, "velocity": base_velocity, "time": simulation_time,
		"last_shot": last_shot_time, "index": index_after_shot}

func restore(data: Dictionary, previous_offset: Vector2) -> void:
	base_angle = data.get("angle", previous_offset * 0.5)
	base_velocity = data.get("velocity", Vector2.ZERO)
	simulation_time = data.get("time", 0.0)
	last_shot_time = data.get("last_shot", simulation_time)
	index_after_shot = data.get("index", 0.0 if previous_offset == Vector2.ZERO else 1.0)
