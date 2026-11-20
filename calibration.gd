extends SceneTree
## godot --headless --fixed-fps 128 --path . --script res://calibration.gd -- --out=<directory>
## Reports timing at physics-tick boundaries. This script is independent of the play scene.

const Fighter = preload("res://fighter.gd")
const SPEED_EPS_U := 0.001
const ANGLE_EPS_DEG := 0.00001
const BURST_LENGTH := 5
const WEAPONS := ["pistol", "rifle"]
const ACCURATE_RUN_FRACTION := 0.34

var arena := Node3D.new()
var actor: Fighter
var probe: Fighter
var dt: float
var tick_hz: int
var csv: FileAccess
var errors: Array[String] = []
var probe_ray_error_deg := 0.0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	tick_hz = Engine.physics_ticks_per_second
	dt = 1.0 / tick_hz
	var output := OS.get_user_data_dir().path_join("calibration")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			output = arg.trim_prefix("--out=")
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Cannot create calibration output directory: " + output)
		quit(1)
		return
	csv = FileAccess.open(output.path_join("trace.csv"), FileAccess.WRITE)
	if csv == null:
		push_error("Cannot create trace.csv: " + error_string(FileAccess.get_open_error()))
		quit(1)
		return
	csv.store_csv_line(["weapon", "scenario", "phase", "tick", "time_ms", "x_displacement_u",
			"vx_u_per_s", "grounded", "hud_spread_deg", "actual_shot_cone_deg",
			"probe_next_shot_cone_deg", "recoil_yaw_deg", "recoil_pitch_deg", "rounds_left",
			"residual_fire_inaccuracy_deg", "probe_ray_error_from_recoiled_aim_deg"])
	root.add_child(arena)
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(500, 1, 500)
	collision.shape = floor_shape
	ground.add_child(collision)
	ground.position.y = -0.5
	arena.add_child(ground)
	var reports := {}
	for slot in WEAPONS.size():
		var report := await _measure_weapon(slot)
		reports[WEAPONS[slot]] = report
	csv.close()
	var summary := {
		"engine": Engine.get_version_info().string, "physics_hz": tick_hz, "tick_ms": dt * 1000,
		"meters_per_u": Fighter.UNIT, "fighter_script_sha256": FileAccess.get_sha256("res://fighter.gd"),
		"limits": {"angle_epsilon_deg": ANGLE_EPS_DEG, "speed_epsilon_u_per_s": SPEED_EPS_U},
		"protocol": {
			"environment": "Movement timings use flat ground, standing, yaw=0. D is positive X. Boundary trials also exercise crouched and airborne shots.",
			"ticks": "Rows are end-of-tick. Tick 0 is immediately before the input change, or immediately after the last shot in recovery trials.",
			"units": "Signed X displacement uses game units (u). Engine positions use meters.",
			"probe": "An independent character restores the pre-tick state and requests a real shot with the same movement input. Blank probe cone means firing was unavailable or untested.",
			"full_accuracy": "A legal shot has the same recorded cone as a stationary first shot within angle_epsilon_deg. Reticle spread and recoil are separate columns.",
			"shot_recovery_90": "First sample with residual firing inaccuracy at or below 10% of one shot's penalty. This residual affects the cone above the ground accuracy threshold or while airborne.",
			"counter": "Reversal continues through the first negative velocity outside the accuracy band. All times start at release.",
			"shooting": "Rifle continuously holds fire during burst. Pistol retries trigger on each physics tick. Recovery starts at the final successful shot.",
			"trace": "trace.csv contains all per-tick observations for each weapon, scenario and phase."
		},
		"weapons": reports, "errors": errors,
	}
	var summary_file := FileAccess.open(output.path_join("summary.json"), FileAccess.WRITE)
	if summary_file == null:
		push_error("Cannot create summary.json: " + error_string(FileAccess.get_open_error()))
		quit(1)
		return
	summary_file.store_string(JSON.stringify(summary, "\t", true, true) + "\n")
	summary_file.close()
	print("Calibration: ", output, " (", errors.size(), " errors)")
	for problem in errors:
		push_error(problem)
	quit(0 if errors.is_empty() else 1)


func _reset_pair(slot: int) -> void:
	if is_instance_valid(actor):
		actor.free()
		probe.free()
	actor = Fighter.new()
	probe = Fighter.new()
	for body: Fighter in [actor, probe]:
		body.weapon = slot
		body.position = Vector3(0, 0.01, 0)
		arena.add_child(body)
	for _tick in tick_hz:
		await physics_frame
		actor.step({}, dt)
		probe.step({}, dt)
		if actor.grounded and probe.grounded:
			return
	errors.append("Failed to settle on the calibration floor: " + WEAPONS[slot])


func _measure_weapon(slot: int) -> Dictionary:
	await _reset_pair(slot)
	await physics_frame
	var first_shot := actor.step({"fire": true, "fire_pressed": true}, dt)
	var reference := actor.last_fire
	if first_shot.is_empty() or reference != 0.0:
		errors.append("Stationary baseline shot failed: " + WEAPONS[slot])
	_record("stationary_baseline", "shot", 0, actor.position.x, reference)
	var motion := {}
	for kind in ["release", "counter", "counter_gap", "counter_long_gap"]:
		await _reset_pair(slot)
		var start := await _accelerate(kind)
		if kind == "release":
			motion["acceleration"] = start
		motion[kind] = await _change_input(kind, reference)
	var recovery := {}
	for count in [1, BURST_LENGTH]:
		await _reset_pair(slot)
		var trial := await _fire_and_recover(count, reference)
		recovery["single" if count == 1 else "burst"] = trial
	var boundaries := await _check_boundaries(slot)
	return {"reference_first_shot_deg": reference, "movement": motion, "firing": recovery,
			"boundary_shots": boundaries}


func _mark(tick: int, start_x: float) -> Dictionary:
	return {"tick": tick, "time_ms": tick * dt * 1000, "distance_u": (actor.position.x - start_x) / Fighter.UNIT,
			"vx_u_per_s": actor.velocity.x / Fighter.UNIT}


func _record(kind: String, phase: String, tick: int, start_x: float, actual: Variant = null,
		potential: Variant = null) -> void:
	csv.store_csv_line([WEAPONS[actor.weapon], kind, phase, str(tick), str(tick * dt * 1000),
			str((actor.position.x - start_x) / Fighter.UNIT), str(actor.velocity.x / Fighter.UNIT),
			str(actor.grounded), str(actor.spread_degrees()), "" if actual == null else str(actual),
			"" if potential == null else str(potential), str(actor.recoil.x), str(actor.recoil.y),
			str(actor.rounds[actor.weapon]), str(actor.fire_inaccuracy),
			"" if potential == null else str(probe_ray_error_deg)])


func _sample_tick(command: Dictionary) -> Variant:
	probe.restore(actor.state())
	var trigger := command.duplicate()
	trigger["fire"] = true
	trigger["fire_pressed"] = true
	actor.step(command, dt)
	var shot := probe.step(trigger, dt)
	if shot.is_empty():
		return null
	probe_ray_error_deg = _ray_error_degrees(shot)
	if probe_ray_error_deg > probe.last_fire + ANGLE_EPS_DEG:
		errors.append("Shot ray exceeds its reported cone: %s / %g deg vs %g deg" %
				[WEAPONS[actor.weapon], probe_ray_error_deg, probe.last_fire])
	return probe.last_fire


func _ray_error_degrees(shot: Dictionary) -> float:
	# The non-firing twin has exactly the recoil used for this shot, before the new kick.
	var aimed := Fighter.look_direction(actor.yaw + deg_to_rad(actor.recoil.x),
			actor.pitch + deg_to_rad(actor.recoil.y))
	return rad_to_deg(aimed.angle_to(shot.direction))


func _accelerate(kind: String) -> Dictionary:
	var start_x := actor.position.x
	var goal: float = Fighter.RUN_SPEED[actor.weapon]
	var result := {"target_speed_u_per_s": goal}
	var command := {"move": Vector2.RIGHT}
	_record(kind, "accelerate_d", 0, start_x)
	for tick in range(1, 10 * tick_hz + 1):
		await physics_frame
		var potential: Variant = _sample_tick(command)
		_record(kind, "accelerate_d", tick, start_x, null, potential)
		for pct in [50, 90, 100]:
			var key := "to_%d_pct" % pct
			if not result.has(key) and actor.velocity.x / Fighter.UNIT + SPEED_EPS_U >= goal * pct / 100:
				result[key] = _mark(tick, start_x)
		if result.has("to_100_pct"):
			return result
	errors.append("Failed to reach configured ground speed: %s/%s" % [WEAPONS[actor.weapon], kind])
	return result


func _change_input(kind: String, reference: float) -> Dictionary:
	var neutral := {"move": Vector2.ZERO}
	var opposite := {"move": Vector2.LEFT}
	var phase := "release_d" if kind == "release" else "reverse_d_to_a"
	var start_x := actor.position.x
	var gap_ticks := 1 if kind == "counter_gap" else 0
	if kind == "counter_long_gap":
		gap_ticks = 8
	var limit_u: float = Fighter.RUN_SPEED[actor.weapon] * ACCURATE_RUN_FRACTION
	var result := {"initial_speed_u_per_s": actor.velocity.x / Fighter.UNIT, "input_gap_ms": gap_ticks * dt * 1000}
	var peak := _mark(0, start_x)
	var prev := _mark(0, start_x)
	_record(kind, phase, 0, start_x)
	for tick in range(1, 10 * tick_hz + 1):
		await physics_frame
		var command := neutral if kind == "release" or tick <= gap_ticks else opposite
		var potential: Variant = _sample_tick(command)
		_record(kind, phase, tick, start_x, null, potential)
		var sample := _mark(tick, start_x)
		if sample.distance_u > peak.distance_u:
			peak = sample
		var inside := absf(sample.vx_u_per_s) <= limit_u
		if potential == null or (float(potential) == 0.0) != inside:
			errors.append("Shot cone crossed the speed boundary on the wrong tick: %s/%s/%d" %
					[WEAPONS[actor.weapon], kind, tick])
		if not result.has("first_within_reference_speed") and inside:
			result["first_within_reference_speed"] = sample
		if not result.has("first_full_accuracy") and potential != null and absf(float(potential) - reference) <= ANGLE_EPS_DEG:
			result["first_full_accuracy"] = sample
		if kind == "release" and not result.has("stopped") and absf(sample.vx_u_per_s) <= SPEED_EPS_U:
			result["stopped"] = sample
		if kind != "release" and not result.has("first_nonpositive_vx") and sample.vx_u_per_s <= 0.0:
			result["first_nonpositive_vx"] = sample
			result["last_positive_vx"] = prev
		if sample.vx_u_per_s < -limit_u and not result.has("first_reverse_moving_spread"):
			result["first_reverse_moving_spread"] = sample
		if result.has("stopped") or result.has("first_reverse_moving_spread"):
			# 128 Hz flat-ground baseline, measured before changing the shot cone.
			var expected_tick: int = {"release": 26, "counter": 10, "counter_gap": 10, "counter_long_gap": 14}[kind]
			if tick_hz == 128 and result.get("first_full_accuracy", {}).get("tick", -1) != expected_tick:
				errors.append("Unexpected time to first zero-spread shot: %s/%s" % [WEAPONS[actor.weapon], kind])
			result["peak_forward_displacement"] = peak
			return result
		prev = sample
	errors.append("Failed to finish motion trial: %s/%s" % [WEAPONS[actor.weapon], kind])
	return result


func _fire_and_recover(count: int, reference: float) -> Dictionary:
	var kind := "single" if count == 1 else "burst"
	var shots: Array[Dictionary] = []
	var start_x := actor.position.x
	for tick in range(10 * tick_hz):
		await physics_frame
		var command := {"fire": true, "fire_pressed": tick == 0 or actor.weapon == 0}
		var shot := actor.step(command, dt)
		var actual: Variant = null
		if not shot.is_empty():
			actual = actor.last_fire
			if actor.last_fire != 0.0:
				errors.append("Stationary shot has random spread: %s/%s" % [WEAPONS[actor.weapon], kind])
			shots.append({"number": shots.size() + 1, "tick": tick, "time_ms": tick * dt * 1000,
					"actual_shot_cone_deg": actual})
		_record(kind, "fire", tick, start_x, actual)
		if shots.size() == count:
			break
	var result := {"shots": shots}
	if shots.size() != count:
		errors.append("Failed to fire requested shots: %s/%s" % [WEAPONS[actor.weapon], kind])
		return result
	_record(kind, "recover", 0, start_x, shots.back().actual_shot_cone_deg)
	for tick in range(1, 10 * tick_hz + 1):
		await physics_frame
		var potential: Variant = _sample_tick({})
		_record(kind, "recover", tick, start_x, null, potential)
		if potential != null and not result.has("first_legal_shot"):
			result["first_legal_shot"] = {"tick": tick, "time_ms": tick * dt * 1000,
					"actual_shot_cone_deg": potential}
		var recovery_margin := float(Fighter.SHOT_PENALTY[actor.weapon]) * Fighter.FIRE_RECOVERY_FRACTION
		if not result.has("shot_recovery_90") and actor.fire_inaccuracy <= recovery_margin:
			result["shot_recovery_90"] = {"tick": tick, "time_ms": tick * dt * 1000,
					"residual_fire_inaccuracy_deg": actor.fire_inaccuracy}
		if potential != null and not result.has("first_full_accuracy") and absf(float(potential) - reference) <= ANGLE_EPS_DEG:
			result["first_full_accuracy"] = {"tick": tick, "time_ms": tick * dt * 1000,
					"actual_shot_cone_deg": potential}
		if actor.recoil.length() <= ANGLE_EPS_DEG and not result.has("recoil_centered"):
			result["recoil_centered"] = {"tick": tick, "time_ms": tick * dt * 1000}
		if result.has("first_full_accuracy") and result.has("recoil_centered") and result.has("shot_recovery_90"):
			return result
	errors.append("Failed to recover stationary first-shot accuracy: %s/%s" % [WEAPONS[actor.weapon], kind])
	return result


func _check_boundaries(slot: int) -> Dictionary:
	await _reset_pair(slot)
	var start := actor.state()
	# Record a real burst just before its next legal shot. This includes the AK's
	# angular velocity and timing, which its rendered recoil alone cannot reconstruct.
	var burst := {}
	if slot == Fighter.RIFLE:
		for tick in 128:
			await physics_frame
			actor.step({"fire": actor.shots < BURST_LENGTH}, dt)
			if actor.shots == BURST_LENGTH and actor.cooldown <= dt:
				burst = actor.state()
				break
		if burst.is_empty():
			errors.append("Could not prepare a rifle burst for the accuracy boundary")
	var limit_u: float = Fighter.RUN_SPEED[slot] * ACCURATE_RUN_FRACTION
	var samples := {}
	for delta_u: float in [-0.001, 0.0, 0.001]:
		actor.restore(start)
		# Check the scalar equality exactly, then shoot through the full movement step using this speed.
		actor.accuracy_speed = (limit_u + delta_u) * Fighter.UNIT
		actor.fire_inaccuracy = 1.2
		if (actor.spread_degrees() == 0.0) != (delta_u <= 0.0):
			errors.append("Incorrect exact boundary at %s / %+.3f u/s" % [WEAPONS[slot], delta_u])
		# Start 1 u/s high so this partial input reaches its speed cap after friction.
		actor.velocity.x = actor.accuracy_speed + Fighter.UNIT
		var input_fraction: float = (limit_u + delta_u) / Fighter.RUN_SPEED[slot]
		var key := "edge_%+.3f_u_s" % delta_u
		await physics_frame
		samples[key] = _boundary_shot({"move": Vector2.RIGHT * input_fraction}, true, delta_u <= 0.0, key, burst)
		if absf(actor.accuracy_speed / Fighter.UNIT - limit_u - delta_u) > 0.00002:
			errors.append("Shot missed the requested boundary speed: %s/%s" % [WEAPONS[slot], key])
	for axis: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2(1, -1).normalized()]:
		actor.restore(start)
		var crouch := {"move": axis, "crouch": true}
		for _tick in 60:
			await physics_frame
			actor.step(crouch, dt)
		var key := "crouch_" + str(axis)
		await physics_frame
		samples[key] = _boundary_shot(crouch, true, true, key, burst)
		if absf(actor.accuracy_speed / Fighter.UNIT - limit_u) > SPEED_EPS_U:
			errors.append("Crouch did not reach the accuracy boundary: %s/%s" % [WEAPONS[slot], key])
	actor.restore(start)
	await physics_frame
	samples["jump_at_rest"] = _boundary_shot({"jump": true}, false, false, "jump_at_rest", burst)
	for tick in range(1, 2 * tick_hz + 1):
		await physics_frame
		var cone: Variant = _sample_tick({})
		if cone == null or (float(cone) == 0.0) != actor.grounded:
			errors.append("Vertical jump accuracy did not coincide with ground contact: %s/%d" % [WEAPONS[slot], tick])
		if actor.grounded:
			samples["landing_at_rest"] = {"tick_after_takeoff": tick, "cone_deg": cone,
					"ray_error_from_recoiled_aim_deg": probe_ray_error_deg}
			break
	if not samples.has("landing_at_rest"):
		errors.append("Failed to land the vertical jump: " + WEAPONS[slot])
	return samples


func _boundary_shot(command: Dictionary, on_floor: bool, precise: bool, scenario: String, burst: Dictionary) -> Dictionary:
	if not burst.is_empty():
		var firing_state := burst.duplicate()
		var pose := actor.state()
		for field in ["position", "velocity", "grounded", "stance"]:
			firing_state[field] = pose[field]
		actor.restore(firing_state)
	else:
		# A pistol's kick normally centers before its next legal shot. Inject a
		# still-offset pistol aim to keep the angular test sensitive to that case.
		actor.shots = 5
		actor.streak = 3
		actor.recoil = Vector2(0.8, 2.4)
		actor.fire_inaccuracy = 1.2
		actor.accuracy_recovery_shots = 3
	actor.yaw = 0.0
	actor.pitch = -0.11
	var cone: Variant = _sample_tick(command)
	if actor.recoil.length() <= 0.1 or actor.fire_inaccuracy <= 0.0:
		errors.append("Boundary shot lacked prior recoil or firing inaccuracy: %s/%s" % [WEAPONS[actor.weapon], scenario])
	if cone == null or actor.grounded != on_floor or (float(cone) == 0.0) != precise or (probe_ray_error_deg <= ANGLE_EPS_DEG) != precise:
		errors.append("Incorrect shot cone or ray: %s/%s" % [WEAPONS[actor.weapon], scenario])
	return {"grounded": actor.grounded, "speed_u_per_s": actor.accuracy_speed / Fighter.UNIT,
			"cone_deg": cone, "recoil_offset_deg": actor.recoil.length(), "ray_error_from_recoiled_aim_deg": probe_ray_error_deg}
