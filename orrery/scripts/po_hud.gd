extends CanvasLayer
## Goldmend :: battle HUD (bilingual).
## Everything is built in code: nameplates that follow units, turn-order
## forecast, skill bar with damage preview, team portraits, combat log,
## Element Fission legend, result screen and the Rune Board.

const Data = preload("po_data.gd")
const M = preload("po_mat.gd")
const I18n = preload("po_i18n.gd")

signal skill_pressed(index: int)
signal portrait_pressed(unit: Node)
signal auto_toggled
signal speed_pressed
signal console_pressed

const BRASS := Color(0.9, 0.7, 0.38)
const IVORY := Color(0.96, 0.94, 0.88)
const NAVY := Color(0.04, 0.04, 0.11, 0.88)
const ALLY_COL := Color(0.4, 0.8, 1.0)
const ENEMY_COL := Color(1.0, 0.38, 0.42)

var battle: Node
var root: Control
var _plates := {}       # unit -> {root, hp, atb, en, status}
var _portraits := {}    # unit -> {button, hp, en}
var _ally_row: VBoxContainer
var _enemy_row: HBoxContainer
var _order_row: HBoxContainer
var _skill_row: HBoxContainer
var _skill_buttons: Array = []
var _desc: RichTextLabel
var _desc_panel: PanelContainer
var _hint: Label
var _banner: Label
var _sub_banner: Label
var _log: RichTextLabel
var _wave_label: Label
var _auto_btn: Button
var _speed_btn: Button
var _legend: PanelContainer
var _relic_label: RichTextLabel


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = make_theme()
	add_child(root)
	_build_top()
	_build_bottom()
	_build_center()
	_build_legend()
	_no_focus(root)


## Buttons must not steal keyboard focus (Space / 1-3 are battle hotkeys).
func _no_focus(n: Node) -> void:
	for c in n.get_children():
		if c is BaseButton or c is ItemList:
			c.focus_mode = Control.FOCUS_NONE
		_no_focus(c)


# --- Theme -----------------------------------------------------------------------
static func _sb(bg: Color, border: Color, bw: int = 2, radius: int = 8, pad: int = 8) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = M.ui_font()
	t.default_font_size = 16
	var panel := _sb(NAVY, BRASS.darkened(0.2), 2, 10, 10)
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)
	t.set_stylebox("normal", "Button", _sb(Color(0.08, 0.07, 0.18, 0.95), BRASS.darkened(0.3), 2, 8, 8))
	t.set_stylebox("hover", "Button", _sb(Color(0.16, 0.12, 0.3, 0.98), BRASS, 2, 8, 8))
	t.set_stylebox("pressed", "Button", _sb(Color(0.3, 0.2, 0.1, 0.98), Color(1, 0.85, 0.5), 2, 8, 8))
	t.set_stylebox("disabled", "Button", _sb(Color(0.06, 0.06, 0.1, 0.8), Color(0.3, 0.3, 0.35), 2, 8, 8))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", IVORY)
	t.set_color("font_hover_color", "Button", Color(1, 0.9, 0.6))
	t.set_color("font_pressed_color", "Button", Color(1, 0.9, 0.6))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.5, 0.55))
	t.set_color("font_color", "Label", IVORY)
	t.set_color("font_outline_color", "Label", Color(0.02, 0.02, 0.06))
	t.set_constant("outline_size", "Label", 4)
	t.set_color("default_color", "RichTextLabel", IVORY)
	t.set_stylebox("panel", "ItemList", _sb(Color(0.03, 0.03, 0.08, 0.9), BRASS.darkened(0.4), 1, 6, 6))
	t.set_color("font_color", "ItemList", IVORY)
	t.set_stylebox("selected", "ItemList", _sb(Color(0.35, 0.25, 0.1, 0.9), BRASS, 1, 4, 2))
	t.set_stylebox("selected_focus", "ItemList", _sb(Color(0.35, 0.25, 0.1, 0.9), BRASS, 1, 4, 2))
	t.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	return t


func _label(text: String, size: int = 16, color: Color = IVORY) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(color: Color, height: float, back: Color = Color(0.05, 0.05, 0.1, 0.9)) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, height)
	b.max_value = 100.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = back
	bg.set_corner_radius_all(3)
	var fg := StyleBoxFlat.new()
	fg.bg_color = color
	fg.set_corner_radius_all(3)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


func _ignore_all(n: Node) -> void:
	for c in n.get_children():
		if c is Control:
			c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_all(c)


# --- Layout ------------------------------------------------------------------------
func _build_top() -> void:
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 12
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	var title_box := VBoxContainer.new()
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_box.add_child(_label(I18n.s("title_small"), 20, BRASS))
	_wave_label = _label("", 15)
	title_box.add_child(_wave_label)
	_relic_label = RichTextLabel.new()
	_relic_label.bbcode_enabled = true
	_relic_label.fit_content = true
	_relic_label.custom_minimum_size = Vector2(380, 0)
	_relic_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_relic_label.add_theme_font_size_override("normal_font_size", 13)
	title_box.add_child(_relic_label)
	top.add_child(title_box)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer)

	var order_panel := PanelContainer.new()
	order_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ob := HBoxContainer.new()
	ob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ob.add_theme_constant_override("separation", 6)
	ob.add_child(_label(I18n.s("turn_order"), 14, BRASS))
	_order_row = HBoxContainer.new()
	_order_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_order_row.add_theme_constant_override("separation", 4)
	ob.add_child(_order_row)
	order_panel.add_child(ob)
	top.add_child(order_panel)

	var spacer2 := Control.new()
	spacer2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(spacer2)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	btns.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_auto_btn = Button.new()
	_auto_btn.text = I18n.s("auto")
	_auto_btn.toggle_mode = true
	_auto_btn.pressed.connect(func(): auto_toggled.emit())
	_speed_btn = Button.new()
	_speed_btn.text = I18n.s("speed", [1])
	_speed_btn.pressed.connect(func(): speed_pressed.emit())
	var legend_btn := Button.new()
	legend_btn.text = I18n.s("legend")
	legend_btn.pressed.connect(func(): _legend.visible = not _legend.visible)
	var console_btn := Button.new()
	console_btn.text = I18n.s("console")
	console_btn.pressed.connect(func(): console_pressed.emit())
	for b in [_auto_btn, _speed_btn, legend_btn, console_btn]:
		btns.add_child(b)
	top.add_child(btns)

	_enemy_row = HBoxContainer.new()
	_enemy_row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_enemy_row.offset_top = 86
	_enemy_row.offset_right = -16
	_enemy_row.add_theme_constant_override("separation", 6)
	_enemy_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_enemy_row)


func _build_bottom() -> void:
	_ally_row = VBoxContainer.new()
	_ally_row.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_ally_row.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_ally_row.offset_left = 16
	_ally_row.offset_bottom = -16
	_ally_row.add_theme_constant_override("separation", 6)
	_ally_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_ally_row)

	var center := VBoxContainer.new()
	center.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	center.grow_horizontal = Control.GROW_DIRECTION_BOTH
	center.grow_vertical = Control.GROW_DIRECTION_BEGIN
	center.offset_bottom = -16
	center.alignment = BoxContainer.ALIGNMENT_END
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	_hint = _label("", 17, Color(1, 0.9, 0.6))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(_hint)
	_desc_panel = PanelContainer.new()
	_desc_panel.custom_minimum_size = Vector2(660, 0)
	_desc_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc = RichTextLabel.new()
	_desc.bbcode_enabled = true
	_desc.fit_content = true
	_desc.scroll_active = false
	_desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_desc.add_theme_font_size_override("normal_font_size", 15)
	_desc_panel.add_child(_desc)
	center.add_child(_desc_panel)
	_skill_row = HBoxContainer.new()
	_skill_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_skill_row.add_theme_constant_override("separation", 10)
	_skill_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_skill_row)
	for i in 3:
		var b := Button.new()
		b.custom_minimum_size = Vector2(210, 74)
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(func(): skill_pressed.emit(i))
		b.mouse_entered.connect(func(): _on_skill_hover(i))
		_skill_row.add_child(b)
		_skill_buttons.append(b)
	_desc_panel.visible = false
	_skill_row.visible = false

	var log_panel := PanelContainer.new()
	log_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	log_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	log_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	log_panel.offset_right = -16
	log_panel.offset_bottom = -16
	log_panel.custom_minimum_size = Vector2(360, 170)
	log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_font_size_override("normal_font_size", 13)
	log_panel.add_child(_log)
	root.add_child(log_panel)


func _build_center() -> void:
	_banner = _label("", 40, BRASS)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 150
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.modulate.a = 0.0
	root.add_child(_banner)
	_sub_banner = _label("", 20)
	_sub_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sub_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub_banner.offset_top = 205
	_sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_banner.modulate.a = 0.0
	root.add_child(_sub_banner)


func _build_legend() -> void:
	_legend = PanelContainer.new()
	_legend.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	_legend.grow_vertical = Control.GROW_DIRECTION_BOTH
	_legend.offset_left = 16
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.custom_minimum_size = Vector2(330, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_font_size_override("normal_font_size", 14)
	var c := func(e: int) -> String:
		return "[color=#%s]%s[/color]" % [Data.ELEMENT_COLORS[e].to_html(false), I18n.element(e)]
	var txt := "[color=#e6b35f][b]%s[/b][/color]\n%s\n" % [I18n.s("fission_title"), I18n.s("fission_intro")]
	var rows := [
		[[0, 2], "wildfire"], [[0, 1], "steam"], [[1, 2], "frost"],
		[[3, 4], "annihilate"], [[3, -1], "radiance"], [[4, -1], "corrode"],
	]
	for r in rows:
		var info: Dictionary = Data.REACTIONS[r[1]]
		var pair: String = c.call(r[0][0]) + "+" + (c.call(r[0][1]) if r[0][1] >= 0 else I18n.s("fission_other"))
		txt += "• %s → [b]%s[/b] %s\n" % [pair, I18n.f(info, "name"), I18n.f(info, "desc")]
	txt += I18n.s("affinity_line", [c.call(0), c.call(2), c.call(1), c.call(0), c.call(3), c.call(4)])
	t.text = txt
	_legend.add_child(t)
	_legend.visible = false
	root.add_child(_legend)


# --- Nameplates & portraits ------------------------------------------------------------
func setup_units(units: Array, relics: Array, floor_text: String = "") -> void:
	clear_units()
	_wave_label.text = floor_text
	var parts: Array = []
	for r in relics:
		var info: Dictionary = Data.RELICS[r]
		parts.append("[hint=%s][color=#%s]◆%s[/color][/hint]" % [I18n.f(info, "desc"), Data.RARITY_COLORS[int(info.rarity)].to_html(false), I18n.f(info, "name")])
	_relic_label.text = " ".join(parts)
	for u in units:
		_make_plate(u)
		_make_portrait(u)


func clear_units() -> void:
	for u in _plates:
		_plates[u].root.queue_free()
	for u in _portraits:
		_portraits[u].button.queue_free()
	_plates.clear()
	_portraits.clear()


func _make_plate(u: Node) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(150, 0)
	box.add_theme_constant_override("separation", 2)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 4)
	var el := _label(I18n.element(u.element), 14, Data.ELEMENT_COLORS[u.element])
	name_row.add_child(el)
	var seams := "" if u.mends <= 0 else " " + "◆".repeat(u.mends)
	var nm := _label("%s Lv%d%s%s" % [u.display_name, u.level, seams, I18n.s("boss_tag") if u.is_boss else ""], 13, IVORY)
	name_row.add_child(nm)
	box.add_child(name_row)
	var hp := _bar(ALLY_COL.lerp(Color(0.3, 1.0, 0.5), 0.5) if u.team == 0 else ENEMY_COL, 9)
	box.add_child(hp)
	var atb := _bar(Color(0.55, 0.85, 1.0), 4)
	box.add_child(atb)
	var en := _bar(Color(1.0, 0.75, 0.3), 4)
	box.add_child(en)
	var st := RichTextLabel.new()
	st.bbcode_enabled = true
	st.fit_content = true
	st.scroll_active = false
	st.autowrap_mode = TextServer.AUTOWRAP_OFF
	st.custom_minimum_size = Vector2(150, 0)
	st.add_theme_font_size_override("normal_font_size", 12)
	st.add_theme_constant_override("outline_size", 4)
	st.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	box.add_child(st)
	_ignore_all(box)
	root.add_child(box)
	root.move_child(box, 0)
	_plates[u] = {"root": box, "hp": hp, "atb": atb, "en": en, "status": st, "last_status": ""}


func _make_portrait(u: Node) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(186 if I18n.en() else 158, 62)
	b.clip_contents = true
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 8
	v.offset_right = -8
	v.offset_top = 6
	v.offset_bottom = -6
	v.add_theme_constant_override("separation", 3)
	var h := HBoxContainer.new()
	h.add_child(_label(I18n.element(u.element), 15, Data.ELEMENT_COLORS[u.element]))
	h.add_child(_label(u.display_name, 14))
	v.add_child(h)
	var hp := _bar(Color(0.35, 0.95, 0.5) if u.team == 0 else ENEMY_COL, 8)
	v.add_child(hp)
	var en := _bar(Color(1.0, 0.75, 0.3), 5)
	v.add_child(en)
	b.add_child(v)
	_ignore_all(b)
	b.pressed.connect(func(): portrait_pressed.emit(u))
	var border := ALLY_COL if u.team == 0 else ENEMY_COL
	b.add_theme_stylebox_override("normal", _sb(Color(0.05, 0.05, 0.12, 0.9), border.darkened(0.3), 2, 8, 4))
	b.add_theme_stylebox_override("hover", _sb(Color(0.12, 0.1, 0.25, 0.95), border, 2, 8, 4))
	(_ally_row if u.team == 0 else _enemy_row).add_child(b)
	_portraits[u] = {"button": b, "hp": hp, "en": en}


func update_units(cam: Camera3D) -> void:
	for u in _plates:
		if not is_instance_valid(u):
			continue
		var p: Dictionary = _plates[u]
		var box: Control = p.root
		var world: Vector3 = u.head_position()
		if not u.alive or cam.is_position_behind(world):
			box.visible = false
		else:
			box.visible = true
			var sp := cam.unproject_position(world)
			box.position = sp - Vector2(75, box.size.y)
		p.hp.value = u.hp_ratio() * 100.0
		p.atb.value = minf(u.atb, 100.0)
		p.en.value = u.energy
		var s := _status_bbcode(u)
		if s != p.last_status:
			p.status.text = s
			p.last_status = s
	for u in _portraits:
		if not is_instance_valid(u):
			continue
		var q: Dictionary = _portraits[u]
		q.hp.value = u.hp_ratio() * 100.0
		q.en.value = u.energy
		q.button.modulate = Color(1, 1, 1, 1) if u.alive else Color(0.45, 0.45, 0.5, 0.7)


func _status_bbcode(u: Node) -> String:
	var parts: Array = []
	if u.mark >= 0:
		parts.append("[bgcolor=#%s][color=#000000] %s [/color][/bgcolor]" % [Data.ELEMENT_COLORS[u.mark].to_html(false), I18n.s("mark", [I18n.element(u.mark)])])
	for s in u.statuses:
		var info: Dictionary = Data.STATUS[s.id]
		parts.append("[color=#%s]%s%d[/color]" % [info.color.to_html(false), I18n.f(info, "label"), s.turns])
	if u.ultimate_ready():
		parts.append("[color=#ffc850]%s[/color]" % I18n.s("ultimate_ready"))
	return " ".join(parts)


# --- Turn order ----------------------------------------------------------------------
func update_turn_order(order: Array) -> void:
	for c in _order_row.get_children():
		c.queue_free()
	for i in order.size():
		var u = order[i]
		var chip := PanelContainer.new()
		var border := ALLY_COL if u.team == 0 else ENEMY_COL
		chip.add_theme_stylebox_override("panel", _sb(Data.ELEMENT_COLORS[u.element].darkened(0.55), border, 2 if i > 0 else 3, 6, 3))
		var l := _label(u.display_name.substr(0, 5 if I18n.en() else 2), 13 if i > 0 else 15)
		chip.add_child(l)
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_order_row.add_child(chip)


# --- Skills ---------------------------------------------------------------------------
func show_skills(u: Node, selected: int, cd_free: bool) -> void:
	_skill_row.visible = true
	_desc_panel.visible = true
	for i in 3:
		var sk: Dictionary = u.skills[i]
		var b: Button = _skill_buttons[i]
		var sub := ""
		var ok := true
		if i == 2:
			sub = I18n.s("ult_energy", [int(u.energy), int(u.ult_cost)])
			ok = u.ultimate_ready() or cd_free
		elif int(u.cooldowns[i]) > 0 and not cd_free:
			sub = I18n.s("on_cd", [int(u.cooldowns[i])])
			ok = false
		else:
			sub = I18n.s("basic") if i == 0 else I18n.s("ready_cd", [int(sk.cd)])
		b.text = "%d  %s\n%s" % [i + 1, I18n.f(sk, "name"), sub]
		b.disabled = not ok
		var col: Color = Data.ELEMENT_COLORS[u.element]
		if i == selected:
			b.add_theme_stylebox_override("normal", _sb(Color(0.25, 0.18, 0.08, 0.98), Color(1, 0.85, 0.45), 3, 8, 8))
		elif i == 2 and ok:
			b.add_theme_stylebox_override("normal", _sb(col.darkened(0.6), col, 3, 8, 8))
		else:
			b.remove_theme_stylebox_override("normal")
	_set_desc(u, selected)


func _on_skill_hover(i: int) -> void:
	if battle and battle.has_method("hud_current_unit"):
		var u = battle.hud_current_unit()
		if u:
			_set_desc(u, i)


func _set_desc(u: Node, i: int) -> void:
	var sk: Dictionary = u.skills[i]
	var tgt := I18n.s("target_" + String(sk.target))
	_desc.text = "[color=#e6b35f][b]%s[/b][/color]  [color=#9aa]%s[/color]\n%s\n[color=#8fb8ff]%s · %s：[/color]%s" % [
		I18n.f(sk, "name"), tgt, I18n.f(sk, "desc"), I18n.s("passive"), I18n.f(u.species.passive, "name"), I18n.f(u.species.passive, "desc")]


func set_preview(text: String) -> void:
	if text == "":
		return
	_desc.text = text


func hide_skills() -> void:
	_skill_row.visible = false
	_desc_panel.visible = false
	_hint.text = ""


func set_hint(text: String) -> void:
	_hint.text = text


func set_auto(on: bool) -> void:
	_auto_btn.button_pressed = on
	_auto_btn.text = I18n.s("auto_on") if on else I18n.s("auto")


func set_speed(mult: int) -> void:
	_speed_btn.text = I18n.s("speed", [mult])


# --- Banners & log -------------------------------------------------------------------
func banner(text: String, color: Color = BRASS, sub: String = "") -> void:
	_banner.text = text
	_banner.add_theme_color_override("font_color", color)
	_banner.scale = Vector2.ONE * 1.3
	_banner.pivot_offset = _banner.size * 0.5
	var t := create_tween()
	t.tween_property(_banner, "modulate:a", 1.0, 0.12)
	t.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK)
	t.tween_interval(0.8)
	t.tween_property(_banner, "modulate:a", 0.0, 0.35)
	_sub_banner.text = sub
	var t2 := create_tween()
	t2.tween_property(_sub_banner, "modulate:a", 1.0 if sub != "" else 0.0, 0.12)
	t2.tween_interval(0.9)
	t2.tween_property(_sub_banner, "modulate:a", 0.0, 0.35)


func log_line(text: String) -> void:
	_log.append_text(text + "\n")


func clear_log() -> void:
	_log.clear()
