extends SceneTree
## godot --path . --script res://viewmodel_views.gd -- --test-resolution=1920x1080
## Captures the viewmodel action module at fixed phase points: deploy, idle,
## inspect, every reload beat (drop / fetch / seat / rack), fire and knife slash.
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
	game._resume(false)
	game._smoke = "--qa-views"  # QA sentinel: no focus-out pause, no mouse capture
	game.options["view"] = 0
	game.options["resolution"] = Vector2i(1920, 1080)
	game._apply_options()
	player = game.local_player
	player.global_position = Vector3(0, 0.02, 6)
	game.aim = Vector2(0, -0.06)
	game._eye_prior = player.eye_position()
	await _ticks(40)
	await _shot("rifle-idle")
	_stats("rifle")
	game._viewmodel.inspect()
	await _ticks(150)
	await _shot("rifle-inspect")
	await _ticks(260)
	player.rounds[TrialFighter.RIFLE] = 10
	game._reload_pressed = true
	await _ticks(75)
	await _shot("rifle-reload-drop")
	await _ticks(65)
	await _shot("rifle-reload-fetch")
	await _ticks(48)
	await _shot("rifle-reload-seat")
	await _ticks(51)
	await _shot("rifle-reload-rack")
	await _ticks(60)
	game.requested_weapon = TrialFighter.PISTOL
	await _ticks(8)
	await _shot("pistol-deploy")
	await _ticks(40)
	await _shot("pistol-idle")
	_stats("pistol")
	game._viewmodel.inspect()
	await _ticks(170)
	await _shot("pistol-inspect")
	await _ticks(280)
	player.rounds[TrialFighter.PISTOL] = 5
	game._reload_pressed = true
	await _ticks(44)
	await _shot("pistol-reload-drop")
	await _ticks(56)
	await _shot("pistol-reload-fetch")
	await _ticks(40)
	await _shot("pistol-reload-seat")
	await _ticks(40)
	await _shot("pistol-reload-rack")
	await _ticks(40)
	game._fire_pressed = true
	await _ticks(3)
	await _shot("pistol-fire")
	await _ticks(30)
	game.requested_weapon = TrialFighter.KNIFE
	await _ticks(8)
	await _shot("knife-deploy")
	await _ticks(40)
	await _shot("knife-idle")
	_stats("knife")
	game._viewmodel.inspect()
	await _ticks(127)
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


func _stats(label: String) -> void:
	var calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("VM_STATS ", label, " draw_calls=", calls, " primitives=", prims)


func _save(name_of_view: String) -> void:
	var image := root.get_texture().get_image()
	var filename := "vm-%s.png" % name_of_view
	var error := image.save_png("user://" + filename)
	print("VM_VIEW ", ProjectSettings.globalize_path("user://" + filename), " code=", error)
