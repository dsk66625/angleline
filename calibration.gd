extends SceneTree
## godot --headless --fixed-fps 128 --path . --script res://calibration.gd -- --out=<directory>
## Reports timing at physics-tick boundaries. This script is independent of the play scene.

const Fighter = preload("res://fighter.gd")
const SPEED_EPS_U := 0.001
const ANGLE_EPS_DEG := 0.00001
const BURST_LENGTH := 5
const WEAPONS := ["pistol", "rifle"]

var arena := Node3D.new()
var actor: Fighter
var probe: Fighter
var dt: float
var tick_hz: int
var csv: FileAccess
var errors: Array[String] = []


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
			"probe_next_shot_cone_deg", "recoil_yaw_deg", "recoil_pitch_deg", "rounds_left", "residual_fire_inaccuracy_deg"])
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
			"environment": "Flat floor, grounded standing, yaw=0. D is positive X. No walk, crouch or jump.",
			"ticks": "Rows are end-of-tick. Tick 0 is immediately before the input change, or immediately after the last shot in recovery trials.",
			"units": "Signed X displacement uses game units (u). Engine positions use meters.",
			"probe": "An independent character restores the pre-tick state and requests a real shot with the same movement input. Blank probe cone means firing was unavailable or untested.",
			"full_accuracy": "A legal shot has the same recorded cone as a stationary first shot within angle_epsilon_deg. Reticle spread and recoil are separate columns.",
			"shot_recovery_90": "First sample with residual firing inaccuracy at or below 10% of one shot's penalty. This residual only affects the cone while moving or airborne.",
			"counter": "First vx <= 0 ends the sampled reversal. A null first_full_accuracy means no zero-spread shot was sampled before that boundary.",
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
	for kind in ["release", "counter", "counter_gap"]:
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
	return {"reference_first_shot_deg": reference, "movement": motion, "firing": recovery}


func _mark(tick: int, start_x: float) -> Dictionary:
	return {"tick": tick, "time_ms": tick * dt * 1000, "distance_u": (actor.position.x - start_x) / Fighter.UNIT,
			"vx_u_per_s": actor.velocity.x / Fighter.UNIT}


func _record(kind: String, phase: String, tick: int, start_x: float, actual: Variant = null,
		potential: Variant = null) -> void:
	csv.store_csv_line([WEAPONS[actor.weapon], kind, phase, str(tick), str(tick * dt * 1000),
			str((actor.position.x - start_x) / Fighter.UNIT), str(actor.velocity.x / Fighter.UNIT),
			str(actor.grounded), str(actor.spread_degrees()), "" if actual == null else str(actual),
			"" if potential == null else str(potential), str(actor.recoil.x), str(actor.recoil.y),
			str(actor.rounds[actor.weapon]), str(actor.fire_inaccuracy)])


func _probe(command: Dictionary) -> Variant:
	probe.restore(actor.state())
	var trigger := command.duplicate()
	trigger["fire"] = true
	trigger["fire_pressed"] = true
	if probe.step(trigger, dt).is_empty():
		return null
	return probe.last_fire


func _accelerate(kind: String) -> Dictionary:
	var start_x := actor.position.x
	var goal: float = Fighter.RUN_SPEED[actor.weapon]
	var result := {"target_speed_u_per_s": goal}
	var command := {"move": Vector2.RIGHT}
	_record(kind, "accelerate_d", 0, start_x)
	for tick in range(1, 10 * tick_hz + 1):
		await physics_frame
		var potential: Variant = _probe(command)
		actor.step(command, dt)
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
	var result := {"initial_speed_u_per_s": actor.velocity.x / Fighter.UNIT, "input_gap_ms": gap_ticks * dt * 1000}
	var peak := _mark(0, start_x)
	var prev := _mark(0, start_x)
	_record(kind, phase, 0, start_x)
	for tick in range(1, 10 * tick_hz + 1):
		await physics_frame
		var command := neutral if kind == "release" or tick <= gap_ticks else opposite
		var potential: Variant = _probe(command)
		actor.step(command, dt)
		_record(kind, phase, tick, start_x, null, potential)
		var sample := _mark(tick, start_x)
		if sample.distance_u > peak.distance_u:
			peak = sample
		if not result.has("first_within_reference_speed") and absf(sample.vx_u_per_s) <= Fighter.RUN_SPEED[actor.weapon] * Fighter.ACCURATE_SPEED_RATIO:
			result["first_within_reference_speed"] = sample
		if not result.has("first_full_accuracy") and potential != null and absf(float(potential) - reference) <= ANGLE_EPS_DEG:
			result["first_full_accuracy"] = sample
		if kind == "release" and not result.has("stopped") and absf(sample.vx_u_per_s) <= SPEED_EPS_U:
			result["stopped"] = sample
		if kind != "release" and not result.has("first_nonpositive_vx") and sample.vx_u_per_s <= 0.0:
			result["first_nonpositive_vx"] = sample
			result["last_positive_vx"] = prev
		if result.has("stopped") or result.has("first_nonpositive_vx"):
			if not result.has("first_full_accuracy"):
				result["first_full_accuracy"] = null
				if kind == "release":
					errors.append("Stopped shot did not regain zero spread: " + WEAPONS[actor.weapon])
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
		var potential: Variant = _probe({})
		actor.step({}, dt)
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
