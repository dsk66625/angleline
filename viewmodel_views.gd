extends SceneTree
## godot --path . --script res://viewmodel_views.gd -- --test-resolution=1920x1080
## Captures the viewmodel action module at fixed phase points: deploy settle,
## inspect mid-keys, reload mag-out / rack, fire kick and knife slash.
## Presentation review only; no gameplay assertions here.

const Game = preload("res://main.gd")
const PLAY_SCENE = preload("res://main.tscn")

var game: Game
var player: TrialFighter


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	game = PLAY_SCENE.instantiate()
	root.add_child(game)
	game._resume()
	game.options["view"] = 0
	game.options["resolution"] = Vector2i(1920, 1080)
	game._apply_options()
	player = game.local_player
	player.global_position = Vector3(0, 0.02, 6)
	game.aim = Vector2(0, -0.06)
	game._eye_prior = player.eye_position()
	await _ticks(40)
	await _shot("rifle-idle")
	game._viewmodel.inspect()
	await _ticks(230)
	await _shot("rifle-inspect")
	player.rounds[TrialFighter.RIFLE] = 10
	game._reload_pressed = true
	await _ticks(70)
	await _shot("rifle-reload-mag")
	await _ticks(120)
	await _shot("rifle-reload-rack")
	await _ticks(120)
	game.requested_weapon = TrialFighter.PISTOL
	await _ticks(40)
	await _shot("pistol-idle")
	game._viewmodel.inspect()
	await _ticks(130)
	await _shot("pistol-inspect")
	game.requested_weapon = TrialFighter.KNIFE
	await _ticks(40)
	await _shot("knife-idle")
	game._viewmodel.inspect()
	await _ticks(110)
	await _shot("knife-inspect")
	await _ticks(260)
	game._fire_pressed = true
	await _ticks(9)
	await _shot("knife-slash")
	await _ticks(60)
	game.requested_weapon = TrialFighter.RIFLE
	await _ticks(40)
	game._fire_pressed = true
	await _ticks(3)
	await _shot("rifle-fire")
	print("VM_VIEWS done")
	quit(0)


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _shot(name_of_view: String) -> void:
	RenderingServer.frame_post_draw.connect(_save.bind(name_of_view), CONNECT_ONE_SHOT)
	await _ticks(2)


func _save(name_of_view: String) -> void:
	var image := root.get_texture().get_image()
	var filename := "vm-%s.png" % name_of_view
	var error := image.save_png("user://" + filename)
	print("VM_VIEW ", ProjectSettings.globalize_path("user://" + filename), " code=", error)