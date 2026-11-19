extends SceneTree
## godot --path . --script res://art_views.gd -- --test-resolution=1920x1080
## Art review captures: teleports the local player to fixed review stands and
## saves one screenshot per stand to user://art-view-<name>.png. Gameplay
## anchors are untouched; this script only moves the camera for review.

const Game = preload("res://main.gd")
const PLAY_SCENE = preload("res://main.tscn")

## name, stand position, yaw, pitch. Yaw 0 looks -Z; -PI/2 looks +X; PI looks +Z.
const VIEWS := [
	["spawn", Vector3(0, 0.02, 6), 0.0, 0.0],
	["jump", Vector3(6.5, 0.02, 4.5), -0.37, -0.12],
	["target1", Vector3(-4.7, 0.02, -5.0), 0.0, -0.05],
	["lane", Vector3(-6.0, 0.02, 2.0), 1.07, -0.10],
	["gantry", Vector3(0, 0.02, -20.5), 0.0, 0.30],
	["rear", Vector3(0, 0.02, 6), PI, -0.05],
]

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
	for view in VIEWS:
		player.global_position = view[1]
		player.velocity = Vector3.ZERO
		player.grounded = false
		game.aim = Vector2(view[2], view[3])
		game._eye_prior = player.eye_position()
		await _ticks(24)
		RenderingServer.frame_post_draw.connect(_save.bind(view[0]), CONNECT_ONE_SHOT)
		await _ticks(2)
	print("ART_VIEWS done")
	quit(0)


func _ticks(count: int) -> void:
	for tick in count:
		await physics_frame


func _save(name_of_view: String) -> void:
	var image := root.get_texture().get_image()
	var filename := "art-view-%s.png" % name_of_view
	var error := image.save_png("user://" + filename)
	print("ART_VIEW ", ProjectSettings.globalize_path("user://" + filename), " code=", error, " size=", image.get_size())