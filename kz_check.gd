extends SceneTree
## godot --headless --fixed-fps 128 --path . --script res://kz_check.gd

const Fighter = preload("res://fighter.gd")
const U := Fighter.UNIT
const LEDGE_X := 80.0
const LEDGE_HEIGHT := 61.0
const ROOF_HEIGHT := 58.0
const DROP_U := 64.0
const STANDING_IMPULSE := 298.865
const PRE_DUCK_IMPULSE := 301.994
const REFERENCE_GRAVITY := 800.0
const TUCK_U := 9.0

var arena := Node3D.new()
var actor: Fighter
var collider: CollisionShape3D
var dt: float
var errors: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	dt = 1.0 / Engine.physics_ticks_per_second
	root.add_child(arena)
	_box(Vector3(0, -8, 0), Vector3(8000, 16, 8000))
	_box(Vector3(LEDGE_X + 180, LEDGE_HEIGHT * 0.5, 240), Vector3(360, LEDGE_HEIGHT, 120))
	_box(Vector3(132, ROOF_HEIGHT + 4, -240), Vector3(64, 8, 120))
	_box(Vector3(-80, DROP_U * 0.5, 600), Vector3(160, DROP_U, 120))
	await _strafe_and_hop()
	var standing := await _jump_height(false)
	var preduck := await _jump_height(true)
	var late_duck := await _jump_height(false, 12)
	var simultaneous := await _jump_height(false, 1)
	_expect(absf(standing - 55.826) <= 0.15, "Standing jump apex %.2f u" % standing)
	_expect(absf(preduck - 56.995) <= 0.15, "Fully crouched jump apex %.2f u" % preduck)
	_expect(absf(late_duck - 64.83) <= 0.15, "Jump then duck apex %.2f u" % late_duck)
	_expect(absf(late_duck - standing - TUCK_U) <= 0.15, "In-air foot lift %.2f u" % (late_duck - standing))
	_expect(absf(simultaneous - late_duck) <= 0.1, "Simultaneous jump and duck apex %.2f vs late duck %.2f u" % [simultaneous, late_duck])
	await _jump_height(false, 0, true)
	await _ledge_jump(false)
	await _ledge_jump(true)
	await _low_roof()
	await _snapshot_landing()
	for problem in errors:
		push_error(problem)
	print("KZ_CHECK errors=", errors.size())
	quit(0 if errors.is_empty() else 1)


func _box(center_u: Vector3, size_u: Vector3) -> void:
	var body := StaticBody3D.new()
	var box := BoxShape3D.new()
	box.size = size_u * U
	var collision := CollisionShape3D.new()
	collision.shape = box
	body.add_child(collision)
	body.position = center_u * U
	arena.add_child(body)


func _spawn(x_u: float = 0, z_u: float = 0, floor_u: float = 0) -> void:
	if is_instance_valid(actor):
		actor.free()
	actor = Fighter.new()
	actor.position = Vector3(x_u, floor_u + 1.0, z_u) * U
	arena.add_child(actor)
	collider = actor.find_children("*", "CollisionShape3D", false, false)[0]
	for _i in 64:
		await _tick({})
		if actor.grounded:
			return
	_expect(false, "Player did not settle onto the test floor")


func _tick(command: Dictionary) -> void:
	await physics_frame
	actor.step(command, dt)


func _snapshot_landing() -> void:
	await _spawn()
	var airborne := Fighter.new()
	airborne.position = Vector3(0, 3, 0)
	arena.add_child(airborne)
	await physics_frame
	actor.step({}, dt)
	airborne.step({}, dt)
	_expect(actor.is_on_floor() and not airborne.is_on_floor(), "Snapshot test needs distinct prior floor contacts")
	var snapshot := actor.state()
	snapshot["position"] = Vector3(3, 0.12, 1)
	snapshot["velocity"] = Vector3(0, -0.1, 0)
	snapshot["grounded"] = false
	actor.restore(snapshot)
	airborne.restore(snapshot)
	var landing_tick := 0
	var hop_tick := 0
	for tick in range(1, 65):
		await physics_frame
		var command := {} if tick == 1 else {"jump": true}
		actor.step(command, dt)
		airborne.step(command, dt)
		var same_motion := actor.position.is_equal_approx(airborne.position) and actor.velocity.is_equal_approx(airborne.velocity)
		if actor.grounded != airborne.grounded or not same_motion:
			_expect(false, "Snapshot replay diverged on tick %d, heights %.5f / %.5f m" % [tick, actor.position.y, airborne.position.y])
			break
		if tick == 1:
			_expect(not actor.grounded and actor.position.y > 0.11 and actor.position.y < 0.12, "Airborne snapshot snapped to the floor")
		if actor.grounded and landing_tick == 0:
			landing_tick = tick
		elif landing_tick > 0 and actor.velocity.y > 0:
			hop_tick = tick
			break
	_expect(landing_tick > 1 and hop_tick == landing_tick + 1, "Held jump after snapshot: landing tick %d, hop tick %d" % [landing_tick, hop_tick])
	print("Snapshot replay: landing tick %d / held jump tick %d" % [landing_tick, hop_tick])
	airborne.free()


func _feet_u() -> float:
	var bounds := collider.shape.get_debug_mesh().get_aabb()
	return (collider.global_position.y + bounds.position.y) / U


func _head_u() -> float:
	var bounds := collider.shape.get_debug_mesh().get_aabb()
	return (collider.global_position.y + bounds.end.y) / U


func _strafe_and_hop() -> void:
	await _spawn(0, 1800)
	for _i in 100:
		await _tick({"move": Vector2.UP})
	var run := actor.accuracy_speed / U
	_expect(absf(run - 215.0) < 0.1, "Rifle ground speed %.2f u/s" % run)
	await _tick({"jump": true})
	_expect(not actor.grounded, "Running jump did not leave the floor")
	var takeoff := run
	var hop_count := 0
	for hop_index in 30:
		for _i in 128:
			# With D held, keep the input direction perpendicular to the current velocity.
			var yaw := atan2(-actor.velocity.x, -actor.velocity.z)
			await _tick({"move": Vector2.RIGHT, "yaw": yaw})
			if actor.grounded:
				break
		var landing := actor.accuracy_speed / U
		_expect(actor.grounded and landing > takeoff + 1.0, "Air strafe #%d: %.2f to %.2f u/s" % [hop_index + 1, takeoff, landing])
		await _tick({"jump": true})
		var hop := actor.accuracy_speed / U
		_expect(not actor.grounded and absf(hop - landing) < 0.1, "Immediate hop speed %.2f vs landing %.2f u/s" % [hop, landing])
		hop_count += 1
		if hop_index == 0:
			print("Rifle horizontal speed (u/s): run %.2f / strafe landing %.2f / hop %.2f" % [run, landing, hop])
		if takeoff > 600.0:
			break
		takeoff = hop
	_expect(takeoff > 600.0 and actor.accuracy_speed / U > takeoff + 1.0, "Air strafing failed to keep gaining above 600 u/s")
	print("Strafes and immediate hops: %d hops, %.2f u/s" % [hop_count, actor.accuracy_speed / U])


func _jump_height(preduck: bool, tuck_tick: int = 0, drop: bool = false) -> float:
	var air_duck := tuck_tick > 0
	var expected_launch := PRE_DUCK_IMPULSE if preduck else STANDING_IMPULSE
	var move := Vector2.RIGHT if drop else Vector2.ZERO
	if drop:
		await _spawn(-125, 600, DROP_U)
	else:
		await _spawn()
	# The reference standing jumps begin after at least one second grounded.
	for _i in Engine.physics_ticks_per_second:
		await _tick({"crouch": preduck})
	var hull_height := _head_u() - _feet_u()
	_expect(absf(hull_height - (54.0 if preduck else 72.0)) < 0.25, "Starting hull height %.2f u" % hull_height)
	if drop:
		for _i in 128:
			await _tick({"move": move})
			if actor.position.x / U >= -40.0:
				break
	var start := _feet_u()
	var peak := 0.0
	var peak_tick := 0
	var landing_tick := 0
	var max_curve_error := 0.0
	var impulse := 0.0
	# Tick 1 includes the jump command and its first interval of flight.
	for tick in range(1, 193):
		await _tick({"move": move, "jump": tick == 1, "crouch": preduck or (air_duck and tick >= tuck_tick)})
		if tick == 1:
			_expect(not actor.grounded, "Jump did not leave its starting surface")
			impulse = actor.velocity.y / U + REFERENCE_GRAVITY * dt
		if actor.grounded:
			landing_tick = tick
			break
		var height := _feet_u() - start
		if height > peak:
			peak = height
			peak_tick = tick
		var t := tick * dt
		var predicted := expected_launch * t - 0.5 * REFERENCE_GRAVITY * t * t
		if air_duck and tick >= tuck_tick:
			predicted += TUCK_U
		max_curve_error = maxf(max_curve_error, absf(height - predicted))
	_expect(landing_tick > 0, "Jump did not land")
	_expect(absf(impulse - expected_launch) <= 0.1, "Inferred takeoff impulse %.3f u/s, expected %.3f" % [impulse, expected_launch])
	_expect(absf(peak_tick * dt - expected_launch / REFERENCE_GRAVITY) <= dt, "Apex tick %d" % peak_tick)
	var descent := DROP_U if drop else 0.0
	_expect(absf(_feet_u() - start + descent) < 0.25, "Landing height did not match test geometry")
	var extra_fall := descent + (TUCK_U if air_duck else 0.0)
	var landing_time := (expected_launch + sqrt(expected_launch ** 2 + 2.0 * REFERENCE_GRAVITY * extra_fall)) / REFERENCE_GRAVITY
	var landing_ms := landing_tick * dt * 1000.0
	_expect(absf(landing_tick * dt - landing_time) <= dt, "Flight time %.3f ms for %.0f u drop" % [landing_ms, descent])
	if air_duck:
		_expect(landing_tick == ceili(landing_time / dt), "Held air crouch touched ground on tick %d" % landing_tick)
	elif preduck:
		_expect(landing_tick == ceili(0.754918 / dt), "Fully crouched jump touched ground on tick %d" % landing_tick)
	elif not drop and not preduck:
		# First grounded 64 Hz sample across 29 standing jumps captured in CS2.
		_expect(landing_ms >= 747.04 and landing_ms <= 755.86, "Standing landing %.3f ms outside CS2 capture window" % landing_ms)
	_expect(max_curve_error < 0.25, "Airborne feet diverged %.3f u from predicted trajectory" % max_curve_error)
	print("Jump (preduck=%s tuck_tick=%d drop=%.0f u): impulse %.3f u/s / peak %.2f u at %.3f ms / landing %.3f ms" % [
		preduck, tuck_tick, descent, impulse, peak, peak_tick * dt * 1000.0, landing_ms])
	return peak


func _ledge_jump(air_duck: bool) -> void:
	await _spawn(-160, 240)
	for _i in 200:
		await _tick({"move": Vector2.RIGHT})
		if actor.position.x >= 0.0:
			break
	await _tick({"move": Vector2.RIGHT, "jump": true})
	var released_above_edge := false
	var landed_on_top := false
	var lowest_over_ledge := INF
	for i in 140:
		var feet := _feet_u()
		# Release while the higher hull is still airborne, over the lip.
		if air_duck and actor.position.x / U > LEDGE_X + 1.0 and feet > LEDGE_HEIGHT and not actor.grounded:
			released_above_edge = true
		await _tick({"move": Vector2.RIGHT, "crouch": air_duck and i >= 8 and not released_above_edge})
		if released_above_edge and actor.position.x / U > LEDGE_X + 1.0:
			lowest_over_ledge = minf(lowest_over_ledge, _feet_u())
		if actor.grounded and _feet_u() > LEDGE_HEIGHT - 0.5:
			landed_on_top = true
	_expect(landed_on_top == air_duck, "61 u ledge, air_duck=%s landed_on_top=%s" % [air_duck, landed_on_top])
	if air_duck:
		_expect(released_above_edge, "Could not release crouch while airborne above the lip")
		_expect(lowest_over_ledge >= LEDGE_HEIGHT - 0.5, "Releasing crouch penetrated ledge: feet at %.2f u" % lowest_over_ledge)
		_expect(_head_u() - _feet_u() > 71.5, "Player could not stand after landing on ledge")
	print("61 u ledge: air_duck=%s landed_on_top=%s" % [air_duck, landed_on_top])


func _low_roof() -> void:
	await _spawn(0, -240)
	for _i in 48:
		await _tick({"crouch": true})
	var crouch_run := 0.0
	for _i in 384:
		await _tick({"move": Vector2.RIGHT, "crouch": true})
		crouch_run = maxf(crouch_run, actor.accuracy_speed / U)
		if actor.position.x / U >= 132.0:
			break
	_expect(absf(crouch_run - 73.1) <= 0.1, "Crouched rifle speed from rest %.2f u/s" % crouch_run)
	_expect(actor.position.x / U >= 132.0, "Crouching player did not enter the tunnel: x=%.2f u" % (actor.position.x / U))
	var highest_under_roof := _head_u()
	var crouched_head_error := 0.0
	for _i in 42:
		await _tick({})
		highest_under_roof = maxf(highest_under_roof, _head_u())
		crouched_head_error = maxf(crouched_head_error, absf(_head_u() - 54.0))
	_expect(highest_under_roof <= ROOF_HEIGHT + 0.25, "Uncrouch penetrated ceiling: %.2f u" % highest_under_roof)
	_expect(crouched_head_error <= 0.25, "Head moved away from 54 u crouch height under the low roof")
	for _i in 320:
		await _tick({"move": Vector2.RIGHT})
		if actor.position.x / U >= 196.0:
			break
	for _i in 42:
		await _tick({})
	_expect(actor.position.x / U >= 196.0 and absf(_head_u() - _feet_u() - 72.0) < 0.25, "Player did not leave tunnel and regain standing height")
	print("58 u low roof: crouch speed %.2f u/s / head on release %.2f u / height after exit %.2f u" % [crouch_run, highest_under_roof, _head_u() - _feet_u()])


func _expect(ok: bool, problem: String) -> void:
	if not ok:
		errors.append(problem)
