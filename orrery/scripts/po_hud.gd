extends CanvasLayer
## Goldmend :: battle HUD (bilingual, icon-first).
## Three layers of information:
##   1. always on screen: icons, bars and numbers only
##   2. on hover: skill details, damage preview, status and unit info (tooltip)
##   3. on demand: rules page (Five Phases, crack, chains, traits, controls) and the combat log

const Data = preload("po_data.gd")
const M = preload("po_mat.gd")
const I18n = preload("po_i18n.gd")
const Icons = preload("po_icons.gd")
const Tip = preload("po_tip.gd")

signal skill_pressed(index: int)
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
var _plates := {}       # unit -> {root, hp, shield, crack, atb, en, status, intent, key}
var _order_row: HBoxContainer
var _skill_buttons: Array = []
var _skill_cd: Array = []
var _skill_ring: Array = []
var _banner: Label
var _sub_banner: Label
var _log_panel: PanelContainer
var _log: RichTextLabel
var _floor_label: Label
var _relic_row: HBoxContainer
var _trait_row: HBoxContainer
var _enemy_trait_row: HBoxContainer
var _auto_btn: Button
var _speed_btn: Button
var _rules: PanelContainer
var _tip: Tip
var _skill_bar: HBoxContainer
var _current: Node = null


func _ready() -> void:
	layer = 5
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = make_theme()
	add_child(root)
	_build_tip()
	_build_top()
	_build_skill_bar()
	_build_banner()
	_build_log()
	_build_rules()
	root.move_child(_tip, root.get_child_count() - 1)


# --- Theme -----------------------------------------------------------------------------
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
	t.set_stylebox("panel", "TooltipPanel", _sb(Color(0.03, 0.03, 0.09, 0.96), BRASS, 1, 8, 8))
	t.set_color("font_color", "TooltipLabel", IVORY)
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


func _icon(tex: Texture2D, size: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Round icon button with a hover tip.
func _icon_button(tex: Texture2D, tip: Callable, size: float = 46.0) -> Button:
	var b := Button.new()
	b.icon = tex
	b.expand_icon = true
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	var r := int(size / 2.0)
	b.add_theme_stylebox_override("normal", _sb(Color(0.06, 0.06, 0.15, 0.9), BRASS.darkened(0.3), 2, r, 6))
	b.add_theme_stylebox_override("hover", _sb(Color(0.16, 0.12, 0.3, 0.98), BRASS, 2, r, 6))
	b.add_theme_stylebox_override("pressed", _sb(Color(0.3, 0.2, 0.1, 0.98), Color(1, 0.85, 0.5), 2, r, 6))
	_hover(b, tip)
	return b


# --- Tooltip ---------------------------------------------------------------------------------
func _build_tip() -> void:
	_tip = Tip.new()
	root.add_child(_tip)


func show_tip(text: String, owner: Object = null) -> void:
	_tip.show_text(text, owner)


func hide_tip(owner: Object = null) -> void:
	_tip.hide_for(owner)


func _hover(c: Control, text_fn: Callable) -> void:
	_tip.attach(c, text_fn)


# --- Layout ----------------------------------------------------------------------------------
func _build_top() -> void:
	var left := VBoxContainer.new()
	left.position = Vector2(18, 12)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor_label = _label("", 17, BRASS)
	left.add_child(_floor_label)
	_relic_row = HBoxContainer.new()
	_relic_row.add_theme_constant_override("separation", 4)
	left.add_child(_relic_row)
	_trait_row = HBoxContainer.new()
	_trait_row.add_theme_constant_override("separation", 4)
	left.add_child(_trait_row)
	root.add_child(left)
	_enemy_trait_row = HBoxContainer.new()
	_enemy_trait_row.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_enemy_trait_row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_enemy_trait_row.offset_right = -18
	_enemy_trait_row.offset_top = 70
	_enemy_trait_row.add_theme_constant_override("separation", 4)
	root.add_child(_enemy_trait_row)

	var order_panel := PanelContainer.new()
	order_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	order_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	order_panel.offset_top = 10
	order_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	order_panel.add_theme_stylebox_override("panel", _sb(Color(0.03, 0.03, 0.09, 0.7), BRASS.darkened(0.4), 1, 30, 6))
	_order_row = HBoxContainer.new()
	_order_row.add_theme_constant_override("separation", 6)
	_order_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	order_panel.add_child(_order_row)
	root.add_child(order_panel)

	var btns := HBoxContainer.new()
	btns.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	btns.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	btns.offset_right = -16
	btns.offset_top = 12
	btns.add_theme_constant_override("separation", 8)
	_auto_btn = _icon_button(Icons.tex("auto"), func(): return "[b]%s[/b]" % I18n.s("auto"))
	_auto_btn.toggle_mode = true
	_auto_btn.pressed.connect(func(): auto_toggled.emit())
	_speed_btn = _icon_button(Icons.tex("speed"), func(): return "[b]%s[/b]" % I18n.s("speed", [int(Engine.time_scale)]))
	_speed_btn.pressed.connect(func(): speed_pressed.emit())
	var rules := _icon_button(Icons.tex("book"), func(): return "[b]%s[/b]" % I18n.s("legend"))
	rules.pressed.connect(func(): _rules.visible = not _rules.visible)
	var log_btn := _icon_button(Icons.tex("scroll"), func(): return "[b]%s[/b]" % I18n.s("log"))
	log_btn.pressed.connect(func(): _log_panel.visible = not _log_panel.visible)
	var console_btn := _icon_button(Icons.tex("gear"), func(): return "[b]%s[/b]" % I18n.s("console"))
	console_btn.pressed.connect(func(): console_pressed.emit())
	for b in [_auto_btn, _speed_btn, rules, log_btn, console_btn]:
		btns.add_child(b)
	root.add_child(btns)


func _build_skill_bar() -> void:
	_skill_bar = HBoxContainer.new()
	_skill_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_skill_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_skill_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_skill_bar.offset_bottom = -24
	_skill_bar.add_theme_constant_override("separation", 18)
	_skill_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_skill_bar)
	for i in 3:
		var size := 96.0 if i == 2 else 84.0
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(size, size)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var b := Button.new()
		b.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.expand_icon = true
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): skill_pressed.emit(i))
		_hover(b, _skill_tip.bind(i))
		holder.add_child(b)
		# energy ring around the ultimate
		var ring := TextureProgressBar.new()
		ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		ring.texture_progress = Icons.tex("ring", Color(0, 0, 0, 0), int(size), "#ffc850")
		ring.fill_mode = TextureProgressBar.FILL_CLOCKWISE
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.visible = i == 2
		holder.add_child(ring)
		var cd := _label("", 34, IVORY)
		cd.set_anchors_preset(Control.PRESET_FULL_RECT)
		cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cd.add_theme_constant_override("outline_size", 10)
		holder.add_child(cd)
		var key := _label(str(i + 1), 13, BRASS)
		key.position = Vector2(4, -2)
		holder.add_child(key)
		_skill_bar.add_child(holder)
		_skill_buttons.append(b)
		_skill_cd.append(cd)
		_skill_ring.append(ring)
	_skill_bar.visible = false


func _build_banner() -> void:
	_banner = _label("", 40, BRASS)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.offset_top = 130
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_constant_override("outline_size", 10)
	_banner.modulate.a = 0.0
	root.add_child(_banner)
	_sub_banner = _label("", 18)
	_sub_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sub_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sub_banner.offset_top = 184
	_sub_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub_banner.modulate.a = 0.0
	root.add_child(_sub_banner)


func _build_log() -> void:
	_log_panel = PanelContainer.new()
	_log_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_log_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_log_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_log_panel.offset_right = -16
	_log_panel.offset_bottom = -16
	_log_panel.custom_minimum_size = Vector2(360, 200)
	_log_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log_panel.add_child(_log)
	_log_panel.visible = false
	root.add_child(_log_panel)


## Rules page: Five Phases wheel, crack & break, chains, intents, statuses and controls.
func _build_rules() -> void:
	_rules = PanelContainer.new()
	_rules.set_anchors_preset(Control.PRESET_CENTER)
	_rules.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_rules.grow_vertical = Control.GROW_DIRECTION_BOTH
	_rules.add_theme_stylebox_override("panel", _sb(Color(0.03, 0.03, 0.09, 0.96), BRASS, 2, 14, 18))
	var t := RichTextLabel.new()
	t.bbcode_enabled = true
	t.fit_content = true
	t.custom_minimum_size = Vector2(700, 0)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.add_theme_font_size_override("normal_font_size", 15)
	_rules_text(t)
	_rules.add_child(t)
	_rules.visible = false
	root.add_child(_rules)


static func element_bb(e: int) -> String:
	return "[color=#%s]%s[/color]" % [Data.ELEMENT_COLORS[e].to_html(false), I18n.element(e)]


## Shared by the battle rules page and the title-screen guide.
static func _rules_text(t: RichTextLabel) -> void:
	var E := Data.Element
	t.append_text("[color=#e6b35f][b]%s[/b][/color]\n" % I18n.s("rules_wuxing_title"))
	for e in 5:
		t.add_image(Icons.element(e, 40), 20, 20)
		t.append_text(" %s %s   " % [element_bb(e), Data.ELEMENT_CRAFT[e].en if I18n.en() else Data.ELEMENT_CRAFT[e].zh])
		if e == 2:
			t.append_text("\n")
	t.append_text("\n" + I18n.s("rules_ke", [element_bb(E.METAL), element_bb(E.WOOD), element_bb(E.EARTH), element_bb(E.WATER), element_bb(E.FIRE)]))
	t.append_text("\n" + I18n.s("rules_sheng", [element_bb(E.WOOD), element_bb(E.FIRE), element_bb(E.EARTH), element_bb(E.METAL), element_bb(E.WATER)]))
	t.append_text("\n\n[color=#e6b35f][b]%s[/b][/color]\n%s\n" % [I18n.s("rules_crack_title"), I18n.s("rules_crack")])
	for e in 5:
		var be: Dictionary = Data.BREAK_EFFECTS[e]
		t.append_text("  %s [b]%s[/b] %s\n" % [element_bb(e), I18n.f(be, "name"), I18n.f(be, "desc")])
	t.append_text("\n[color=#e6b35f][b]%s[/b][/color]\n%s\n" % [I18n.s("rules_chain_title"), I18n.s("rules_chain")])
	t.append_text("\n[color=#e6b35f][b]%s[/b][/color]\n%s\n" % [I18n.s("rules_intent_title"), I18n.s("rules_intent")])
	t.append_text("\n[color=#e6b35f][b]%s[/b][/color]\n" % I18n.s("statuses"))
	for id in Data.STATUS:
		var info: Dictionary = Data.STATUS[id]
		t.add_image(Icons.status(id, info.color, 44), 22, 22)
		t.append_text(" [color=#%s]%s[/color]  " % [info.color.to_html(false), I18n.f(info, "name")])
	t.append_text("\n\n[color=#e6b35f][b]%s[/b][/color]\n%s" % [I18n.s("controls"), I18n.s("battle_hint")])


# --- Nameplates ------------------------------------------------------------------------------
func setup_units(units: Array, relics: Array, floor_text: String = "", traits: Array = [{}, {}]) -> void:
	clear_units()
	_floor_label.text = floor_text
	for row in [_trait_row, _enemy_trait_row]:
		for c in row.get_children():
			c.queue_free()
	for team in 2:
		for tid in Data.TRAIT_ORDER:
			if traits[team].has(tid):
				var ic := trait_icon(tid, int(traits[team][tid]), 30, team == 1)
				(_trait_row if team == 0 else _enemy_trait_row).add_child(ic)
	for c in _relic_row.get_children():
		c.queue_free()
	for r in relics:
		var info: Dictionary = Data.RELICS[r]
		var ic := _icon(Icons.tex("shard", Data.RARITY_COLORS[int(info.rarity)].darkened(0.45), 40), 30)
		ic.mouse_filter = Control.MOUSE_FILTER_STOP
		_hover(ic, func(): return "[color=#%s][b]◆ %s[/b][/color]\n%s" % [Data.RARITY_COLORS[int(info.rarity)].to_html(false), I18n.f(info, "name"), I18n.f(info, "desc")])
		_relic_row.add_child(ic)
	for u in units:
		_make_plate(u)


## Trait badge: glyph on a disc, tier pips, tooltip with every tier.
func trait_icon(tid: String, tier: int, size: float, enemy: bool = false) -> Control:
	var col := Color(0.55, 0.2, 0.22) if enemy else Color(0.42, 0.3, 0.12)
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(_icon(Icons.tex(Icons.TRAIT_ICON.get(tid, "ring"), col, 48), size))
	var n := _label("%d" % (tier + 1), 11, Color(1.0, 0.85, 0.45))
	n.position = Vector2(size - 9, size - 14)
	n.add_theme_constant_override("outline_size", 4)
	holder.add_child(n)
	_hover(holder, func(): return trait_tip(tid, tier))
	return holder


static func trait_tip(tid: String, tier: int) -> String:
	var info: Dictionary = Data.TRAITS[tid]
	var t := "[color=#e6b35f][b]%s[/b][/color]" % I18n.f(info, "name")
	var descs: Array = info.desc_en if I18n.en() else info.desc
	for i in info.tiers.size():
		var on: bool = i <= tier
		t += "\n[color=#%s](%d) %s[/color]" % ["ffe6a0" if on else "777788", int(info.tiers[i]), descs[i]]
	return t


func clear_units() -> void:
	for u in _plates:
		_plates[u].root.queue_free()
	_plates.clear()


func _make_plate(u: Node) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.custom_minimum_size = Vector2(118, 0)
	box.add_theme_constant_override("separation", 2)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 3)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(_icon(Icons.element(u.element, 40), 18))
	if u.is_boss:
		top.add_child(_icon(Icons.tex("crown", Color(0, 0, 0, 0), 40, "#ffc850"), 18))
	for i in u.mends:
		top.add_child(_icon(Icons.tex("seam", Color(0, 0, 0, 0), 32, "#ffc850"), 12))
	var hp := _bar(Color(0.35, 0.95, 0.5) if u.team == 0 else ENEMY_COL, 9)
	hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# gold shield overlays the HP bar
	var shield := _bar(Color(1.0, 0.8, 0.3, 0.85), 9, Color(0, 0, 0, 0))
	shield.set_anchors_preset(Control.PRESET_FULL_RECT)
	hp.add_child(shield)
	top.add_child(hp)
	box.add_child(top)
	# crack gauge (裂纹): fills toward toughness; flashes when broken
	var crack := _bar(Color(0.95, 0.93, 0.85), 4, Color(0.12, 0.1, 0.16, 0.9))
	box.add_child(crack)
	var atb := _bar(Color(0.55, 0.85, 1.0), 3)
	box.add_child(atb)
	var en := _bar(Color(1.0, 0.75, 0.3), 3)
	box.add_child(en)
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 1)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	status.custom_minimum_size = Vector2(0, 20)
	box.add_child(status)
	# enemy intent: what it will do next, and to whom
	var intent := HBoxContainer.new()
	intent.add_theme_constant_override("separation", 2)
	intent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(intent)
	box.move_child(intent, 0)
	root.add_child(box)
	root.move_child(box, 0)
	_plates[u] = {"root": box, "hp": hp, "shield": shield, "crack": crack, "atb": atb, "en": en, "status": status, "intent": intent, "key": "", "ikey": ""}


func update_units(cam: Camera3D) -> void:
	for u in _plates:
		if not is_instance_valid(u):
			continue
		var p: Dictionary = _plates[u]
		var box: Control = p.root
		var world: Vector3 = u.head_position()
		if not u.alive or cam.is_position_behind(world):
			box.visible = false
			continue
		box.visible = true
		box.position = cam.unproject_position(world) - Vector2(59, box.size.y)
		p.hp.value = u.hp_ratio() * 100.0
		p.shield.value = u.shield / u.max_hp * 100.0
		p.crack.value = u.crack_ratio() * 100.0
		var crack_fill: StyleBoxFlat = p.crack.get_theme_stylebox("fill")
		if u.broken:
			crack_fill.bg_color = Color(1.0, 0.35, 0.3).lerp(Color(1, 0.85, 0.4), 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012))
		else:
			crack_fill.bg_color = Color(0.95, 0.93, 0.85).lerp(Color(1.0, 0.55, 0.3), u.crack_ratio())
		p.atb.value = minf(u.atb, 100.0)
		p.en.value = u.energy / u.ult_cost * 100.0
		var key := "%s|%s|%s" % [u.broken, str(u.statuses), u.ultimate_ready()]
		if key != p.key:
			p.key = key
			_fill_status(p.status, u)
		var it: Dictionary = u.intent
		var ikey := "" if it.is_empty() else "%d|%s" % [int(it.skill), str(it.target.get_instance_id()) if is_instance_valid(it.target) else ""]
		if ikey != p.ikey:
			p.ikey = ikey
			_fill_intent(p.intent, u)


## Intent row above an enemy plate: skill-kind icon (+ target portrait for single-target moves).
func _fill_intent(row: HBoxContainer, u: Node) -> void:
	for c in row.get_children():
		c.queue_free()
	var it: Dictionary = u.intent
	if it.is_empty():
		return
	var i := int(it.skill)
	var sk: Dictionary = u.skills[i]
	var glyph := "intent_attack"
	if i == 2:
		glyph = "ult"
	elif sk.target == "all_enemies":
		glyph = "intent_aoe"
	elif sk.target == "all_allies":
		glyph = "intent_buff"
	var col := Color(0.7, 0.15, 0.15) if i > 0 else Color(0.3, 0.12, 0.14)
	row.add_child(_icon(Icons.tex(glyph, col, 48, "#ffe6c0"), 26 if i > 0 else 20))
	if sk.target == "enemy" and is_instance_valid(it.target):
		row.add_child(_icon(Icons.tex("speed", Color(0, 0, 0, 0), 32, "#ffb0a0"), 12))
		row.add_child(_icon(Icons.portrait(it.target.species_id, it.target.element, 48), 22))


## Status row: broken / shield first, then one icon per status with its turns as a badge.
func _fill_status(row: HBoxContainer, u: Node) -> void:
	for c in row.get_children():
		c.queue_free()
	if u.broken:
		row.add_child(_icon(Icons.tex("broken", Color(0.7, 0.2, 0.15), 40), 20))
	for s in u.statuses:
		var info: Dictionary = Data.STATUS[s.id]
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(20, 20)
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(_icon(Icons.status(s.id, info.color, 40), 20))
		var n := _label(str(s.turns), 11, IVORY)
		n.position = Vector2(12, 6)
		n.add_theme_constant_override("outline_size", 4)
		holder.add_child(n)
		row.add_child(holder)
	if u.ultimate_ready():
		row.add_child(_icon(Icons.tex("ult", Color(0, 0, 0, 0), 40, "#ffc850"), 18))


## One-line summary of a unit, shown when hovering it.
func unit_tip(u: Node) -> String:
	var t := "[color=#%s][b]%s[/b][/color]  Lv%d" % [Data.ELEMENT_COLORS[u.element].to_html(false), u.display_name, u.level]
	t += "\n%d / %d" % [int(u.hp), int(u.max_hp)]
	if u.shield > 0.0:
		t += "  [color=#ffd060]+%d[/color]" % int(u.shield)
	t += "\n" + (I18n.s("tip_broken") if u.broken else I18n.s("tip_crack", [int(u.crack), int(u.toughness)]))
	if not u.intent.is_empty():
		var sk: Dictionary = u.skills[int(u.intent.skill)]
		var tgt: String = u.intent.target.display_name if (sk.target == "enemy" and is_instance_valid(u.intent.target)) else I18n.s("target_" + String(sk.target))
		t += "\n" + I18n.s("tip_intent", [I18n.f(sk, "name"), tgt])
	for s in u.statuses:
		var info: Dictionary = Data.STATUS[s.id]
		t += "\n[color=#%s]%s[/color] ×%d" % [info.color.to_html(false), I18n.f(info, "name"), s.turns]
	for sc in u.scars:
		t += "\n[color=#ffc860]◆ %s[/color] %s" % [I18n.f(Data.SCARS[sc], "name"), I18n.f(Data.SCARS[sc], "desc")]
	t += "\n[color=#8fb8ff]%s[/color] %s" % [I18n.f(u.species.passive, "name"), I18n.f(u.species.passive, "desc")]
	for uid in u.upgrades:
		t += "\n[color=#ffc860]✦ %s[/color]" % I18n.f(Data.upgrade_info(u.species_id, uid), "name")
	return t


# --- Turn order ----------------------------------------------------------------------------
## Forecast of the next actors; a gold link badge marks actions that will be 相生 chain links.
func update_turn_order(order: Array, chains: Array = []) -> void:
	for c in _order_row.get_children():
		c.queue_free()
	for i in order.size():
		var u = order[i]
		var size := 46.0 if i == 0 else 34.0
		var holder := PanelContainer.new()
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var border := ALLY_COL if u.team == 0 else ENEMY_COL
		var link: int = int(chains[i]) if i < chains.size() else 0
		if link > 0:
			border = Color(1.0, 0.82, 0.35)
		holder.add_theme_stylebox_override("panel", _sb(Color(0, 0, 0, 0), border, 3 if (i == 0 or link > 0) else 2, int(size / 2.0) + 3, 1))
		var inner := Control.new()
		inner.custom_minimum_size = Vector2(size, size)
		inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inner.add_child(_icon(Icons.portrait(u.species_id, u.element, 64), size))
		if link > 0:
			var badge := _icon(Icons.tex("chain", Color(0.45, 0.3, 0.05), 32), 16)
			badge.position = Vector2(size - 14, -4)
			inner.add_child(badge)
			var n := _label(str(link), 11, Color(1.0, 0.9, 0.5))
			n.position = Vector2(size - 10, size - 14)
			n.add_theme_constant_override("outline_size", 4)
			inner.add_child(n)
		holder.add_child(inner)
		_order_row.add_child(holder)


# --- Skills -----------------------------------------------------------------------------------
func show_skills(u: Node, selected: int, cd_free: bool) -> void:
	_current = u
	_skill_bar.visible = true
	for i in 3:
		var sk: Dictionary = u.skills[i]
		var b: Button = _skill_buttons[i]
		var col: Color = Data.ELEMENT_COLORS[u.element]
		b.icon = Icons.tex(Icons.skill_kind(sk, i), col.darkened(0.45) if i != 2 else col.darkened(0.25), 96)
		var ok := true
		var cd_text := ""
		if i == 2:
			ok = u.ultimate_ready() or cd_free
			_skill_ring[i].value = minf(u.energy / u.ult_cost, 1.0) * 100.0
		elif int(u.cooldowns[i]) > 0 and not cd_free:
			ok = false
			cd_text = str(int(u.cooldowns[i]))
		b.disabled = not ok
		b.modulate = Color(1, 1, 1) if ok else Color(0.55, 0.55, 0.6)
		_skill_cd[i].text = cd_text
		var r := 48 if i == 2 else 42
		var border := Color(1, 0.88, 0.5) if i == selected else (col if i == 2 and ok else BRASS.darkened(0.35))
		var bw := 4 if i == selected else 2
		for st in ["normal", "hover", "disabled"]:
			b.add_theme_stylebox_override(st, _sb(Color(0.05, 0.05, 0.12, 0.92), border, bw, r, 4))
	# keep an open skill tip in sync with the newly selected skill
	for i in 3:
		if _tip.owned_by(_skill_buttons[i]):
			show_tip(_skill_tip(i), _skill_buttons[i])


func _skill_tip(i: int) -> String:
	var u := _current
	if u == null or not is_instance_valid(u):
		return ""
	var sk: Dictionary = u.skills[i]
	var tgt := I18n.s("target_" + String(sk.target))
	var cost := ""
	if i == 2:
		cost = I18n.s("ult_energy", [int(u.energy), int(u.ult_cost)])
	elif int(sk.cd) > 0:
		cost = I18n.s("cd_turns", [int(sk.cd)])
	return "[color=#e6b35f][b]%s[/b][/color]  [color=#9aa]%s · %s[/color]\n%s" % [I18n.f(sk, "name"), tgt, cost, I18n.f(sk, "desc")]


func hide_skills() -> void:
	_skill_bar.visible = false
	for b in _skill_buttons:
		hide_tip(b)


func set_hint(_text: String) -> void:
	pass


func set_auto(on: bool) -> void:
	_auto_btn.button_pressed = on
	_auto_btn.modulate = Color(1.0, 0.85, 0.45) if on else Color.WHITE


func set_speed(mult: int) -> void:
	_speed_btn.modulate = [Color.WHITE, Color(0.7, 0.95, 1.0), Color(1.0, 0.8, 0.45)][clampi(mult, 1, 3) - 1]


# --- Banners & log -------------------------------------------------------------------------
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
