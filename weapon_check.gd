extends SceneTree
## godot --headless --fixed-fps 128 --path . --script res://weapon_check.gd

const Game = preload("res://main.gd")
const PLAY_SCENE = preload("res://main.tscn")
const KEYS := [KEY_1, KEY_2, KEY_3]
const SLOTS := [1, 0, 2]
const NAMES := ["AK-47", "P250", "Knife"]
const SPEEDS := [215.0, 240.0, 250.0]
const STANCES := ["run", "walk", "crouch"]
const SPEED_FACTORS := [1.0, 0.52, 0.34]

var game: Game
var player: TrialFighter
var errors: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	game = PLAY_SCENE.instantiate()
	root.add_child(game)
	game._resume(false)
	player = game.local_player
	for index in KEYS.size():
		_tap_key(KEYS[index])
		await _ticks(2)
		_expect(player.weapon == SLOTS[index], "Number key %d selected weapon %d" % [index + 1, player.weapon])
		for stance in STANCES.size():
			await _measure(index, stance)
	await _counter_shot()
	await _melee()
	for problem in errors:
		push_error(problem)
	print("WEAPON_CHECK errors=", errors.size())
	quit(0 if errors.is_empty() else 1)


func _key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _tap_key(code: Key) -> void:
	_key(code, true)
	_key(code, false)


func _left_click() -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _move_to(location: Vector3) -> void:
	player.global_position = location
	player.velocity = Vector3.ZERO
	player.grounded = false
	game.aim = Vector2.ZERO


func _measure(index: int, stance: int) -> void:
	_move_to(Vector3(-4.0, 0.01, 8.0))
	_key(KEY_SHIFT, stance == 1)
	_key(KEY_CTRL, stance == 2)
	await _ticks(64)
	_expect(player.grounded and is_zero_approx(player.accuracy_speed), "Movement measurement did not start at rest")
	_key(KEY_D, true)
	await _ticks(128)
	var start := player.global_position
	await _ticks(64)
	var seconds := 64.0 / Engine.physics_ticks_per_second
	var traveled := (player.global_position.x - start.x) / TrialFighter.UNIT / seconds
	var speed := player.accuracy_speed / TrialFighter.UNIT
	var expected: float = SPEEDS[index] * SPEED_FACTORS[stance]
	_expect(absf(speed - expected) < 0.02 and absf(traveled - expected) < 0.02,
			"%s %s expected %.2f, velocity %.3f, displacement/time %.3f" % [NAMES[index], STANCES[stance], expected, speed, traveled])
	print("%s %s: velocity %.2f, displacement/time %.2f u/s" % [NAMES[index], STANCES[stance], speed, traveled])
	_key(KEY_D, false)
	_key(KEY_CTRL, false)
	_key(KEY_SHIFT, false)


func _counter_shot() -> void:
	# Face the flat C/01 panel so a centered ray leaves its mark at eye X and Y.
	_move_to(Vector3(-6.3, 0.01, 8.0))
	_tap_key(KEY_1)
	await _ticks(64)
	_key(KEY_D, true)
	await _ticks(128)
	_key(KEY_D, false)
	await _ticks(1)
	_key(KEY_A, true)
	await _ticks(8)
	_expect(player.accuracy_speed / TrialFighter.UNIT > 73.1 and game.hud.rig_label.text.contains("移动散布"),
			"Counter step 9 must still show movement spread")
	var mark_index := game._mark_next
	_left_click()
	await _ticks(1)
	var speed := player.accuracy_speed / TrialFighter.UNIT
	var mark: Node3D = game._marks[mark_index]
	var eye := player.eye_position()
	var error := Vector2(mark.global_position.x - eye.x, mark.global_position.y - eye.y).length()
	_expect(speed > 0.0 and speed <= 73.1 and player.last_fire == 0.0, "Counter step 10 must fire with zero spread")
	_expect(game.hud.rig_label.text.contains("急停就绪") and game.hud.rig_label.text.ends_with("0.0°"),
			"Counter step 10 must display the new accuracy window")
	_expect(mark_index != game._mark_next and error < 0.00001, "Counter shot missed the center on C/01")
	print("COUNTER_HIT tick=10 speed_u_s=%.3f spread_deg=%.3f impact_offset_m=%.7f" % [speed, player.last_fire, error])
	_key(KEY_A, false)


func _melee() -> void:
	# Use the actual practice target and production input, ray cast, and hit feedback.
	var target: Node3D = game.find_child("Plate_01", true, false)
	var center := target.global_position
	_move_to(Vector3(center.x, 0.01, center.z + 3.0))
	_tap_key(KEY_2)
	await _ticks(64)
	_left_click()
	await _ticks(2)
	var original_ammo := player.rounds.duplicate()
	_expect(original_ammo[0] == 12, "Ammo preservation test needs a partly empty pistol")
	_tap_key(KEY_3)
	await _ticks(64)
	var hits := game._number_hits
	var attacks := game._test_fires
	_left_click()
	await _ticks(2)
	_expect(game._test_fires == attacks + 1 and game._number_hits == hits, "Knife must swing and miss the distant target")

	_move_to(Vector3(center.x, 0.01, center.z + 1.1))
	await _ticks(64)
	var tracer := game._tracer_next
	var mark := game._mark_next
	_left_click()
	await _ticks(2)
	_expect(game._number_hits == hits + 1, "Knife missed an unobstructed nearby target")
	_expect(game._tracer_next == tracer and game._mark_next == mark, "Melee hit produced gun effects")
	_left_click()
	await _ticks(2)
	_expect(game._number_hits == hits + 1, "Knife bypassed its attack cooldown")

	var blocker := StaticBody3D.new()
	var obstacle := BoxShape3D.new()
	obstacle.size = Vector3(1.0, 2.0, 0.1)
	var collision := CollisionShape3D.new()
	collision.shape = obstacle
	blocker.add_child(collision)
	blocker.position = center + Vector3(0.0, 0.0, 0.3)
	game.add_child(blocker)
	await _ticks(64)
	_left_click()
	_tap_key(KEY_R)
	await _ticks(2)
	_expect(game._number_hits == hits + 1, "Knife hit a target behind cover")
	_expect(player.reloading == 0.0 and player.rounds == original_ammo, "Knife attacks or reload modified gun ammo")
	_tap_key(KEY_2)
	await _ticks(64)
	_left_click()
	await _ticks(2)
	_expect(player.weapon == 0 and player.rounds[0] == original_ammo[0] - 1, "Pistol did not fire after switching back from knife")


func _expect(passed: bool, message: String) -> void:
	if not passed:
		errors.append(message)
