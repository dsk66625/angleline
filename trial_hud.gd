class_name TrialHUD
extends CanvasLayer

signal applied(values: Dictionary)
signal resumed
signal host_requested(port: int)
signal join_requested(address: String, port: int)
signal leave_requested
signal reset_requested
signal quit_requested

const GREEN := Color("#cdff7a")
const PAPER := Color("#e6ece8")
const MUTED := Color("#adbfbe")
const DARK := Color("#131e22")
const CAPS := [0, 60, 120, 144, 165, 240, 360, 480, -1]
const RESOLUTIONS := [
	Vector2i.ZERO,
	Vector2i(1024, 768), Vector2i(1280, 960), Vector2i(1440, 1080), Vector2i(1600, 1200), Vector2i(1920, 1440),
	Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440),
]

var frame_label: Label
var rig_label: Label
var ammo_label: Label
var status_label: Label
var hit_label: Label
var position_label: Label
var crosshair: Control
var spread := 0.0
var pulsed := false
var hit := false
var _root: Control
var _veil: ColorRect
var _center: CenterContainer
var _sense: LineEdit
var _axis_x: LineEdit
var _axis_y: LineEdit
var _address: LineEdit
var _port: SpinBox
var _preset: OptionButton
var _resolution: OptionButton
var _fullscreen: CheckButton
var _cap: OptionButton
var _custom_cap: LineEdit
var _sync: CheckButton
var _sound: HSlider
var _connection: Label
var _settings_profile: Label
var _settings_error: Label

func _ready() -> void:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Segoe UI", "Noto Sans CJK SC"])
	var ui := Theme.new()
	ui.default_font = font
	ui.default_font_size = 16
	_style_theme(ui)
	_root = Control.new()
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = ui
	_build_in_game()
	_build_pause()
	show_menu(true)

func _style_theme(ui: Theme) -> void:
	for kind in ["Button", "OptionButton", "LineEdit", "CheckButton"]:
		ui.set_color("font_color", kind, PAPER)
		ui.set_color("font_hover_color", kind, PAPER)
		ui.set_color("font_pressed_color", kind, GREEN)
		ui.set_color("font_focus_color", kind, PAPER)
		ui.set_stylebox("normal", kind, _box(Color("#233337"), Color("#405657"), 12, 6))
		ui.set_stylebox("hover", kind, _box(Color("#354a4a"), GREEN, 12, 6))
		ui.set_stylebox("pressed", kind, _box(Color("#1d2c30"), GREEN, 12, 6))
		ui.set_stylebox("focus", kind, _box(Color(0, 0, 0, 0), GREEN, 12, 6))

func fit_render_size(render_size: Vector2i) -> void:
	if render_size.x <= 0 or render_size.y <= 0:
		return
	var ui_scale := minf(float(render_size.y) / 720.0, float(render_size.x) / 960.0)
	_root.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_root.scale = Vector2.ONE * ui_scale
	_root.size = Vector2(render_size) / ui_scale

func _box(fill: Color, outline: Color, horizontal: float, vertical: float) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = outline
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.content_margin_left = horizontal
	box.content_margin_right = horizontal
	box.content_margin_top = vertical
	box.content_margin_bottom = vertical
	return box

func _label(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _panel(parent: Node, fill: Color, outline: Color, x: float, y: float) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _box(fill, outline, x, y))
	parent.add_child(panel)
	return panel

func _build_in_game() -> void:
	var overlay := MarginContainer.new()
	_root.add_child(overlay)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "top", "right", "bottom"]:
		overlay.add_theme_constant_override("margin_" + side, 22)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var layout := VBoxContainer.new()
	overlay.add_child(layout)
	layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var top := HBoxContainer.new()
	var bottom := HBoxContainer.new()
	layout.add_child(top)
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(gap)
	layout.add_child(bottom)

	var title := _panel(top, Color("#19272bd9"), Color("#53696a"), 13, 8)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var title_stack := VBoxContainer.new()
	title.add_child(title_stack)
	title_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_stack.add_child(_label("角线   ANGLELINE", 19, GREEN))
	status_label = _label("离线练习", 13, PAPER)
	title_stack.add_child(status_label)
	_spacer(top)
	frame_label = _label("", 15, PAPER)
	top.add_child(frame_label)
	frame_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	frame_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	frame_label.add_theme_color_override("font_shadow_color", Color("#11181a"))
	frame_label.add_theme_constant_override("shadow_offset_y", 1)

	var telemetry := _panel(bottom, Color("#19272bd9"), Color("#53696a"), 13, 8)
	telemetry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var stats := VBoxContainer.new()
	telemetry.add_child(stats)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rig_label = _label("", 16, PAPER)
	stats.add_child(rig_label)
	position_label = _label("", 13, MUTED)
	stats.add_child(position_label)
	_spacer(bottom)
	var kit := _panel(bottom, Color("#19272bd9"), Color("#53696a"), 16, 8)
	kit.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ammo_label = _label("", 23, GREEN)
	kit.add_child(ammo_label)
	ammo_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var key_panel := _panel(layout, Color("#19272bd9"), Color("#53696a"), 9, 4)
	key_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	key_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var keys := _label("WASD 移动  ·  空格 跳  ·  Shift 静步  ·  Ctrl 蹲  ·  1 / 2 切枪  ·  R 换弹  ·  F2 复位  ·  Esc 设置", 13, PAPER)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_panel.add_child(keys)

	crosshair = Control.new()
	_root.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	hit_label = _label("", 15, GREEN)
	_root.add_child(hit_label)
	hit_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	hit_label.offset_top = 29
	hit_label.offset_left = -110
	hit_label.offset_right = 110
	hit_label.offset_bottom = 55
	hit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _spacer(parent: Container) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(spacer)

func _build_pause() -> void:
	_veil = ColorRect.new()
	_veil.color = Color(0.026, 0.044, 0.052, 0.83)
	_root.add_child(_veil)
	_veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center = CenterContainer.new()
	_root.add_child(_center)
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := _panel(_center, DARK, Color("#53696a"), 26, 16)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	panel.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	header.add_child(_label("角线", 34, PAPER))
	_spacer(header)
	var play := _button(header, "进入练习", _apply_and_resume)
	play.add_theme_color_override("font_color", GREEN)
	_settings_profile = _label("ANGLELINE  /  手感测试场", 14, GREEN)
	body.add_child(_settings_profile)

	var columns := GridContainer.new()
	columns.columns = 2
	columns.add_theme_constant_override("h_separation", 10)
	columns.add_theme_constant_override("v_separation", 6)
	body.add_child(columns)
	_sense = _edit(columns, "CS2 鼠标灵敏度", "1.00")
	_axis_x = _edit(columns, "水平倍率", "1.00")
	_axis_y = _edit(columns, "垂直倍率", "1.00")
	columns.add_child(_label("渲染分辨率", 15, PAPER))
	_resolution = OptionButton.new()
	for size: Vector2i in RESOLUTIONS:
		if size == Vector2i.ZERO:
			_resolution.add_item("自动（跟随窗口）")
		else:
			var ratio := "4:3" if is_four_three(size) else "16:9"
			_resolution.add_item("%d × %d   (%s)" % [size.x, size.y, ratio])
	_resolution.item_selected.connect(_resolution_selected)
	columns.add_child(_resolution)
	columns.add_child(_label("世界视角", 15, PAPER))
	_preset = OptionButton.new()
	for name_of_mode in ["原生宽屏", "4:3 黑边", "4:3 拉伸"]:
		_preset.add_item(name_of_mode)
	_preset.item_selected.connect(_view_selected)
	columns.add_child(_preset)
	columns.add_child(_label("帧率上限", 15, PAPER))
	var rate_options := HBoxContainer.new()
	columns.add_child(rate_options)
	_cap = OptionButton.new()
	for cap in CAPS:
		_cap.add_item("不限帧" if cap == 0 else ("自定义" if cap == -1 else str(cap) + " FPS"))
	rate_options.add_child(_cap)
	_custom_cap = LineEdit.new()
	_custom_cap.custom_minimum_size.x = 92.0
	_custom_cap.max_length = 5
	_custom_cap.text = "300"
	rate_options.add_child(_custom_cap)
	_cap.item_selected.connect(func(index: int) -> void: _custom_cap.visible = CAPS[index] == -1)
	columns.add_child(_label("显示选项", 15, PAPER))
	var display_options := HBoxContainer.new()
	columns.add_child(display_options)
	_fullscreen = CheckButton.new()
	_fullscreen.text = "全屏"
	display_options.add_child(_fullscreen)
	_sync = CheckButton.new()
	_sync.text = "垂直同步"
	display_options.add_child(_sync)
	columns.add_child(_label("开火音量", 15, PAPER))
	_sound = HSlider.new()
	_sound.min_value = 0
	_sound.max_value = 100
	_sound.step = 1
	_sound.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(_sound)
	var network_bar := HBoxContainer.new()
	body.add_child(network_bar)
	network_bar.add_child(_label("局域网", 16, GREEN))
	_address = LineEdit.new()
	_address.placeholder_text = "主机 IP"
	_address.text = "127.0.0.1"
	_address.custom_minimum_size.x = 119.0
	network_bar.add_child(_address)
	_port = SpinBox.new()
	_port.min_value = 1024
	_port.max_value = 65535
	_port.value = 27428
	network_bar.add_child(_port)
	_button(network_bar, "开房", func() -> void: host_requested.emit(int(_port.value)))
	_button(network_bar, "加入", func() -> void: join_requested.emit(_address.text.strip_edges(), int(_port.value)))
	_button(network_bar, "断开", func() -> void: leave_requested.emit())
	_connection = _label("当前为离线练习", 13, MUTED)
	body.add_child(_connection)
	_settings_error = _label("", 13, Color("#ffc68e"))
	body.add_child(_settings_error)
	_settings_error.hide()
	var footer := HBoxContainer.new()
	body.add_child(footer)
	footer.add_child(_label("Esc 返回测试场", 13, MUTED))
	_spacer(footer)
	_button(footer, "复位练习", func() -> void: reset_requested.emit())
	_button(footer, "退出", func() -> void: quit_requested.emit())

func _edit(parent: Container, title: String, initial: String) -> LineEdit:
	parent.add_child(_label(title, 15, PAPER))
	var field := LineEdit.new()
	field.text = initial
	field.custom_minimum_size.x = 180.0
	field.max_length = 12
	field.text_submitted.connect(func(_entered: String) -> void: _apply_and_resume())
	parent.add_child(field)
	return field

func _button(parent: Container, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

static func is_four_three(size: Vector2i) -> bool:
	return size != Vector2i.ZERO and size.x * 3 == size.y * 4

func _resolution_selected(index: int) -> void:
	var size: Vector2i = RESOLUTIONS[index]
	if size == Vector2i.ZERO:
		return
	if is_four_three(size):
		if _preset.selected == 0:
			_preset.select(1)
	else:
		_preset.select(0)

func _view_selected(index: int) -> void:
	var current: Vector2i = RESOLUTIONS[_resolution.selected]
	if current == Vector2i.ZERO or is_four_three(current) == (index != 0):
		return
	var best := -1
	var distance := 2147483647
	for i in range(1, RESOLUTIONS.size()):
		var choice: Vector2i = RESOLUTIONS[i]
		if is_four_three(choice) != (index != 0):
			continue
		var difference := absi(choice.y - current.y)
		if difference < distance:
			distance = difference
			best = i
	_resolution.select(best)

func load_values(settings: Dictionary) -> void:
	_sense.text = str(settings["sensitivity"])
	_axis_x.text = str(settings["axis_x"])
	_axis_y.text = str(settings["axis_y"])
	_preset.select(int(settings["view"]))
	_resolution.select(maxi(0, RESOLUTIONS.find(settings["resolution"])))
	_fullscreen.button_pressed = settings["fullscreen"]
	var limit_index := CAPS.find(settings["cap"])
	_cap.select(CAPS.size() - 1 if limit_index < 0 else limit_index)
	_custom_cap.visible = limit_index < 0
	if limit_index < 0:
		_custom_cap.text = str(settings["cap"])
	_sync.button_pressed = settings["vsync"]
	_sound.value = settings["volume"]

func _apply_and_resume() -> void:
	var fields := [_sense, _axis_x, _axis_y]
	for field in fields:
		if not field.text.is_valid_float() or float(field.text) <= 0.0 or float(field.text) > 50.0:
			_settings_error.text = "灵敏度和轴向倍率请输入大于 0 且不超过 50 的数字。"
			_settings_error.show()
			return
	if CAPS[_cap.selected] == -1 and (not _custom_cap.text.is_valid_int() or int(_custom_cap.text) < 30 or int(_custom_cap.text) > 2000):
		_settings_error.text = "自定义帧率请输入 30 到 2000 之间的整数。"
		_settings_error.show()
		return
	_settings_error.hide()
	applied.emit({"sensitivity": float(_sense.text), "axis_x": float(_axis_x.text),
		"axis_y": float(_axis_y.text), "view": _preset.selected,
		"resolution": RESOLUTIONS[_resolution.selected], "fullscreen": _fullscreen.button_pressed,
		"cap": int(_custom_cap.text) if CAPS[_cap.selected] == -1 else CAPS[_cap.selected],
		"vsync": _sync.button_pressed, "volume": int(_sound.value)})
	resumed.emit()

func show_menu(visible_menu: bool) -> void:
	_center.visible = visible_menu
	_veil.visible = visible_menu
	crosshair.visible = not visible_menu
	hit_label.visible = not visible_menu

func connection_status(message: String) -> void:
	status_label.text = message
	_connection.text = message

func _draw_crosshair() -> void:
	var center := crosshair.size * 0.5
	var gap := clampf(4.0 + spread * 4.0, 4.0, 30.0)
	var color := Color.WHITE if pulsed else GREEN
	for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var start: Vector2 = center + direction * gap
		var finish: Vector2 = center + direction * (gap + 5.0)
		crosshair.draw_line(start, finish, Color("#202729"), 4)
		crosshair.draw_line(start, finish, color, 2)
	if hit:
		for direction in [Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1), Vector2(1, -1)]:
			crosshair.draw_line(center + direction * 7, center + direction * 12, Color.WHITE, 2)
