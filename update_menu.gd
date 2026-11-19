extends Control

const Updater = preload("res://game_updater.gd")
const GREEN := Color("#cdff7a")
const PAPER := Color("#e6ece8")

var updater: Updater
var _status: Label
var _check: Button
var _install: Button
var _progress: ProgressBar


func _ready() -> void:
	hide()
	var veil := ColorRect.new()
	veil.color = Color(0.026, 0.044, 0.052, 0.86)
	add_child(veil)
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color("#131e22")
	box.border_color = Color("#53696a")
	box.set_border_width_all(1)
	box.set_corner_radius_all(5)
	box.content_margin_left = 24
	box.content_margin_right = 24
	box.content_margin_top = 20
	box.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", box)
	center.add_child(panel)
	var body := VBoxContainer.new()
	body.custom_minimum_size.x = 470
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	var heading := HBoxContainer.new()
	body.add_child(heading)
	var title := _label(heading, "游戏更新", 24, GREEN)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var back := _button(heading, "返回", hide)
	_label(body, "当前版本 v" + updater.current_version, 15, PAPER)
	_status = _label(body, "", 16, PAPER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_progress = ProgressBar.new()
	_progress.custom_minimum_size.y = 18
	body.add_child(_progress)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	_check = _button(actions, "检查更新", updater.check)
	_install = _button(actions, "重启并更新", updater.install)
	_install.add_theme_color_override("font_color", GREEN)
	updater.changed.connect(_refresh)
	visibility_changed.connect(func() -> void:
		set_process(is_visible_in_tree())
		if is_visible_in_tree():
			back.grab_focus())
	set_process(false)
	_refresh()


func open() -> void:
	_refresh()
	show()


func _process(_delta: float) -> void:
	if _progress.visible:
		_progress.value = updater.download_progress() * 100.0


func _refresh() -> void:
	_status.text = updater.status
	_progress.visible = updater.state == Updater.State.DOWNLOADING
	_check.disabled = not updater.supported() or updater.busy()
	_install.visible = updater.state in [Updater.State.READY, Updater.State.INSTALLING]
	_install.disabled = updater.busy()


func _label(parent: Container, content: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = content
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func _button(parent: Container, caption: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = caption
	control.pressed.connect(action)
	parent.add_child(control)
	return control
