extends SceneTree
## godot --headless --fixed-fps 128 --path . --script res://recoil_check.gd -- --trace=<csv>

const GameScene := preload("res://main.tscn")
const Fighter = preload("res://fighter.gd")
const DT := 1.0 / 128.0
const TEST_ORIGIN := Vector3(160, 0, 160)
const MAGAZINE := 30
const RAY_TOLERANCE_DEG := 0.0001
# Independent CS2 match build 14141, demo ticks 66363–66549. FireBullets aim_punch
# converted to yaw-left, pitch-up in degrees. This full burst is held out of calibration.
const CS2_BURST := [
	Vector2(0.000000, 0.000000), Vector2(-0.108520, 0.209981), Vector2(0.001450, 1.300936),
	Vector2(-0.146076, 2.911121), Vector2(-0.196873, 4.674560), Vector2(0.463034, 6.309804),
	Vector2(0.898777, 7.790852), Vector2(1.613074, 8.891864), Vector2(0.795024, 9.738511),
	Vector2(-1.513490, 9.533243), Vector2(-2.725745, 9.746260), Vector2(-2.081632, 10.279884),
	Vector2(-2.854982, 10.372564), Vector2(-4.220279, 10.029684), Vector2(-4.457777, 10.234138),
	Vector2(-2.466158, 10.459539), Vector2(-1.278346, 10.790309), Vector2(-0.470336, 11.116988),
	Vector2(0.915790, 11.147639), Vector2(2.772229, 10.673214), Vector2(1.784046, 10.691199),
	Vector2(1.993584, 10.806750), Vector2(1.611785, 11.095638), Vector2(1.169371, 11.372860),
	Vector2(2.153736, 11.215612), Vector2(2.500630, 11.278395), Vector2(1.453457, 11.399996),
	Vector2(-0.364155, 11.239202), Vector2(-2.735658, 10.377712), Vector2(-3.646003, 10.288842),
]

var game: Node3D
var player: Fighter
var twin: Fighter
var resting: Dictionary
var errors: Array[String] = []
var pattern: Array[Vector2] = []
var trace: FileAccess


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--trace="):
			trace = FileAccess.open(argument.trim_prefix("--trace="), FileAccess.WRITE)
			if trace == null:
				push_error("Cannot create recoil trace")
				quit(1)
				return
			trace.store_csv_line(["shot", "tick", "time_ms", "yaw_left_deg", "pitch_up_deg",
					"wall_right_m", "wall_up_m", "spread_deg"])
	game = GameScene.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	game.set_process(false)
	_add_box(TEST_ORIGIN + Vector3(0, -0.5, 0), Vector3(60, 1, 60))
	_add_box(TEST_ORIGIN + Vector3(0, 8, -10.5), Vector3(45, 28, 1))
	player = game.local_player
	player.global_position = TEST_ORIGIN + Vector3.UP * 0.01
	twin = Fighter.new()
	game.add_child(twin)
	twin.global_position = player.global_position
	# A reconciliation clone must not intercept the authority's bullet ray.
	twin.collision_layer = 0
	for tick in 12:
		await physics_frame
		player.step({}, DT)
		twin.step({}, DT)
	_expect(player.grounded and twin.grounded, "Test setup must begin on the floor")
	resting = player.state()
	await _full_magazine()
	if pattern.size() == MAGAZINE:
		await _compensated_magazine()
		await _crouch_spray()
		await _pause_and_resume()
		await _spaced_taps()
		await _interrupted_bursts()
		await _reload_and_reset()
	if trace != null:
		trace.close()
	for problem in errors:
		push_error(problem)
	print("RECOIL_CHECK shots=%d errors=%d" % [pattern.size(), errors.size()])
	quit(0 if errors.is_empty() else 1)


func _add_box(center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	game.add_child(body)
	body.global_position = center


func _angles(direction: Vector3) -> Vector2:
	return Vector2(rad_to_deg(atan2(-direction.x, -direction.z)),
			rad_to_deg(atan2(direction.y, Vector2(direction.x, direction.z).length())))


func _full_magazine() -> void:
	var restored := false
	var max_replay_error := 0.0
	var max_reference_error := 0.0
	var max_wall_error := 0.0
	var worst_shot := 0
	var last_shot_tick := -1
	for tick in 420:
		await physics_frame
		var command := {"fire": true, "yaw": 0.0, "pitch": 0.0}
		if tick == 100:
			# The late-joining prediction starts between shots, from the wire-format state.
			twin.restore(bytes_to_var(var_to_bytes(player.state())))
			restored = true
		var shot := player.step(command, DT)
		if restored:
			var replay := twin.step(command, DT)
			_expect(replay.is_empty() == shot.is_empty(), "Snapshot replay changed shot time on tick %d" % tick)
			if not replay.is_empty() and not shot.is_empty():
				var direction: Vector3 = shot.direction
				max_replay_error = maxf(max_replay_error, rad_to_deg(direction.angle_to(replay.direction)))
		if shot.is_empty():
			continue
		var index := pattern.size()
		_expect(index < MAGAZINE, "Trigger fired after the AK magazine emptied")
		_expect(absf(tick * DT - index * 0.1) < DT, "Full-auto firing time at shot %d" % (index + 1))
		_expect(player.last_fire == 0.0, "Standing full-auto burst has random spread")
		var angle := _angles(shot.direction)
		pattern.append(angle)
		if index < CS2_BURST.size():
			var error := angle.distance_to(CS2_BURST[index])
			if error > max_reference_error:
				max_reference_error = error
				worst_shot = index + 1
		var impact: Dictionary = game._cast(shot, player)
		var displacement: Vector3 = impact.end - shot.origin
		_expect(absf(displacement.z + 10.0) < 0.001, "Shot %d missed the test wall" % (index + 1))
		if index < CS2_BURST.size():
			var expected: Vector2 = CS2_BURST[index]
			var yaw_rad := deg_to_rad(expected.x)
			var expected_mark := 10.0 * Vector2(-tan(yaw_rad), tan(deg_to_rad(expected.y)) / cos(yaw_rad))
			max_wall_error = maxf(max_wall_error, expected_mark.distance_to(Vector2(displacement.x, displacement.y)))
		if trace != null:
			trace.store_csv_line([str(index + 1), str(tick), str(tick * DT * 1000.0),
					str(angle.x), str(angle.y), str(displacement.x), str(displacement.y), str(player.last_fire)])
		last_shot_tick = tick
	_expect(pattern.size() == MAGAZINE and player.rounds[Fighter.RIFLE] == 0, "Incomplete standing AK magazine")
	_expect(not pattern.is_empty() and pattern[0].length() <= RAY_TOLERANCE_DEG, "AK first shot must follow aim")
	_expect(max_replay_error < RAY_TOLERANCE_DEG, "Replayed burst diverged from authority")
	_expect(max_reference_error < 0.001, "CS2 burst mismatch at shot %d (%.6f deg)" % [worst_shot, max_reference_error])
	_expect(max_wall_error < 0.0002, "AK impact on 10 m wall diverged by %.6f m" % max_wall_error)
	print("AK_SPRAY last_tick=%d reference_max_deg=%.8f worst_shot=%d wall_max_m=%.8f replay_max_deg=%.8f" %
			[last_shot_tick, max_reference_error, worst_shot, max_wall_error, max_replay_error])


func _compensated_magazine() -> void:
	# Counter the measured free-spray angles by moving the two input axes on a different view bearing.
	player.restore(resting)
	var desired := Vector2(deg_to_rad(16.0), deg_to_rad(-4.0))
	var target := Fighter.look_direction(desired.x, desired.y)
	var index := 0
	var max_error := 0.0
	for tick in 420:
		await physics_frame
		var offset := pattern[index]
		var shot := player.step({"fire": true, "yaw": desired.x - deg_to_rad(offset.x),
				"pitch": desired.y - deg_to_rad(offset.y)}, DT)
		if not shot.is_empty():
			max_error = maxf(max_error, rad_to_deg(target.angle_to(shot.direction)))
			index += 1
			if index == MAGAZINE:
				break
	_expect(index == MAGAZINE and max_error < RAY_TOLERANCE_DEG, "Compensated magazine missed the aim point")
	print("AK_COMPENSATION max_deg=%.8f" % max_error)


func _pause_and_resume() -> void:
	player.restore(resting)
	for tick in 145:
		await physics_frame
		player.step({"fire": true}, DT)
	# Tap again shortly after a burst, then allow the entire recoil to recover.
	for tick in 15:
		await physics_frame
		player.step({}, DT)
	await physics_frame
	var continuation := player.step({"fire": true}, DT)
	_expect(not continuation.is_empty(), "AK did not fire after releasing its trigger")
	if not continuation.is_empty():
		_expect(_angles(continuation.direction).length() > 0.01, "A short release erased the AK recoil")
	for tick in 384:
		await physics_frame
		player.step({}, DT)
	await _check_opening_burst("Recovered")


func _crouch_spray() -> void:
	player.restore(resting)
	var command := {"move": Vector2.RIGHT, "crouch": true}
	for tick in 64:
		await physics_frame
		player.step(command, DT)
	var speed := player.accuracy_speed / Fighter.UNIT
	_expect(absf(speed - 73.1) < 0.001 and player.grounded, "Crouch spray did not start on its accuracy boundary")
	command["fire"] = true
	var count := 0
	var max_error := 0.0
	for tick in 420:
		await physics_frame
		var shot := player.step(command, DT)
		if not shot.is_empty():
			_expect(player.last_fire == 0.0, "Crouch speed introduced random spread")
			max_error = maxf(max_error, _angles(shot.direction).distance_to(pattern[count]))
			count += 1
			if count == MAGAZINE:
				break
	_expect(count == MAGAZINE and max_error < RAY_TOLERANCE_DEG, "Crouch spray diverged from standing AK pattern")
	print("AK_CROUCH speed_u_s=%.4f pattern_max_deg=%.8f" % [speed, max_error])


func _reload_and_reset() -> void:
	player.restore(resting)
	for tick in 145:
		await physics_frame
		player.step({"fire": true}, DT)
	await physics_frame
	player.step({"reload": true}, DT)
	_expect(player.reloading > 0.0, "AK did not start reloading")
	for tick in 384:
		await physics_frame
		_expect(player.step({}, DT).is_empty(), "AK fired while reloading")
		if player.reloading == 0.0:
			break
	_expect(player.reloading == 0.0 and player.rounds[Fighter.RIFLE] == MAGAZINE, "AK did not refill after reloading")
	await _check_opening_burst("Reloaded")
	for tick in 145:
		await physics_frame
		player.step({"fire": true}, DT)
	player.reset_equipment()
	await _check_opening_burst("Equipment reset")


func _spaced_taps() -> void:
	# Offline CS2 build 14199, level fixed aim. Actual input gaps in the demo were
	# 185.807, 243.488, 314.729 and 471.024 ms. Replay the nearest 128 Hz step.
	var ticks := [24, 31, 40, 60]
	var expected := [Vector2(-0.076317, 0.147671), Vector2(-0.058731, 0.113638),
			Vector2(-0.042511, 0.082256), Vector2.ZERO]
	var max_error := 0.0
	for i in ticks.size():
		player.restore(resting)
		await physics_frame
		player.step({"fire": true}, DT)
		for tick in range(1, ticks[i]):
			await physics_frame
			player.step({}, DT)
		await physics_frame
		var shot := player.step({"fire": true}, DT)
		_expect(not shot.is_empty(), "Missing second tap after %d ticks" % ticks[i])
		if not shot.is_empty():
			max_error = maxf(max_error, _angles(shot.direction).distance_to(expected[i]))
	_expect(max_error < 0.01, "Second-tap recoil differed from stationary CS2 replay by %.5f degrees" % max_error)
	print("AK_TAPS reference_max_deg=%.8f" % max_error)


func _check_opening_burst(reason: String) -> void:
	var index := 0
	for tick in 60:
		await physics_frame
		var shot := player.step({"fire": true}, DT)
		if not shot.is_empty():
			_expect(_angles(shot.direction).distance_to(pattern[index]) < RAY_TOLERANCE_DEG,
					"%s AK did not restart at shot %d" % [reason, index + 1])
			index += 1
			if index == 3:
				break
	_expect(index == 3, "%s AK failed to fire" % reason)


func _interrupted_bursts() -> void:
	# FireBullets after a 316.649 ms gap (14141 tick 68543) and a 408.396 ms
	# gap (14161 tick 117331). The latter burst has only two rounds left.
	var trials := [
		{"prior": 7, "resume_tick": 117, "angles": [Vector2(0.683394, 3.372207),
				Vector2(0.180076, 3.294814), Vector2(0.032897, 4.511333), Vector2(0.632531, 6.039118)]},
		{"prior": 28, "resume_tick": 398, "angles": [Vector2(-0.538949, 1.403374),
				Vector2(-0.682797, 2.511958)]},
	]
	for trial: Dictionary in trials:
		player.restore(resting)
		var count := 0
		var max_error := 0.0
		for tick in range(int(trial.resume_tick) + 60):
			await physics_frame
			var shot := player.step({"fire": count < trial.prior or tick >= trial.resume_tick}, DT)
			if shot.is_empty():
				continue
			if count >= trial.prior:
				var n: int = count - trial.prior
				_expect(absf((tick - trial.resume_tick) * DT - n * 0.1) < DT, "Interrupted AK burst cadence")
				max_error = maxf(max_error, _angles(shot.direction).distance_to(trial.angles[n]))
			count += 1
			if count == trial.prior + trial.angles.size():
				break
		_expect(count == trial.prior + trial.angles.size(), "Interrupted burst did not finish")
		_expect(max_error < 0.10, "Interrupted burst after %d shots diverged %.5f degrees" % [trial.prior, max_error])
		print("AK_RESUMED prior=%d compared=%d reference_max_deg=%.8f" %
				[trial.prior, trial.angles.size(), max_error])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
