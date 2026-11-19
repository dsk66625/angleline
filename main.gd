extends Node3D

const Arena = preload("res://world.gd")
const Fighter = preload("res://fighter.gd")
const HUD = preload("res://trial_hud.gd")
const Reticle = preload("res://crosshair.gd")
const Link = preload("res://trial_link.gd")
const Updater = preload("res://game_updater.gd")
const UpdateMenu = preload("res://update_menu.gd")
const SPAWN := [Vector3(0, 0.02, 6), Vector3(3, 0.02, 6)]
const VERTICAL_FOV := 73.739795
const SETTINGS_PATH := "user://angleline.cfg"
const TICK := 1.0 / 128.0

var options := {"sensitivity": 1.0, "axis_x": 1.0, "axis_y": 1.0, "view": 0,
	"resolution": Vector2i.ZERO, "fullscreen": false, "cap": 0, "vsync": false, "volume": 65,
	"crosshair": Reticle.DEFAULTS.duplicate()}
var _last_window_target := Vector2i(-1, -1)
var local_player: TrialFighter
var remote_player: TrialFighter
var camera: Camera3D
var link: TrialLink
var hud: TrialHUD
var updater: Updater
var update_menu: UpdateMenu
var active_play := false
var aim := Vector2.ZERO
var requested_weapon := Fighter.RIFLE
var _jump_pressed := false
var _fire_pressed := false
var _reload_pressed := false
var _eye_prior := Vector3.ZERO
var _proxy_from := Vector3.ZERO
var _proxy_to := Vector3.ZERO
var _proxy_elapsed := 0.0
var _commands: Array[Dictionary] = []
var _remote_queue: Array[Dictionary] = []
var _last_remote: Dictionary = {}
var _ack := -1
var _seq := 0
var _world_tick := 0
var _last_snapshot := -1
var _silence := 0
var _pending_snapshot: Dictionary = {}
var _hit_time := 0.0
var _number_hits := 0
var _performance: Array[float] = []
var _performance_elapsed := 0.0
var _last_info := ""
var _viewmodel: VmRig
var _aim_prior := Vector2.ZERO
var _tracer_pool: Array[MeshInstance3D] = []
var _tracer_timers := PackedFloat32Array()
var _tracer_next := 0
var _marks: Array[MeshInstance3D] = []
var _mark_next := 0
var _sounds: Array[AudioStreamWAV] = []
var _audio: AudioStreamPlayer
var _smoke := ""
var _bench_fps := -1
var _visual_frames := 0
var _visual_view := 0
var _stats_elapsed := 0.0
var _bench_start := 0
var _bench_previous := 0
var _bench_frames: Array[float] = []
var _test_round := 0
var _test_fires := 0
var _test_received := 0
var _test_saw_remote_swing := false
var _test_start := Vector3.ZERO
var _test_peak := 0.0
var _test_stop := 0.0
var _test_reverse := 0.0
var _test_jump := 0.0

func _ready() -> void:
	var viewport_window := get_window()
	viewport_window.min_size = Vector2i(720, 580)
	add_child(Arena.new())
	link = Link.new()
	link.name = "TrialLink"
	add_child(link)
	link.state_changed.connect(_connection_status)
	link.peer_arrived.connect(_arrive)
	link.peer_departed.connect(_depart)
	link.input_received.connect(_enqueue_remote)
	link.snapshot_received.connect(_queue_snapshot)
	link.shot_received.connect(_receive_shot)

	local_player = Fighter.new()
	add_child(local_player)
	_place(local_player, 0)
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = VERTICAL_FOV
	camera.near = 0.035
	camera.far = 112
	add_child(camera)
	camera.current = true
	_build_presentation()
	hud = HUD.new()
	add_child(hud)
	hud.applied.connect(_save_options)
	hud.resumed.connect(_resume)
	hud.host_requested.connect(_host)
	hud.join_requested.connect(_join)
	hud.leave_requested.connect(link.leave)
	hud.reset_requested.connect(_reset_player)
	hud.quit_requested.connect(get_tree().quit)
	updater = Updater.new()
	add_child(updater)
	update_menu = UpdateMenu.new()
	update_menu.updater = updater
	var update_button := hud.mount_update_menu(update_menu, update_menu.open)
	updater.changed.connect(func() -> void:
		update_button.text = "重启可更新" if updater.state == Updater.State.READY else "游戏更新")
	viewport_window.size_changed.connect(_sync_render_size, CONNECT_DEFERRED)
	_load_options()
	_apply_options()
	hud.load_values(options)
	_eye_prior = local_player.eye_position()
	camera.position = _eye_prior
	for argument in OS.get_cmdline_user_args():
		if argument in ["--self-test", "--smoke-host", "--smoke-client", "--visual-test", "--bench-run"]:
			_smoke = argument
		elif argument.begins_with("--test-fps="):
			_bench_fps = int(argument.get_slice("=", 1))
		elif argument.begins_with("--test-view="):
			_visual_view = clampi(int(argument.get_slice("=", 1)), 0, 2)
		elif argument.begins_with("--test-resolution="):
			var parts := argument.get_slice("=", 1).split("x")
			if parts.size() == 2:
				var size := Vector2i(int(parts[0]), int(parts[1]))
				if size in HUD.RESOLUTIONS:
					options["resolution"] = size
		elif argument == "--test-fullscreen":
			options["fullscreen"] = true
		elif argument == "--print-engine-licenses":
			_print_engine_licenses()
			get_tree().quit()
			return
	if _bench_fps > 0:
		Engine.max_fps = _bench_fps
	if _smoke == "--smoke-host":
		_host(29428)
	elif _smoke == "--smoke-client":
		_join("127.0.0.1", 29428)
	elif _smoke == "--visual-test":
		options["view"] = _visual_view
		_apply_options()
		hud.load_values(options)
	elif _smoke == "--bench-run":
		options["view"] = 0
		options["cap"] = 0
		options["vsync"] = false
		_apply_options()
		_resume()
		_bench_start = Time.get_ticks_usec()
		_bench_previous = _bench_start
	if _smoke.is_empty() and DisplayServer.get_name() != "headless":
		updater.start.call_deferred()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and is_instance_valid(hud) and active_play and _smoke.is_empty():
		_pause()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			if not active_play and update_menu.visible:
				update_menu.hide()
				get_viewport().set_input_as_handled()
				return
			if not active_play and hud.dismiss_crosshair_popup():
				get_viewport().set_input_as_handled()
				return
			if active_play:
				_pause()
			else:
				_resume()
			get_viewport().set_input_as_handled()
		elif active_play:
			match event.physical_keycode:
				KEY_1: requested_weapon = Fighter.RIFLE
				KEY_2: requested_weapon = Fighter.PISTOL
				KEY_3: requested_weapon = Fighter.KNIFE
				KEY_SPACE: _jump_pressed = true
				KEY_R: _reload_pressed = true
				KEY_F: _viewmodel.inspect()
				KEY_F2: _reset_player()
	if not active_play:
		return
	if event is InputEventMouseMotion:
		var axis := Vector2(options["axis_x"], options["axis_y"])
		aim += Fighter.turn_delta(event.screen_relative, options["sensitivity"], axis)
		aim.x = wrapf(aim.x, -PI, PI)
		aim.y = clampf(aim.y, deg_to_rad(-89), deg_to_rad(89))
	elif event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: _fire_pressed = true
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN: _jump_pressed = true

func _pause() -> void:
	active_play = false
	_jump_pressed = false
	_fire_pressed = false
	_reload_pressed = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.load_values(options)
	hud.show_menu(true)

func _resume() -> void:
	active_play = true
	hud.show_menu(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _load_options() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		return
	for key in options:
		var default_value: Variant = options[key]
		var loaded: Variant = config.get_value("client", key, default_value)
		if typeof(loaded) == typeof(default_value):
			options[key] = loaded
	for key in ["sensitivity", "axis_x", "axis_y"]:
		if not is_finite(options[key]) or options[key] <= 0.0 or options[key] > 50.0:
			options[key] = 1.0
	options["view"] = clampi(options["view"], 0, 2)
	var size: Vector2i = options["resolution"]
	if size not in HUD.RESOLUTIONS:
		options["resolution"] = Vector2i.ZERO
	elif size != Vector2i.ZERO:
		if HUD.is_four_three(size):
			options["view"] = maxi(1, options["view"])
		else:
			options["view"] = 0
	options["cap"] = clampi(options["cap"], 0, 2000)
	options["volume"] = clampi(options["volume"], 0, 100)
	options["crosshair"] = Reticle.normalize(options["crosshair"])

func _save_options(values: Dictionary) -> void:
	options = values
	_apply_options()
	var config := ConfigFile.new()
	for key in options:
		config.set_value("client", key, options[key])
	if config.save(SETTINGS_PATH) != OK:
		push_warning("Could not save angleline.cfg")

func _apply_options() -> void:
	hud.crosshair.apply_style(options["crosshair"])
	var window := get_window()
	Engine.max_fps = options["cap"]
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if options["vsync"] else DisplayServer.VSYNC_DISABLED)
	Input.use_accumulated_input = false
	var selected: Vector2i = options["resolution"]
	var fullscreen: bool = options["fullscreen"]
	var was_fullscreen := window.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN]
	if DisplayServer.get_name() != "headless":
		if fullscreen != was_fullscreen:
			window.mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED
		if not fullscreen and selected != Vector2i.ZERO and (selected != _last_window_target or was_fullscreen):
			_fit_window(selected)
	_last_window_target = selected
	_sync_render_size()
	_audio.volume_db = linear_to_db(maxf(float(options["volume"]) * 0.01, 0.0001))

func _fit_window(selected: Vector2i) -> void:
	var window := get_window()
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	if not usable.has_area():
		return
	var decorations := (window.get_size_with_decorations() - window.size).max(Vector2i.ZERO)
	var available := (usable.size - decorations).max(Vector2i.ONE)
	var desired := selected
	if HUD.is_four_three(selected):
		desired.x = roundi(float(selected.y) * 16.0 / 9.0)
	var fit := minf(1.0, minf(float(available.x) / desired.x, float(available.y) / desired.y))
	window.size = Vector2i(Vector2(desired) * fit)
	var decorated := window.get_size_with_decorations()
	var client_offset := window.position - window.get_position_with_decorations()
	window.position = usable.position + (usable.size - decorated) / 2 + client_offset

func _sync_render_size() -> void:
	var window := get_window()
	var selected: Vector2i = options["resolution"]
	var render_size := selected
	if render_size == Vector2i.ZERO:
		render_size = window.size
		if options["view"] != 0:
			render_size.x = roundi(float(render_size.y) * 4.0 / 3.0)
	if render_size.x < 1 or render_size.y < 1:
		return
	if selected == Vector2i.ZERO and options["view"] == 0:
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		window.content_scale_size = Vector2i.ZERO
	else:
		window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE if options["view"] == 2 else Window.CONTENT_SCALE_ASPECT_KEEP
		window.content_scale_size = render_size
		window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	hud.fit_render_size(render_size)

func _connection_status(message: String) -> void:
	hud.connection_status(message)
	if _smoke in ["--smoke-host", "--smoke-client"]:
		print("NETWORK_STATUS ", message)

func _host(port: int) -> void:
	var result := link.start_host(port)
	if result != OK:
		hud.connection_status("开房失败（%s）。请先断开现有连接并检查端口。" % error_string(result))

func _join(address: String, port: int) -> void:
	var result := link.join_host(address, port)
	if result != OK:
		hud.connection_status("加入失败（%s）。请检查地址和端口。" % error_string(result))

func _place(fighter: TrialFighter, slot: int) -> void:
	fighter.global_position = SPAWN[slot]
	fighter.velocity = Vector3.ZERO
	fighter.grounded = false
	fighter.reset_physics_interpolation()

func _reset_player() -> void:
	if link.remote_ready:
		hud.connection_status("联机中请在断开后使用复位")
		return
	_place(local_player, 0)
	local_player.reset_equipment()
	aim = Vector2.ZERO
	_eye_prior = local_player.eye_position()
	_number_hits = 0
	for mark in _marks:
		mark.hide()

func _arrive() -> void:
	_clear_network()
	var local_slot := 0 if link.is_host else 1
	_place(local_player, local_slot)
	_eye_prior = local_player.eye_position()
	remote_player = Fighter.new()
	add_child(remote_player)
	_place(remote_player, 1 - local_slot)
	remote_player.show_avatar(Color("#67b4c2") if link.is_host else Color("#c7a765"))
	_proxy_from = remote_player.global_position
	_proxy_to = _proxy_from

func _depart() -> void:
	_clear_network()

func _clear_network() -> void:
	if is_instance_valid(remote_player):
		remote_player.queue_free()
	remote_player = null
	_commands.clear()
	_remote_queue.clear()
	_last_remote.clear()
	_pending_snapshot.clear()
	_ack = -1
	_seq = 0
	_last_snapshot = -1
	_silence = 0

func _enqueue_remote(command: Dictionary) -> void:
	if _remote_queue.size() < 192:
		_remote_queue.append(command)

func _queue_snapshot(snapshot: Dictionary) -> void:
	if not is_instance_valid(remote_player):
		return
	var tick: int = snapshot.get("tick", -1)
	if tick > _last_snapshot:
		_pending_snapshot = snapshot
		_last_snapshot = tick

func _reconcile() -> void:
	var snapshot := _pending_snapshot
	_pending_snapshot = {}
	_proxy_from = remote_player.global_position
	_proxy_to = snapshot["host"]["position"]
	_proxy_elapsed = 0.0
	var proxy_data: Dictionary = snapshot["host"].duplicate()
	proxy_data["position"] = _proxy_from
	remote_player.restore(proxy_data)
	var accepted: int = snapshot["ack"]
	while not _commands.is_empty() and int(_commands[0]["seq"]) <= accepted:
		_commands.pop_front()
	var predicted_before := local_player.global_position
	local_player.restore(snapshot["guest"])
	for command in _commands:
		local_player.step(command, TICK)
	if local_player.global_position.distance_to(predicted_before) > 1.0:
		_eye_prior = local_player.eye_position()

func _read_player() -> Dictionary:
	var d := Vector2.ZERO
	var jump_held := active_play and Input.is_physical_key_pressed(KEY_SPACE)
	if active_play:
		d.x = float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
		d.y = float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W))
	var command := {"seq": _seq, "move": d, "yaw": aim.x, "pitch": aim.y, "weapon": requested_weapon,
		"walk": active_play and Input.is_physical_key_pressed(KEY_SHIFT),
		"crouch": active_play and Input.is_physical_key_pressed(KEY_CTRL),
		"jump": active_play and (_jump_pressed or jump_held), "jump_held": jump_held,
		"reload": active_play and _reload_pressed,
		"fire": active_play and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT),
		"fire_pressed": active_play and _fire_pressed}
	_jump_pressed = false
	_fire_pressed = false
	_reload_pressed = false
	return command

func _physics_process(_dt: float) -> void:
	_world_tick += 1
	if not _pending_snapshot.is_empty() and is_instance_valid(remote_player):
		_reconcile()
	_eye_prior = local_player.eye_position()
	var command := _read_player()
	if _smoke == "--self-test":
		_simulate_test(command)
	elif _smoke in ["--smoke-host", "--smoke-client"]:
		_network_test(command)
	elif _smoke == "--bench-run":
		_benchmark_input(command)
	if link.remote_ready and not link.is_host:
		link.send_input(command)
		_commands.append(command)
		if _commands.size() > 256:
			_commands.pop_front()
		_seq += 1
	var predicted := local_player.step(command, TICK)
	if not predicted.is_empty():
		_test_fires += 1
		_local_shot(predicted)
	if not link.is_host or not link.remote_ready or not is_instance_valid(remote_player):
		return
	var other := _next_remote_command()
	var shot := remote_player.step(other, TICK)
	if not shot.is_empty():
		_test_received += 1
		var impact := _cast(shot, remote_player)
		impact["slot"] = 1
		_feedback(impact, false)
		link.send_shot(impact)
	if _world_tick % 2 == 0:
		link.send_snapshot({"tick": _world_tick, "ack": _ack, "host": local_player.state(),
			"guest": remote_player.state()})

func _next_remote_command() -> Dictionary:
	if not _remote_queue.is_empty():
		_silence = 0
		_last_remote = _remote_queue.pop_front()
		_ack = _last_remote["seq"]
		return _last_remote
	_silence += 1
	var repeat_held := _silence < 8
	return {"move": _last_remote.get("move", Vector2.ZERO) if repeat_held else Vector2.ZERO,
		"jump": repeat_held and _last_remote.get("jump_held", false),
		"crouch": repeat_held and _last_remote.get("crouch", false),
		"walk": repeat_held and _last_remote.get("walk", false),
		"yaw": _last_remote.get("yaw", 0.0), "pitch": _last_remote.get("pitch", 0.0)}

func _cast(shot: Dictionary, shooter: TrialFighter) -> Dictionary:
	var origin: Vector3 = shot["origin"]
	var reach: float = shot.get("range", 90.0)
	var end: Vector3 = origin + shot["direction"] * reach
	var ray := PhysicsRayQueryParameters3D.create(origin, end, 3, [shooter.get_rid()])
	ray.hit_from_inside = shot["weapon"] == Fighter.KNIFE
	var impact := get_world_3d().direct_space_state.intersect_ray(ray)
	var target := 0
	var normal := Vector3.ZERO
	if not impact.is_empty():
		end = impact["position"]
		normal = impact["normal"]
		var collider: Node = impact["collider"]
		if collider.is_in_group("practice_target"):
			target = int(collider.get_meta("target_id", 1))
		elif collider is TrialFighter:
			target = 99
	return {"origin": origin, "end": end, "normal": normal, "target": target,
		"weapon": shot["weapon"], "shots": shot["shots"]}

func _local_shot(shot: Dictionary) -> void:
	var impact := _cast(shot, local_player)
	_viewmodel.notify_attack(shot["weapon"])
	_feedback(impact, true)
	if link.is_host and link.remote_ready:
		impact["slot"] = 0
		link.send_shot(impact)

func _receive_shot(event: Dictionary) -> void:
	_test_received += 1
	if int(event.get("slot", -1)) == 0:
		_feedback(event, false)
	else:
		_show_hit(int(event.get("target", 0)))

func _feedback(event: Dictionary, own: bool) -> void:
	if own:
		if DisplayServer.get_name() != "headless":
			_audio.stream = _sounds[event["weapon"]]
			_audio.play()
		if not link.remote_ready or link.is_host:
			_show_hit(event["target"])
	if event["weapon"] == Fighter.KNIFE:
		if not own and _smoke in ["--smoke-host", "--smoke-client"]:
			_test_saw_remote_swing = true
		return
	var origin: Vector3 = event["origin"]
	var end: Vector3 = event["end"]
	var normal: Vector3 = event.get("normal", Vector3.ZERO)
	if normal.length_squared() > 0.5 and event["target"] != 99:
		var mark := _marks[_mark_next]
		var plane_up := Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > 0.98 else Vector3.UP
		mark.global_transform = Transform3D(Basis.looking_at(-normal, plane_up), end + normal * 0.003)
		mark.show()
		_mark_next = (_mark_next + 1) % _marks.size()
	var direction := origin.direction_to(end)
	var tracer := _tracer_pool[_tracer_next]
	var length := minf(origin.distance_to(end) * 0.35, 2.8)
	if length > 0.05:
		var center := end - direction * length * 0.5
		var up := Vector3.RIGHT if absf(direction.dot(Vector3.UP)) > 0.98 else Vector3.UP
		tracer.global_transform = Transform3D(Basis.looking_at(direction, up).scaled_local(Vector3(1, 1, length)), center)
		tracer.visible = true
		_tracer_timers[_tracer_next] = 0.105
		_tracer_next = (_tracer_next + 1) % _tracer_pool.size()

func _show_hit(target: int) -> void:
	if target > 0:
		_hit_time = 0.23
		_number_hits += 1
		hud.hit_label.text = "命中陪练" if target == 99 else "命中靶标  %02d" % target

func _process(dt: float) -> void:
	camera.position = _eye_prior.lerp(local_player.eye_position(), Engine.get_physics_interpolation_fraction())
	var recoil := local_player.recoil
	camera.rotation = Vector3(aim.y + deg_to_rad(recoil.y), aim.x + deg_to_rad(recoil.x), 0.0)
	if link.remote_ready and not link.is_host and is_instance_valid(remote_player):
		_proxy_elapsed += dt
		remote_player.global_position = _proxy_from.lerp(_proxy_to, clampf(_proxy_elapsed * 64.0, 0.0, 1.0))
	_hit_time = maxf(_hit_time - dt, 0.0)
	var look_delta := aim - _aim_prior
	_aim_prior = aim
	_viewmodel.tick(dt, local_player, look_delta)
	for index in _tracer_pool.size():
		if _tracer_timers[index] > 0.0:
			_tracer_timers[index] -= dt
			if _tracer_timers[index] <= 0.0:
				_tracer_pool[index].hide()
	var shown_spread := snappedf(local_player.spread_degrees(), 0.1)
	hud.crosshair.set_feedback(shown_spread, _viewmodel.firing(), _hit_time > 0.0)
	hud.hit_label.modulate.a = clampf(_hit_time * 9.0, 0.0, 1.0)
	_performance.append(dt * 1000.0)
	_performance_elapsed += dt
	if _performance_elapsed >= 0.8:
		_update_telemetry()
	_stats_elapsed += dt
	if _stats_elapsed >= 0.05:
		_stats_elapsed = 0.0
		_update_player_stats()
	if _smoke == "--visual-test":
		_visual_check()
	elif _smoke == "--bench-run":
		_measure_benchmark()

func _update_telemetry() -> void:
	_performance.sort()
	var p99: float = _performance[mini(ceili(_performance.size() * 0.99) - 1, _performance.size() - 1)]
	var fps := float(_performance.size()) / _performance_elapsed
	hud.frame_label.text = "%d FPS   /   %.2f ms P99" % [roundi(fps), p99]
	_performance.clear()
	_performance_elapsed = 0.0

func _update_player_stats() -> void:
	var sens: float = options["sensitivity"]
	var state_name := ["宽屏", "4:3 黑边", "4:3 拉伸"][int(options["view"])] as String
	hud.position_label.text = "%s  ·  灵敏度 %s  ·  命中 %d" % [state_name, str(sens), _number_hits]
	var speed := roundi(local_player.accuracy_speed / Fighter.UNIT)
	if local_player.weapon == Fighter.KNIFE:
		hud.rig_label.text = "%03d u/s" % speed
		_update_ammo()
		return
	var accuracy_state := "首发稳定"
	if not local_player.grounded:
		accuracy_state = "腾空散布"
	elif local_player.accuracy_speed > Fighter.RUN_SPEED[local_player.weapon] * Fighter.UNIT * Fighter.ACCURATE_SPEED_RATIO:
		accuracy_state = "移动散布"
	elif local_player.streak > 0:
		accuracy_state = "射击恢复"
	hud.rig_label.text = "%03d u/s   /   %s   /   %.1f°" % [speed, accuracy_state, local_player.spread_degrees()]
	_update_ammo()

func _update_ammo() -> void:
	var info := "3  近战刀    左键挥击"
	if local_player.weapon != Fighter.KNIFE:
		var label := "1  主武器" if local_player.weapon == Fighter.RIFLE else "2  手枪"
		info = "%s    %02d / %02d" % [label, local_player.rounds[local_player.weapon], Fighter.CAPACITY[local_player.weapon]]
		if local_player.reloading > 0.0:
			info += "  换弹"
	if info != _last_info:
		_last_info = info
		hud.ammo_label.text = info

func _build_presentation() -> void:
	_audio = AudioStreamPlayer.new()
	add_child(_audio)
	_sounds = [_weapon_sound(Fighter.PISTOL), _weapon_sound(Fighter.RIFLE), _weapon_sound(Fighter.KNIFE)]
	_viewmodel = VmRig.new()
	camera.add_child(_viewmodel)
	var glow := _material(Color("#f9d38d"), true)
	for index in 12:
		var trace := _solid(self, Vector3(0.012, 0.012, 1.0), Vector3.ZERO, glow)
		trace.hide()
		_tracer_pool.append(trace)
		_tracer_timers.append(0.0)
	var ink := _material(Color("#101c21"), true)
	for index in 48:
		var mark := _solid(self, Vector3(0.038, 0.038, 0.005), Vector3.ZERO, ink)
		mark.hide()
		_marks.append(mark)

func _visual_check() -> void:
	_visual_frames += 1
	if _visual_frames == 45:
		RenderingServer.frame_post_draw.connect(_capture_visual.bind("menu"), CONNECT_ONE_SHOT)
	elif _visual_frames == 55:
		_resume()
	elif _visual_frames == 150:
		RenderingServer.frame_post_draw.connect(_capture_visual.bind("range"), CONNECT_ONE_SHOT)

func _capture_visual(name_of_view: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var filename := "angleline-%s-%d.png" % [name_of_view, _visual_view]
	var error := image.save_png("user://" + filename)
	print("VISUAL_TEST ", ProjectSettings.globalize_path("user://" + filename), " code=", error, " size=", image.get_size())
	if name_of_view == "range":
		get_tree().quit(error)

func _benchmark_input(command: Dictionary) -> void:
	var phase := _world_tick % 384
	var horizontal := 1.0 if phase < 90 else (-1.0 if phase >= 192 and phase < 282 else 0.0)
	command["move"] = Vector2(horizontal, 0)
	command["fire"] = phase % 96 >= 28 and phase % 96 < 62
	command["reload"] = phase == 294 or phase == 300
	if phase == 0:
		_place(local_player, 0)
		_eye_prior = local_player.eye_position()
	aim.x = sin(float(phase) / 384.0 * TAU) * 0.15
	command["yaw"] = aim.x

func _measure_benchmark() -> void:
	var now := Time.get_ticks_usec()
	var seconds := float(now - _bench_start) * 0.000001
	if seconds > 2.0:
		_bench_frames.append(float(now - _bench_previous) * 0.001)
	_bench_previous = now
	if seconds < 17.0:
		return
	_bench_frames.sort()
	var draw_size := get_viewport().get_texture().get_size()
	var cpu := OS.get_processor_name()
	var gpu := RenderingServer.get_video_adapter_name()
	var p99 := _bench_frames[ceili(float(_bench_frames.size()) * 0.99) - 1]
	print("RANGE_BENCH size=", draw_size, " CPU=", cpu, " GPU=", gpu, " seconds=", snappedf(seconds - 2.0, 0.01),
		" avg_fps=", snappedf(float(_bench_frames.size()) / (seconds - 2.0), 0.1), " p99_ms=", snappedf(p99, 0.01))
	get_tree().quit()

func _material(color: Color, flat: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	if flat:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

func _solid(parent: Node3D, size: Vector3, location: Vector3, material: Material) -> MeshInstance3D:
	var geometry := BoxMesh.new()
	geometry.size = size
	geometry.material = material
	var instance := MeshInstance3D.new()
	instance.mesh = geometry
	instance.position = location
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance

func _weapon_sound(which: int) -> AudioStreamWAV:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var samples := PackedByteArray()
	var count: int = [3400, 4400, 3000][which]
	samples.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9181 + which
	var low := 0.0
	for index in count:
		var t := float(index) / 22050.0
		var noise := rng.randf_range(-1, 1)
		low = lerpf(low, noise, 0.19)
		var value: float
		if which == Fighter.KNIFE:
			value = low * 0.7 * pow(sin(PI * index / float(count)), 2.0)
		else:
			var kick := sin(TAU * (110.0 if which == Fighter.PISTOL else 77.0) * t) * exp(-t * 39.0)
			value = low * 0.55 * exp(-t * 28) + noise * 0.36 * exp(-t * 105) + kick * 0.40
		samples.encode_s16(index * 2, roundi(clampf(value, -0.95, 0.95) * 32767.0))
	sound.data = samples
	return sound

func _print_engine_licenses() -> void:
	print(Engine.get_license_text())
	var licenses := Engine.get_license_info()
	for license_name in licenses:
		print("\n" + str(license_name) + "\n" + str(licenses[license_name]))
	print("\nCopyright notices\n")
	for component in Engine.get_copyright_info():
		print(component["name"])
		for part in component["parts"]:
			for holder in part["copyright"]:
				print(holder)
			print("License: ", part["license"])

func _simulate_test(command: Dictionary) -> void:
	if _world_tick == 10:
		_test_start = local_player.global_position
	if _world_tick >= 10 and _world_tick < 90:
		command["move"] = Vector2(0, -1)
		_test_peak = maxf(_test_peak, local_player.accuracy_speed)
	if _world_tick == 90:
		_test_stop = local_player.position.z
	if _world_tick == 130:
		_test_stop = absf(local_player.position.z - _test_stop)
	if _world_tick >= 135 and _world_tick < 215:
		command["move"] = Vector2(1, 0)
	if _world_tick == 215:
		_test_reverse = local_player.position.x
	if _world_tick >= 215 and _world_tick < 227 and local_player.velocity.x > 0.0:
		command["move"] = Vector2(-1, 0)
	if _world_tick == 227:
		_test_reverse = absf(local_player.position.x - _test_reverse)
	if _world_tick == 235:
		command["jump"] = true
	if _world_tick > 235 and _world_tick < 325:
		_test_jump = maxf(_test_jump, local_player.position.y)
	if _world_tick >= 325 and _world_tick < 370:
		command["fire"] = true
	if _world_tick == 374:
		var count := 360.0 / 0.022
		var rotation := rad_to_deg(Fighter.turn_delta(Vector2(count, 0), 1.0, Vector2.ONE).x)
		var run := _test_peak / Fighter.UNIT
		var distance := _test_start.distance_to(local_player.position)
		var valid := absf(rotation + 360.0) < 0.001 and absf(run - 215.0) < 0.1
		valid = valid and _test_stop > _test_reverse and _test_reverse > 0.0
		valid = valid and _test_fires == 4 and _test_jump > 0.9 and local_player.grounded
		print("SELF_TEST ", "PASS" if valid else "FAIL", " rotation=", snappedf(rotation, 0.001),
			" vertical_fov=", camera.fov, " run=", snappedf(run, 0.001),
			" coast=", snappedf(_test_stop, 0.0001), " counter=", snappedf(_test_reverse, 0.0001),
			" jump=", snappedf(_test_jump, 0.0001), " shots=", _test_fires, " distance=", snappedf(distance, 0.0001))
		get_tree().quit(0 if valid else 1)

func _network_test(command: Dictionary) -> void:
	if not link.remote_ready:
		if _world_tick > 1536:
			print("NETWORK_TEST FAIL no peer")
			get_tree().quit(1)
		return
	_test_round += 1
	if _test_round < 53:
		command["move"] = Vector2(0, -1)
	if _test_round >= 90:
		command["weapon"] = Fighter.KNIFE
	if _test_round in [58, 78, 140]:
		command["fire_pressed"] = true
	if _test_round == 180:
		var valid := _test_fires == 3 and _test_received >= 3 and _test_saw_remote_swing and is_instance_valid(remote_player)
		valid = valid and remote_player.position.z < 5.4 and local_player.position.z < 5.4
		valid = valid and local_player.weapon == Fighter.KNIFE and remote_player.weapon == Fighter.KNIFE
		print("NETWORK_TEST ", "PASS" if valid else "FAIL", " role=", "host" if link.is_host else "guest",
			" local_shots=", _test_fires, " confirmed=", _test_received, " ack=", _ack,
			" local_z=", snappedf(local_player.position.z, 0.001), " other_z=", snappedf(remote_player.position.z, 0.001))
		get_tree().quit(0 if valid else 1)
