extends SceneTree
## godot --headless --path . --script res://vm_land.gd
## Regression: the viewmodel must not snap on the landing frame. Drops the
## player from height and prints the largest per-tick weapon Y delta after
## touchdown; a hard airborne switch would show a ~0.02 m single-frame jump.

const Game = preload("res://main.gd")
const PLAY_SCENE = preload("res://main.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game: Game = PLAY_SCENE.instantiate()
	root.add_child(game)
	game._resume(false)
	game._smoke = "--qa-land"
	var player: TrialFighter = game.local_player
	player.global_position = Vector3(0, 1.2, 6)
	await _ticks(20)
	var landed := false
	var prev_y: float = game._viewmodel.weapons[player.weapon].position.y
	var max_delta := 0.0
	var samples := 0
	for i in 240:
		await physics_frame
		var y: float = game._viewmodel.weapons[player.weapon].position.y
		if player.grounded:
			landed = true
		if landed and samples < 40:
			max_delta = maxf(max_delta, absf(y - prev_y))
			samples += 1
		prev_y = y
	print("VM_LAND landed=", landed, " max_per_tick_dy=", snappedf(max_delta, 0.00001))
	quit(0 if landed and max_delta < 0.004 else 1)


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame
