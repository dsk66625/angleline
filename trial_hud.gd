class_name TrialHUD
extends CanvasLayer

signal applied(values: Dictionary)
signal resumed
signal host_requested(port: int)
signal join_requested(address: String, port: int)
signal leave_requested
signal reset_requested
signal quit_requested

const Reticle = preload("res://crosshair.gd")
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
var crosshair: Reticle
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
var _general_page: VBoxContainer
var _crosshair_page: VBoxContainer
var _general_tab: Button
var _crosshair_tab: Button
var _footer: HBoxContainer
var _preview: Reticle
var _shape: OptionButton
var _color: ColorPickerButton
var _length: HSlider
var _gap: HSlider
var _thickness: HSlider
var _dot: CheckButton
var _outline: CheckButton
var _dynamic: CheckButton
var _loading_style := false

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
	crosshair.set_render_height(render_size.y)
	_preview.set_render_height(render_size.y)

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
	var keys := _label("WASD 移动 · 长按空格连跳 · 滚轮跳 · Ctrl 蹲 · Shift 静步 · 1 主武器 · 2 手枪 · 3 近战 · R 换弹 · F 检视 · F2 复位 · Esc 设置", 13, PAPER)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	key_panel.add_child(keys)

	crosshair = Reticle.new()
	_root.add_child(crosshair)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
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

	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	var group := ButtonGroup.new()
	_general_tab = _button(tabs, "常规设置", _select_page.bind(false))
	_crosshair_tab = _button(tabs, "准星设置", _select_page.bind(true))
	for tab in [_general_tab, _crosshair_tab]:
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_general_page = VBoxContainer.new()
	_general_page.add_theme_constant_override("separation", 8)
	body.add_child(_general_page)
	var columns := GridContainer.new()
	columns.columns = 2
	columns.add_theme_constant_override("h_separation", 10)
	columns.add_theme_constant_override("v_separation", 6)
	_general_page.add_child(columns)
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
	_general_page.add_child(network_bar)
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
	_general_page.add_child(_connection)
	_crosshair_page = VBoxContainer.new()
	_crosshair_page.add_theme_constant_override("separation", 8)
	body.add_child(_crosshair_page)
	_build_crosshair_page()
	_select_page(false)
	_settings_error = _label("", 13, Color("#ffc68e"))
	body.add_child(_settings_error)
	_settings_error.hide()
	_footer = HBoxContainer.new()
	body.add_child(_footer)
	_footer.add_child(_label("Esc 放弃更改并返回", 13, MUTED))
	_spacer(_footer)
	_button(_footer, "复位练习", func() -> void: reset_requested.emit())
	_button(_footer, "退出", func() -> void: quit_requested.emit())

func mount_update_menu(menu: Control, open_menu: Callable) -> Button:
	var button := _button(_footer, "游戏更新", open_menu)
	_footer.move_child(button, 2)
	_root.add_child(menu)
	menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.visibility_changed.connect(func() -> void:
		_center.visible = _veil.visible and not menu.visible
		if _center.is_visible_in_tree():
			button.grab_focus())
	return button

func _select_page(edit_crosshair: bool) -> void:
	_general_page.visible = not edit_crosshair
	_crosshair_page.visible = edit_crosshair
	_general_tab.set_pressed_no_signal(not edit_crosshair)
	_crosshair_tab.set_pressed_no_signal(edit_crosshair)

func _build_crosshair_page() -> void:
	_crosshair_page.custom_minimum_size.x = 460
	var preview_panel := _panel(_crosshair_page, Color("#37474b"), Color("#53696a"), 12, 6)
	var preview_body := VBoxContainer.new()
	preview_panel.add_child(preview_body)
	var preview_header := HBoxContainer.new()
	preview_body.add_child(preview_header)
	preview_header.add_child(_label("准星预览", 15, PAPER))
	_spacer(preview_header)
	var movement := CheckButton.new()
	movement.text = "模拟移动"
	preview_header.add_child(movement)
	_preview = Reticle.new()
	_preview.custom_minimum_size.y = 124
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview_body.add_child(_preview)
	movement.toggled.connect(func(moving: bool) -> void:
		_preview.set_feedback(2.0 if moving else 0.0, false, false))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 15)
	grid.add_theme_constant_override("v_separation", 6)
	_crosshair_page.add_child(grid)
	grid.add_child(_label("准星形状", 15, PAPER))
	_shape = OptionButton.new()
	for title in ["十字", "T 形", "圆点"]:
		_shape.add_item(title)
	_shape.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_shape)
	_shape.item_selected.connect(func(_index: int) -> void: _update_preview())
	grid.add_child(_label("准星颜色", 15, PAPER))
	_color = ColorPickerButton.new()
	_color.edit_alpha = false
	_color.custom_minimum_size.y = 28
	grid.add_child(_color)
	_color.color_changed.connect(func(_value: Color) -> void: _update_preview())
	_length = _dimension(grid, "线长", Reticle.LENGTH_MIN, Reticle.LENGTH_MAX)
	_gap = _dimension(grid, "单侧间距", Reticle.GAP_MIN, Reticle.GAP_MAX)
	_thickness = _dimension(grid, "粗细", Reticle.THICKNESS_MIN, Reticle.THICKNESS_MAX)
	var flags := HBoxContainer.new()
	_crosshair_page.add_child(flags)
	_dot = _style_toggle(flags, "中心点")
	_outline = _style_toggle(flags, "描边")
	_dynamic = _style_toggle(flags, "动态散布")
	var defaults_row := HBoxContainer.new()
	_crosshair_page.add_child(defaults_row)
	defaults_row.add_child(_label("尺寸以 960p 像素计", 13, MUTED))
	_spacer(defaults_row)
	_button(defaults_row, "CS2 静态准星", func() -> void: _load_style(Reticle.CS2_STATIC))
	_button(defaults_row, "恢复默认准星", func() -> void: _load_style(Reticle.DEFAULTS))
	_load_style(Reticle.DEFAULTS)

func _dimension(parent: Container, title: String, minimum: int, maximum: int) -> HSlider:
	parent.add_child(_label(title, 15, PAPER))
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(row)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var reading := _label(str(int(slider.value)), 15, PAPER)
	reading.custom_minimum_size.x = 28
	reading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(reading)
	slider.value_changed.connect(func(value: float) -> void:
		reading.text = str(int(value))
		_update_preview())
	return slider

func _style_toggle(parent: Container, title: String) -> CheckButton:
	var toggle := CheckButton.new()
	toggle.text = title
	parent.add_child(toggle)
	toggle.toggled.connect(func(_pressed: bool) -> void: _update_preview())
	return toggle

func _load_style(raw: Variant) -> void:
	var style := Reticle.normalize(raw)
	_loading_style = true
	_shape.select(style["shape"])
	_color.color = style["color"]
	_length.value = style["length"]
	_gap.value = style["gap"]
	_thickness.value = style["thickness"]
	_dot.set_pressed_no_signal(style["dot"])
	_outline.set_pressed_no_signal(style["outline"])
	_dynamic.set_pressed_no_signal(style["dynamic"])
	_loading_style = false
	_update_preview()

func _edited_style() -> Dictionary:
	return Reticle.normalize({"shape": _shape.selected, "color": _color.color,
		"length": int(_length.value), "gap": int(_gap.value), "thickness": int(_thickness.value),
		"dot": _dot.button_pressed, "outline": _outline.button_pressed, "dynamic": _dynamic.button_pressed})

func _update_preview() -> void:
	if _loading_style:
		return
	var has_lines := _shape.selected != Reticle.Shape.DOT
	_length.editable = has_lines
	_gap.editable = has_lines
	_dot.disabled = not has_lines
	_dynamic.disabled = not has_lines
	_preview.apply_style(_edited_style())

func dismiss_crosshair_popup() -> bool:
	if _color.get_popup().visible:
		_color.get_popup().hide()
		return true
	if _shape.get_popup().visible:
		_shape.get_popup().hide()
		return true
	return false

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
	_settings_error.hide()
	_load_style(settings.get("crosshair", Reticle.DEFAULTS))
	crosshair.apply_style(_edited_style())
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
			_select_page(false)
			_settings_error.text = "灵敏度和轴向倍率请输入大于 0 且不超过 50 的数字。"
			_settings_error.show()
			return
	if CAPS[_cap.selected] == -1 and (not _custom_cap.text.is_valid_int() or int(_custom_cap.text) < 30 or int(_custom_cap.text) > 2000):
		_select_page(false)
		_settings_error.text = "自定义帧率请输入 30 到 2000 之间的整数。"
		_settings_error.show()
		return
	_settings_error.hide()
	applied.emit({"sensitivity": float(_sense.text), "axis_x": float(_axis_x.text),
		"axis_y": float(_axis_y.text), "view": _preset.selected,
		"resolution": RESOLUTIONS[_resolution.selected], "fullscreen": _fullscreen.button_pressed,
		"cap": int(_custom_cap.text) if CAPS[_cap.selected] == -1 else CAPS[_cap.selected],
		"vsync": _sync.button_pressed, "volume": int(_sound.value), "crosshair": _edited_style()})
	resumed.emit()

func show_menu(visible_menu: bool) -> void:
	_center.visible = visible_menu
	_veil.visible = visible_menu
	crosshair.visible = not visible_menu
	hit_label.visible = not visible_menu

func connection_status(message: String) -> void:
	status_label.text = message
	_connection.text = message
