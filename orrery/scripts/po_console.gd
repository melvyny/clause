extends CanvasLayer
## Porcelain Orrery :: developer cheat console (toggle with F1 or ` / ~).

const M = preload("po_mat.gd")

var battle: Node
var _panel: PanelContainer
var _checks := {}
var _status: Label


func _ready() -> void:
	layer = 20
	_panel = PanelContainer.new()
	_panel.position = Vector2(16, 90)
	_panel.custom_minimum_size = Vector2(300, 0)
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
	title.text = "▣ DEV CONSOLE  (F1 / ~)"
	title.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
	v.add_child(title)

	_button(v, "瞬间获胜 Win Battle Instantly", func(): battle.cheat_win())
	_button(v, "击杀全部敌人 Kill All Enemies", func(): battle.cheat_kill_all())
	_check(v, "no_cd", "无限冷却 + 满灵力 Infinite Cooldowns", func(on): battle.cheat_no_cd = on)
	_check(v, "max_atb", "我方满攻击条 Max ATB Always", func(on): battle.cheat_max_atb = on)
	_check(v, "auto", "自动战斗 AI Auto-Battle", func(on): battle.set_auto(on))
	var speeds := HBoxContainer.new()
	for m in [1, 2, 3]:
		var b := Button.new()
		b.text = "%dx 倍速" % m
		b.pressed.connect(func(): battle.set_speed(m))
		speeds.add_child(b)
	v.add_child(speeds)
	_button(v, "我方全体回满 Heal Team", func(): battle.cheat_heal())
	_button(v, "获得5个传说符文 +5 Legend Runes", func(): battle.cheat_runes())
	_button(v, "+3 召唤卷轴 Summoning Scrolls", func(): battle.cheat_scrolls())
	_button(v, "重置存档 Reset Save", func(): battle.cheat_reset())
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color(0.6, 0.9, 0.7))
	v.add_child(_status)
	_panel.add_child(v)
	add_child(_panel)
	_panel.visible = false


func _button(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(func():
		cb.call()
		note(text))
	parent.add_child(b)


func _check(parent: Node, key: String, text: String, cb: Callable) -> void:
	var c := CheckButton.new()
	c.text = text
	c.toggled.connect(func(on):
		cb.call(on)
		note("%s: %s" % [text, "ON" if on else "OFF"]))
	parent.add_child(c)
	_checks[key] = c


func sync(auto_on: bool) -> void:
	_checks.auto.set_pressed_no_signal(auto_on)


func toggle() -> void:
	_panel.visible = not _panel.visible


func note(text: String) -> void:
	_status.text = "> " + text
