extends CanvasLayer
## Goldmend :: developer cheat console (toggle with F1 or ` / ~).

const M = preload("po_mat.gd")
const I18n = preload("po_i18n.gd")

var game: Node
var _panel: PanelContainer
var _checks := {}
var _status: Label


func _ready() -> void:
	layer = 20
	_build()


func _build() -> void:
	if _panel:
		_panel.queue_free()
	_checks.clear()
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 120)
	_panel.custom_minimum_size = Vector2(320, 0)
	var theme := Theme.new()
	theme.default_font = M.ui_font()
	theme.default_font_size = 15
	_panel.theme = theme
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.02, 0.06, 0.04, 0.94)
	sb.border_color = Color(0.3, 1.0, 0.55)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	var title := Label.new()
	title.text = I18n.s("c_title")
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	v.add_child(title)
	_button(v, I18n.s("c_win"), func(): game.cheat("win"))
	_button(v, I18n.s("c_kill"), func(): game.cheat("kill"))
	_check(v, "no_cd", I18n.s("c_nocd"), func(on): game.cheat_flag("no_cd", on))
	_check(v, "max_atb", I18n.s("c_maxatb"), func(on): game.cheat_flag("max_atb", on))
	_check(v, "auto", I18n.s("c_auto"), func(on): game.set_auto(on))
	var speeds := HBoxContainer.new()
	for m in [1, 2, 3]:
		var b := Button.new()
		b.text = I18n.s("c_speed", [m])
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): game.set_speed(m))
		speeds.add_child(b)
	v.add_child(speeds)
	_button(v, I18n.s("c_heal"), func(): game.cheat("heal"))
	_button(v, I18n.s("c_gold"), func(): game.cheat("gold"))
	_button(v, I18n.s("c_relic"), func(): game.cheat("relic"))
	_button(v, I18n.s("c_mend"), func(): game.cheat("mend"))
	_button(v, I18n.s("c_lang"), func(): game.toggle_language())
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(0.6, 0.9, 0.7))
	v.add_child(_status)
	_panel.add_child(v)
	add_child(_panel)
	_panel.visible = false


func rebuild() -> void:
	var was: bool = _panel.visible
	_build()
	_panel.visible = was


func _button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(_on_button.bind(cb, text))
	parent.add_child(b)


func _on_button(cb: Callable, text: String) -> void:
	cb.call()
	note(text)


func _check(parent: Node, key: String, text: String, cb: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(_on_check.bind(cb, text))
	parent.add_child(c)
	_checks[key] = c


func _on_check(on: bool, cb: Callable, text: String) -> void:
	cb.call(on)
	note("%s: %s" % [text, "ON" if on else "OFF"])


func sync(auto_on: bool) -> void:
	if _checks.has("auto"):
		_checks.auto.set_pressed_no_signal(auto_on)


func toggle() -> void:
	_panel.visible = not _panel.visible


func note(text: String) -> void:
	_status.text = "> " + text
