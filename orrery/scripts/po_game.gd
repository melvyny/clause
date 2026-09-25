extends Node
## Goldmend :: game flow (main scene script).
## Title -> choose starters -> porcelain-plate map -> nodes (battle, elite,
## kiln, mending hall, shop, encounter) -> The Unmended -> run summary.
##
## Command-line (after `--`):
##   --gm-autotest              plays a whole run with the AI, prints a summary, quits
##   --gm-demo=<screen>         jump to title|map|battle|mend|reward (for screenshots)
##   --gm-shot=<path.png>       save a screenshot after --gm-shot-delay=<sec>, then quit
##   --gm-lang=<zh|en>          force the language
##   --gm-sim[=N]               balance simulation: N fast battles per floor & starter, prints a table, quits

const Data = preload("po_data.gd")
const I18n = preload("po_i18n.gd")
const M = preload("po_mat.gd")
const Run = preload("po_run.gd")
const MapScene = preload("po_map.gd")
const Battle = preload("po_battle.gd")
const HUD = preload("po_hud.gd")
const Audio = preload("po_audio.gd")
const Console = preload("po_console.gd")
const Codex = preload("po_codex.gd")
const Icons = preload("po_icons.gd")
const Tip = preload("po_tip.gd")

const BRASS := Color(0.9, 0.7, 0.38)
const IVORY := Color(0.96, 0.94, 0.88)

var run := Run.new()
var audio: Node
var console: CanvasLayer
var world: Node3D
var ui_layer: CanvasLayer
var ui: Control
var map: Node3D
var battle: Node3D
var auto_battle := false
var speed := 1
var cheats := {"no_cd": false, "max_atb": false}
var _busy := false
var _screen: Callable
var _autotest := false
var _args: PackedStringArray
var tip: Tip


func _ready() -> void:
	I18n.load_settings()
	_args = OS.get_cmdline_user_args()
	for a in _args:
		if a.begins_with("--gm-lang="):
			I18n.lang = a.get_slice("=", 1)
	_autotest = "--gm-autotest" in _args
	audio = Audio.new()
	add_child(audio)
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 10
	add_child(ui_layer)
	_add_vignette()
	console = Console.new()
	console.game = self
	add_child(console)
	var tip_layer := CanvasLayer.new()
	tip_layer.layer = 30
	add_child(tip_layer)
	tip = Tip.new()
	tip_layer.add_child(tip)
	if _autotest:
		audio.muted = true
		auto_battle = true
		Engine.time_scale = 10.0
		get_tree().create_timer(600.0, true, false, true).timeout.connect(func():
			printerr("AUTOTEST TIMEOUT")
			get_tree().quit(1))
	_setup_screenshot()
	for a in _args:
		if a.begins_with("--gm-sim"):
			audio.muted = true
			_simulate.call_deferred(int(a.get_slice("=", 1)) if "=" in a else 20)
			return
	var demo := ""
	for a in _args:
		if a.begins_with("--gm-demo="):
			demo = a.get_slice("=", 1)
	match demo:
		"map":
			run.new_run(0, 7)
			show_map()
		"battle":
			run.new_run(0, 7)
			_enter_battle("battle", 1)
		"mend":
			run.new_run(1, 7)
			run.party[0].shattered = true
			run.party[0].mends = 1
			run.party[0].cause = {"element": 0, "crit": true}
			run.gold = 200
			show_mend(true)
			get_tree().create_timer(1.5).timeout.connect(_do_mend.bind(int(run.party[0].uid)))
		"reward":
			run.new_run(0, 7)
			show_reward("elite", {"gold": 62, "shattered": [run.display_name(run.party[1])], "dust": []})
		"end":
			run.new_run(0, 7)
			show_end(true)
		"codex":
			show_codex()
		_:
			show_title()


func _setup_screenshot() -> void:
	var shot := ""
	var delay := 6.0
	for a in _args:
		if a.begins_with("--gm-shot="):
			shot = a.get_slice("=", 1)
		elif a.begins_with("--gm-shot-delay="):
			delay = float(a.get_slice("=", 1))
	if shot == "":
		return
	get_tree().create_timer(delay, true, false, true).timeout.connect(func():
		get_viewport().get_texture().get_image().save_png(shot)
		print("screenshot saved: ", shot)
		get_tree().quit(0))


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or event.keycode == KEY_QUOTELEFT:
			console.toggle()
		elif battle and is_instance_valid(battle):
			battle.handle_key(event.keycode)


# --- Scene plumbing -----------------------------------------------------------------------------
func _clear_world() -> void:
	for c in world.get_children():
		c.queue_free()
	map = null
	battle = null


func _clear_ui() -> void:
	if tip:
		tip.hide_for()
	if ui:
		ui.queue_free()
	ui = Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.theme = HUD.make_theme()
	ui_layer.add_child(ui)


func _show_map_bg(interactive: bool) -> void:
	if map and is_instance_valid(map) and not map.title_mode:
		map.interactive = interactive
		return
	_clear_world()
	map = MapScene.new()
	map.setup(run)
	map.interactive = interactive
	world.add_child(map)
	map.node_chosen.connect(_on_node_chosen)
	map.node_hovered.connect(_on_node_hovered)


func _fade_in() -> void:
	var f := ColorRect.new()
	f.color = Color(0.02, 0.02, 0.06, 1.0)
	f.set_anchors_preset(Control.PRESET_FULL_RECT)
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(f)
	var t := create_tween()
	t.tween_property(f, "color:a", 0.0, 0.5)
	t.tween_callback(f.queue_free)


## Dark indigo vignette framing every screen (keeps the bright plate from glaring).
func _add_vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.08, 0.0))
	g.set_color(1, Color(0.02, 0.02, 0.08, 0.85))
	g.add_point(0.55, Color(0.02, 0.02, 0.08, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.05, 0.5)
	tex.width = 256
	tex.height = 256
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(r)


# --- UI helpers ------------------------------------------------------------------------------------
func _label(text: String, size: int = 16, color: Color = IVORY) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _rich(text: String, size: int = 16, width: float = 0.0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.text = text
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	if width > 0.0:
		r.custom_minimum_size = Vector2(width, 0)
	return r


func _button(text: String, cb: Callable, min_w: float = 180.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 46)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		audio.play("ui")
		cb.call())
	return b


## A clickable card with rich text and a coloured border.
func _card(bbcode: String, border: Color, cb: Callable, size: Vector2 = Vector2(300, 250), images: Array = [], img_size: int = 72) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", HUD._sb(Color(0.05, 0.05, 0.13, 0.95), border.darkened(0.2), 2, 12, 14))
	b.add_theme_stylebox_override("hover", HUD._sb(Color(0.12, 0.1, 0.24, 0.98), border.lightened(0.2), 3, 12, 14))
	b.add_theme_stylebox_override("pressed", HUD._sb(Color(0.2, 0.15, 0.08, 0.98), BRASS, 3, 12, 14))
	var r := _rich("", 15)
	if not images.is_empty():
		r.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
		for im in images:
			r.add_image(im, img_size, img_size)
			r.add_text(" ")
		r.pop()
	r.append_text(bbcode)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.offset_left = 16
	r.offset_right = -16
	r.offset_top = 14
	r.offset_bottom = -14
	b.add_child(r)
	b.pressed.connect(func():
		audio.play("ui")
		cb.call())
	return b


func _center_panel(width: float) -> VBoxContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.custom_minimum_size = Vector2(width, 0)
	p.add_theme_stylebox_override("panel", HUD._sb(Color(0.03, 0.03, 0.09, 0.93), BRASS, 3, 16, 24))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	ui.add_child(p)
	return v


func _hex(c: Color) -> String:
	return c.to_html(false)


func _creature_bbcode(sid: String, extra: String = "") -> String:
	var sp: Dictionary = Data.SPECIES[sid]
	var col: Color = Data.ELEMENT_COLORS[sp.element]
	var t := "[center][font_size=22][color=#%s][b]%s[/b][/color][/font_size]\n" % [_hex(col), I18n.f(sp, "name")]
	t += "[color=#%s]%s[/color] · %s[/center]\n" % [_hex(col), I18n.element(sp.element), I18n.f(sp, "role")]
	t += "[i][color=#ccd]%s[/color][/i]" % I18n.f(sp, "lore")
	return t + extra


## Full detail for hover tips: origin, passive and every skill.
func _creature_detail(sid: String) -> String:
	var sp: Dictionary = Data.SPECIES[sid]
	var o: Dictionary = sp.origin
	var t := "[color=#%s][b]%s[/b][/color]\n[color=#e6b35f]%s · %s[/color]\n" % [_hex(Data.ELEMENT_COLORS[sp.element]), I18n.f(sp, "name"), I18n.f(o, "era"), I18n.f(o, "piece")]
	t += "%s · %s\n" % [_tags_text(sid), I18n.s("toughness", [int(sp.toughness)])]
	t += "[color=#8fb8ff]%s[/color] %s\n" % [I18n.f(sp.passive, "name"), I18n.f(sp.passive, "desc")]
	for sk in sp.skills:
		t += "[color=#e6b35f]• %s[/color] %s\n" % [I18n.f(sk, "name"), I18n.f(sk, "desc")]
	return t.strip_edges()


func _tags_text(sid: String) -> String:
	var names: Array = []
	for tg in Data.SPECIES[sid].tags:
		names.append(I18n.f(Data.TRAITS[tg], "name"))
	return "[color=#ffd060]%s[/color]" % " · ".join(names)


func _upgrade_bbcode(uid: int, upgrade_id: String, extra: String = "") -> String:
	var m: Dictionary = run.member(uid)
	var sp: Dictionary = Data.SPECIES[m.species]
	var up: Dictionary = Data.upgrade_info(m.species, upgrade_id)
	var t := "[center][font_size=15][color=#%s]%s[/color][/font_size]\n" % [_hex(Data.ELEMENT_COLORS[sp.element]), I18n.f(sp, "name")]
	t += "[font_size=21][color=#ffc860][b]✦ %s[/b][/color][/font_size][/center]\n%s%s" % [I18n.f(up, "name"), I18n.f(up, "desc"), extra]
	return t


func _relic_bbcode(id: String, extra: String = "") -> String:
	var r: Dictionary = Data.RELICS[id]
	var col: Color = Data.RARITY_COLORS[int(r.rarity)]
	return "[center][font_size=20][color=#%s][b]%s[/b][/color][/font_size][/center]\n%s%s" % [_hex(col), I18n.f(r, "name"), I18n.f(r, "desc"), extra]


## Gold, floor, party and glaze shards across the top of every run screen (icons + hover tips).
func _top_bar() -> void:
	tip.hide_for()
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_top = 12
	bar.add_theme_constant_override("separation", 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar)
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gold_row := HBoxContainer.new()
	gold_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gold_row.add_child(_icon(Icons.tex("gold", Color(0, 0, 0, 0), 48, "#ffc850"), 26))
	gold_row.add_child(_label(str(run.gold), 22, Color(1, 0.85, 0.45)))
	left.add_child(gold_row)
	var row: int = run.node(run.current).row
	left.add_child(_label(I18n.s("floor", [row, Run.ROWS - 1]), 15, IVORY))
	bar.add_child(left)
	for m in run.party:
		bar.add_child(_party_card(m))
	var traits := run.team_traits()
	if not traits.is_empty():
		var tv := HBoxContainer.new()
		tv.add_theme_constant_override("separation", 3)
		tv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for tid in Data.TRAIT_ORDER:
			if traits.has(tid):
				var ic := _icon(Icons.tex(Icons.TRAIT_ICON.get(tid, "ring"), Color(0.42, 0.3, 0.12), 48), 30)
				ic.mouse_filter = Control.MOUSE_FILTER_STOP
				tip.attach(ic, HUD.trait_tip.bind(tid, int(traits[tid])))
				tv.add_child(ic)
		bar.add_child(tv)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	var relics := HBoxContainer.new()
	relics.add_theme_constant_override("separation", 4)
	relics.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in run.relics:
		var info: Dictionary = Data.RELICS[r]
		var col: Color = Data.RARITY_COLORS[int(info.rarity)]
		var ic := _icon(Icons.tex("shard", col.darkened(0.45), 48), 34)
		ic.mouse_filter = Control.MOUSE_FILTER_STOP
		tip.attach(ic, func(): return "[color=#%s][b]◆ %s[/b][/color]\n%s" % [_hex(col), I18n.f(info, "name"), I18n.f(info, "desc")])
		relics.add_child(ic)
	bar.add_child(relics)
	var lang := _button(I18n.s("lang_btn"), toggle_language, 90)
	bar.add_child(lang)


func _icon(tex: Texture2D, size: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(size, size)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Compact party card: portrait seal, HP bar and gold-seam pips. Details on hover.
func _party_card(m: Dictionary) -> Control:
	var sp: Dictionary = Data.SPECIES[m.species]
	var card := HBoxContainer.new()
	card.add_theme_constant_override("separation", 6)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var portrait := _icon(Icons.portrait(m.species, sp.element, 96), 50)
	if m.shattered:
		portrait.modulate = Color(0.45, 0.4, 0.45)
	card.add_child(portrait)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 3)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var hp := ProgressBar.new()
	hp.show_percentage = false
	hp.custom_minimum_size = Vector2(70, 8)
	hp.value = float(m.hp) * 100.0
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.35, 0.95, 0.5)
	fg.set_corner_radius_all(3)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.05, 0.08)
	bg.set_corner_radius_all(3)
	hp.add_theme_stylebox_override("fill", fg)
	hp.add_theme_stylebox_override("background", bg)
	v.add_child(hp)
	var seams := HBoxContainer.new()
	seams.add_theme_constant_override("separation", 2)
	seams.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in Data.MAX_MENDS:
		var pip := _icon(Icons.tex("seam", Color(0, 0, 0, 0), 32, "#ffc850" if i < int(m.mends) else "#4a4458"), 14)
		seams.add_child(pip)
	if m.shattered:
		seams.add_child(_icon(Icons.tex("def_break", Color(0, 0, 0, 0), 32, "#ff6060"), 14))
	v.add_child(seams)
	var ups := _label("✦".repeat(m.get("upgrades", []).size()), 11, Color(1.0, 0.8, 0.4))
	v.add_child(ups)
	card.add_child(v)
	tip.attach(card, _member_tip.bind(m))
	return card


func _member_tip(m: Dictionary) -> String:
	var sp: Dictionary = Data.SPECIES[m.species]
	var t := "[color=#%s][b]%s[/b][/color]  Lv%d\n" % [_hex(Data.ELEMENT_COLORS[sp.element]), I18n.f(sp, "name"), int(m.level)]
	t += "%s · %s · %d%%\n" % [I18n.element(sp.element), I18n.f(sp, "role"), int(float(m.hp) * 100.0)]
	if m.shattered:
		t += "[color=#ff7070]%s[/color]\n" % I18n.s("shattered")
	t += I18n.s("seams", [int(m.mends), Data.MAX_MENDS]) + "\n"
	for sc in m.scars:
		t += "[color=#ffc860]◆ %s[/color] %s\n" % [I18n.f(Data.SCARS[sc], "name"), I18n.f(Data.SCARS[sc], "desc")]
	t += "[color=#8fb8ff]%s[/color] %s" % [I18n.f(sp.passive, "name"), I18n.f(sp.passive, "desc")]
	for uid in m.get("upgrades", []):
		var up: Dictionary = Data.upgrade_info(m.species, uid)
		t += "\n[color=#ffc860]✦ %s[/color] %s" % [I18n.f(up, "name"), I18n.f(up, "desc")]
	return t


## One line per trait the species list activates (or could activate), for tips.
func _traits_bbcode(species_ids: Array) -> String:
	var counts := Data.trait_counts(species_ids)
	var active := Data.active_traits(species_ids)
	var t := ""
	for tid in Data.TRAIT_ORDER:
		if int(counts.get(tid, 0)) == 0:
			continue
		var info: Dictionary = Data.TRAITS[tid]
		var need: int = int(info.tiers[0])
		if active.has(tid):
			var descs: Array = info.desc_en if I18n.en() else info.desc
			t += "[color=#ffd060]◈ %s %d[/color] %s\n" % [I18n.f(info, "name"), int(counts[tid]), descs[int(active[tid])]]
		else:
			t += "[color=#777788]◇ %s %d/%d[/color]\n" % [I18n.f(info, "name"), int(counts[tid]), need]
	return t.strip_edges()


# --- Title & starters ----------------------------------------------------------------------------
func show_title() -> void:
	_screen = show_title
	_clear_world()
	_clear_ui()
	map = MapScene.new()
	map.title_mode = true
	world.add_child(map)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.grow_horizontal = Control.GROW_DIRECTION_BOTH
	v.grow_vertical = Control.GROW_DIRECTION_BOTH
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 16)
	ui.add_child(v)
	var title := _label(I18n.s("title"), 150, Color(1.0, 0.8, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 22)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.25))
	v.add_child(title)
	var sub := _label(I18n.s("subtitle"), 28, IVORY)
	sub.add_theme_constant_override("outline_size", 10)
	sub.add_theme_color_override("font_outline_color", Color(0.03, 0.05, 0.2))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var story_panel := PanelContainer.new()
	story_panel.add_theme_stylebox_override("panel", HUD._sb(Color(0.02, 0.03, 0.1, 0.78), Color(0.9, 0.7, 0.38, 0.6), 1, 12, 18))
	story_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	story_panel.add_child(_rich("[center]%s[/center]" % I18n.s("story"), 17, 760))
	v.add_child(story_panel)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	h.add_child(_button(I18n.s("start_run"), show_starters, 240))
	h.add_child(_button(I18n.s("codex"), show_codex, 180))
	h.add_child(_button(I18n.s("lang_btn"), toggle_language, 140))
	v.add_child(h)
	_fade_in()
	if _autotest:
		show_starters.call_deferred()


# --- Codex ------------------------------------------------------------------------------------------
var _codex_info: RichTextLabel


func show_codex() -> void:
	_screen = show_codex
	_clear_world()
	_clear_ui()
	var codex := Codex.new()
	world.add_child(codex)
	codex.selected.connect(_codex_selected)
	var t := _label(I18n.s("codex_title"), 34, BRASS)
	t.set_anchors_preset(Control.PRESET_CENTER_TOP)
	t.grow_horizontal = Control.GROW_DIRECTION_BOTH
	t.offset_top = 18
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_constant_override("outline_size", 10)
	t.add_theme_color_override("font_outline_color", Color(0.03, 0.03, 0.1))
	ui.add_child(t)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_right = -24
	panel.custom_minimum_size = Vector2(420, 0)
	panel.add_theme_stylebox_override("panel", HUD._sb(Color(0.03, 0.03, 0.09, 0.9), BRASS, 2, 14, 18))
	_codex_info = _rich(I18n.s("codex_hint"), 16, 380)
	panel.add_child(_codex_info)
	ui.add_child(panel)
	var back := _button(I18n.s("back"), show_title, 160)
	back.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	back.grow_vertical = Control.GROW_DIRECTION_BEGIN
	back.offset_left = 24
	back.offset_bottom = -24
	ui.add_child(back)
	_fade_in()
	for a in _args:
		if a.begins_with("--gm-codex-focus="):
			codex.focus.call_deferred(int(a.get_slice("=", 1)))


func _codex_selected(sid: String) -> void:
	var sp: Dictionary = Data.SPECIES[sid]
	var o: Dictionary = sp.origin
	var t := "[font_size=28][color=#%s][b]%s[/b][/color][/font_size]\n" % [_hex(Data.ELEMENT_COLORS[sp.element]), I18n.f(sp, "name")]
	t += "[color=#e6b35f]%s · %s · %s[/color]\n" % [I18n.f(o, "country"), I18n.f(o, "era"), I18n.f(o, "piece")]
	t += "%s · %s\n\n[i]%s[/i]\n\n" % [I18n.element(sp.element), I18n.f(sp, "role"), I18n.f(sp, "lore")]
	t += "%s · %s\n" % [_tags_text(sid), I18n.s("toughness", [int(sp.toughness)])]
	t += "[color=#8fb8ff]%s · %s[/color] %s\n" % [I18n.s("passive"), I18n.f(sp.passive, "name"), I18n.f(sp.passive, "desc")]
	for sk in sp.skills:
		t += "[color=#e6b35f]• %s[/color] %s\n" % [I18n.f(sk, "name"), I18n.f(sk, "desc")]
	t += "\n[color=#ffc860]%s[/color]\n" % I18n.s("upgrades_title")
	for up in sp.upgrades:
		t += "[color=#ffc860]✦ %s[/color] %s\n" % [I18n.f(up, "name"), I18n.f(up, "desc")]
	_codex_info.text = t


func show_starters() -> void:
	_screen = show_starters
	_clear_ui()
	var v := _center_panel(1040)
	var t := _label(I18n.s("choose_starter"), 30, BRASS)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	for i in Data.STARTERS.size():
		var st: Dictionary = Data.STARTERS[i]
		var txt := "[center][font_size=24][color=#e6b35f][b]%s[/b][/color][/font_size]\n[color=#aab]%s[/color][/center]" % [I18n.f(st, "name"), I18n.f(st, "desc")]
		var imgs: Array = []
		for sid in st.team:
			imgs.append(Icons.portrait(sid, Data.SPECIES[sid].element, 128))
		var card := _card(txt, BRASS, _start_run.bind(i), Vector2(320, 210), imgs, 76)
		tip.attach(card, _starter_tip.bind(st))
		h.add_child(card)
	v.add_child(h)
	if _autotest:
		_start_run.call_deferred(0)


func _starter_tip(st: Dictionary) -> String:
	var t := ""
	for sid in st.team:
		var sp: Dictionary = Data.SPECIES[sid]
		t += "[color=#%s][b]%s[/b][/color] %s · %s\n[i][color=#ccd]%s[/color][/i]\n" % [_hex(Data.ELEMENT_COLORS[sp.element]), I18n.f(sp, "name"), I18n.element(sp.element), I18n.f(sp, "role"), I18n.f(sp, "lore")]
	return (t + "\n" + _traits_bbcode(st.team)).strip_edges()


func _start_run(i: int) -> void:
	run.new_run(i)
	show_map()


# --- Map -------------------------------------------------------------------------------------------
func show_map() -> void:
	_screen = show_map
	_busy = false
	_show_map_bg(true)
	if map:
		map.clear_mend()
		map.focus_current()
	_clear_ui()
	_top_bar()
	var hint := _label(I18n.s("map_hint"), 18, Color(1, 0.9, 0.6))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hint.offset_bottom = -20
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(hint)
	if _autotest:
		_autopilot_map.call_deferred()


func _autopilot_map() -> void:
	await get_tree().create_timer(0.3).timeout
	var avail: Array = run.available()
	if not avail.is_empty():
		_on_node_chosen(avail[run.rng.randi_range(0, avail.size() - 1)])


func _on_node_hovered(id: int) -> void:
	if id < 0 or map == null or map.title_mode:
		tip.hide_for(map)
		return
	var n: Dictionary = run.node(id)
	var info: Dictionary = Data.NODE_TYPES[n.type]
	var txt := "[color=#%s][b]%s[/b][/color]" % [_hex(info.color.lightened(0.35)), I18n.f(info, "name")]
	txt += "\n[color=#9aa]%s[/color]" % I18n.s("node_" + String(n.type))
	if not id in run.available():
		txt += "\n[color=#777]%s[/color]" % I18n.s("not_reachable")
	tip.show_text(txt, map)


func _on_node_chosen(id: int) -> void:
	if _busy or not id in run.available():
		return
	_busy = true
	audio.play("turn")
	map.interactive = false
	await map.travel_to(id)
	run.current = id
	run.node(id).visited = true
	var n: Dictionary = run.node(id)
	match n.type:
		"battle", "elite", "boss":
			_enter_battle(n.type, n.row)
		"kiln":
			show_kiln()
		"mend":
			show_mend(false)
		"shop":
			show_shop()
		"event":
			show_event(run.pick_event())


# --- Battle ----------------------------------------------------------------------------------------
func _enter_battle(kind: String, row: int) -> void:
	if run.fighters().is_empty():
		show_end(false)
		return
	_clear_ui()
	_clear_world()
	battle = Battle.new()
	battle.game = self
	battle.audio = audio
	battle.auto_battle = auto_battle
	battle.cheat_no_cd = cheats.no_cd
	battle.cheat_max_atb = cheats.max_atb
	battle.floor_text = I18n.s("floor", [row, Run.ROWS - 1])
	battle.banner_text = {"battle": I18n.s("floor_banner", [row]), "elite": I18n.s("elite_banner"), "boss": I18n.s("boss_banner")}[kind]
	battle.banner_sub = I18n.f(Data.NODE_TYPES[kind], "name")
	world.add_child(battle)
	_fade_in()
	battle.begin(run.ally_specs(), run.enemy_specs(row, kind), run.relics)
	var result: Array = await battle.finished
	var victory: bool = result[0]
	var report: Dictionary = result[1]
	var res: Dictionary = run.apply_battle(victory, report, kind, row)
	if _autotest:
		print("AUTOTEST %s row=%d: %s turns=%d ally_turns=%d breaks=%d chains=%d interrupts=%d gold=%d party=%s" % [kind, row, "WIN" if victory else "LOSS",
			report.turns, report.ally_turns, report.breaks, report.chains, report.interrupts, run.gold,
			run.party.map(func(m): return "%s L%d hp%.2f s%d u%d%s" % [m.species, m.level, m.hp, m.mends, m.upgrades.size(), " X" if m.shattered else ""])])
	if not victory or run.fighters().is_empty():
		show_end(false)
	elif kind == "boss":
		show_end(true)
	else:
		show_reward(kind, res)


func show_reward(kind: String, res: Dictionary) -> void:
	_screen = show_reward.bind(kind, res)
	_show_map_bg(false)
	_clear_ui()
	_top_bar()
	var v := _center_panel(1000)
	var t := _label(I18n.s("reward_title"), 34, BRASS)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var lines := "[center]%s · %s[/center]\n" % [I18n.s("reward_gold", [int(res.gold)]), I18n.s("reward_level")]
	for n in res.shattered:
		lines += "[center]%s[/center]\n" % I18n.s("reward_shattered", [n])
	for n in res.dust:
		lines += "[center]%s[/center]\n" % I18n.s("reward_dust", [n])
	v.add_child(_rich(lines, 17))
	var pick := _label(I18n.s("pick_reward"), 20, IVORY)
	pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pick)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 16)
	# normal fights: 2 craft upgrades + 1 glaze shard; elites: 1 upgrade + 2 rarer shards
	var ups: Array = run.upgrade_choices(1 if kind == "elite" else 2)
	var shards: Array = run.relic_choices(3 - ups.size(), 1 if kind == "elite" else 0)
	for o in ups:
		var m: Dictionary = run.member(int(o.uid))
		var c := _card(_upgrade_bbcode(int(o.uid), o.upgrade), Color(1.0, 0.78, 0.35), _take_upgrade.bind(int(o.uid), o.upgrade), Vector2(270, 220),
			[Icons.portrait(m.species, Data.SPECIES[m.species].element, 96)], 56)
		tip.attach(c, _member_tip.bind(m))
		h.add_child(c)
	for r in shards:
		var rcol: Color = Data.RARITY_COLORS[int(Data.RELICS[r].rarity)]
		h.add_child(_card(_relic_bbcode(r), rcol, _take_relic.bind(r), Vector2(270, 220), [Icons.tex("shard", rcol.darkened(0.45), 96)], 56))
	v.add_child(h)
	var skip := _button(I18n.s("skip"), show_map, 160)
	skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(skip)
	if _autotest:
		if not ups.is_empty():
			_take_upgrade.call_deferred(int(ups[0].uid), ups[0].upgrade)
		elif not shards.is_empty():
			_take_relic.call_deferred(shards[0])
		else:
			show_map.call_deferred()


func _take_relic(id: String) -> void:
	run.relics.append(id)
	audio.play("buff")
	show_map()


func _take_upgrade(uid: int, upgrade_id: String) -> void:
	run.apply_upgrade(uid, upgrade_id)
	audio.play("buff")
	var up: Dictionary = Data.upgrade_info(run.member(uid).species, upgrade_id)
	_toast("✦ %s" % I18n.f(up, "name"))
	show_map()


# --- Kiln ------------------------------------------------------------------------------------------
func show_kiln() -> void:
	_screen = show_kiln
	_show_map_bg(false)
	_clear_ui()
	_top_bar()
	var v := _center_panel(1040)
	v.add_child(_label(I18n.s("kiln_title"), 32, Color(1.0, 0.6, 0.3)))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var choices: Array = run.kiln_choices()
	for sid in choices:
		var kc := _card(_creature_bbcode(sid), Data.ELEMENT_COLORS[Data.SPECIES[sid].element], _kiln_pick.bind(sid), Vector2(300, 270), [Icons.portrait(sid, Data.SPECIES[sid].element, 128)], 84)
		tip.attach(kc, _creature_detail.bind(sid))
		h.add_child(kc)
	v.add_child(h)
	# 回炉: or put one of your spirits back in the kiln for a new craft technique
	var refire: Array = run.upgrade_choices(3)
	if not refire.is_empty():
		v.add_child(_label(I18n.s("kiln_refire"), 20, Color(1.0, 0.75, 0.45)))
		var h2 := HBoxContainer.new()
		h2.add_theme_constant_override("separation", 16)
		for o in refire:
			var m: Dictionary = run.member(int(o.uid))
			var c := _card(_upgrade_bbcode(int(o.uid), o.upgrade), Color(1.0, 0.6, 0.3), _take_upgrade.bind(int(o.uid), o.upgrade), Vector2(300, 170),
				[Icons.portrait(m.species, Data.SPECIES[m.species].element, 96)], 44)
			tip.attach(c, _member_tip.bind(m))
			h2.add_child(c)
		v.add_child(h2)
	v.add_child(_button(I18n.s("skip"), show_map, 160))
	if _autotest:
		if run.party.size() < Run.MAX_PARTY or refire.is_empty():
			_kiln_pick.call_deferred(choices[0])
		else:
			_take_upgrade.call_deferred(int(refire[0].uid), refire[0].upgrade)


func _kiln_pick(sid: String) -> void:
	if run.party.size() < Run.MAX_PARTY:
		var m: Dictionary = run.recruit(sid)
		audio.play("heal")
		_toast(I18n.s("joined", [run.display_name(m)]))
		show_map()
		return
	_clear_ui()
	_top_bar()
	var v := _center_panel(900)
	v.add_child(_label(I18n.s("kiln_replace"), 26, BRASS))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	for m in run.party:
		var rc := _card("[center]%s\n[color=#ffc860]%s[/color][/center]" % [run.display_name(m), "◆".repeat(int(m.mends))], Color(0.9, 0.4, 0.4), _kiln_replace.bind(sid, int(m.uid)), Vector2(170, 170), [Icons.portrait(m.species, Data.SPECIES[m.species].element, 128)], 84)
		tip.attach(rc, _member_tip.bind(m))
		h.add_child(rc)
	v.add_child(h)
	v.add_child(_button(I18n.s("skip"), show_map, 160))
	if _autotest:
		show_map.call_deferred()


func _kiln_replace(sid: String, uid: int) -> void:
	var m: Dictionary = run.recruit(sid, uid)
	_toast(I18n.s("joined", [run.display_name(m)]))
	show_map()


# --- Mending hall ------------------------------------------------------------------------------------
var _rested := false


func show_mend(fresh: bool = true) -> void:
	if fresh or _screen != show_mend:
		_rested = false
	_screen = show_mend
	_show_map_bg(false)
	_clear_ui()
	_top_bar()
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = 30
	panel.custom_minimum_size = Vector2(560, 0)
	panel.add_theme_stylebox_override("panel", HUD._sb(Color(0.03, 0.03, 0.09, 0.93), BRASS, 3, 16, 22))
	ui.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	v.add_child(_label(I18n.s("mend_title"), 32, Color(1.0, 0.8, 0.4)))
	var how := _label(I18n.s("mend_short"), 15, Color(0.8, 0.8, 0.9))
	how.mouse_filter = Control.MOUSE_FILTER_STOP
	tip.attach(how, func(): return I18n.s("mend_text"))
	v.add_child(how)
	for m in run.party:
		var sp: Dictionary = Data.SPECIES[m.species]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var seams := "◆".repeat(int(m.mends)) + "◇".repeat(Data.MAX_MENDS - int(m.mends))
		var desc := "[color=#%s]%s[/color]  [color=#ffc860]%s[/color]  %s" % [_hex(Data.ELEMENT_COLORS[sp.element]), I18n.f(sp, "name"), seams,
			("[color=#ff7070]%s[/color]" % I18n.s("shattered")) if m.shattered else "%d%%" % int(float(m.hp) * 100.0)]
		var info := _rich(desc, 16, 280)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		if m.shattered:
			var cost: int = run.mend_cost(m)
			var b := _button(I18n.s("mend_btn", [cost]), _do_mend.bind(int(m.uid)), 200)
			b.disabled = run.gold < cost
			row.add_child(b)
		v.add_child(row)
	var rest := _button(I18n.s("rest_btn"), _do_rest, 300)
	rest.disabled = _rested
	v.add_child(rest)
	v.add_child(_button(I18n.s("leave"), show_map, 160))
	if _autotest:
		for m in run.party:
			if m.shattered and run.gold >= run.mend_cost(m):
				_do_mend.call_deferred(int(m.uid))
				return
		if not _rested:
			_rested = true
			run.heal_all(0.4)
		show_map.call_deferred()


func _do_rest() -> void:
	_rested = true
	run.heal_all(0.4)
	audio.play("heal")
	show_mend(false)


func _do_mend(uid: int) -> void:
	var m: Dictionary = run.member(uid)
	var scar: String = run.mend(uid)
	audio.play("reaction")
	show_mend(false)
	if map:
		map.play_mend(m.species, int(m.mends))
	var txt := "%s  %s" % [I18n.s("mended_banner"), "◆".repeat(int(m.mends))]
	if scar != "":
		txt += "\n" + I18n.s("new_scar", [I18n.f(Data.SCARS[scar], "name"), I18n.f(Data.SCARS[scar], "desc")])
	_toast(txt, 3.0)


func _toast(text: String, secs: float = 2.0) -> void:
	var l := _label(text, 26, Color(1.0, 0.85, 0.45))
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0.03, 0.03, 0.1))
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.grow_horizontal = Control.GROW_DIRECTION_BOTH
	l.offset_top = 150
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui_layer.add_child(l)
	var t := create_tween()
	t.tween_interval(secs)
	t.tween_property(l, "modulate:a", 0.0, 0.5)
	t.tween_callback(l.queue_free)


# --- Shop ---------------------------------------------------------------------------------------------
var _shop_stock: Array = []
var _shop_upgrade: Dictionary = {}


func show_shop(restock: bool = true) -> void:
	if restock or _screen != show_shop:
		_shop_stock = run.relic_choices(3)
		var ups: Array = run.upgrade_choices(1)
		_shop_upgrade = ups[0] if not ups.is_empty() else {}
	_screen = show_shop
	_show_map_bg(false)
	_clear_ui()
	_top_bar()
	var v := _center_panel(1000)
	v.add_child(_label(I18n.s("shop_title"), 32, Color(0.5, 0.8, 1.0)))
	v.add_child(_label(I18n.s("shop_text"), 16))
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 16)
	for r in _shop_stock:
		var owned: bool = r in run.relics
		var price: int = run.relic_price(r)
		var extra := "\n\n[color=#ffd060]%s[/color]" % (I18n.s("sold") if owned else I18n.s("buy", [price]))
		var scol: Color = Data.RARITY_COLORS[int(Data.RELICS[r].rarity)]
		var c := _card(_relic_bbcode(r, extra), scol, _buy.bind(r), Vector2(270, 220), [Icons.tex("shard", scol.darkened(0.45), 96)], 56)
		c.disabled = owned or run.gold < price
		h.add_child(c)
	if not _shop_upgrade.is_empty():
		var o := _shop_upgrade
		var m: Dictionary = run.member(int(o.uid))
		var have: bool = o.upgrade in m.upgrades
		var extra := "\n\n[color=#ffd060]%s[/color]" % (I18n.s("sold") if have else I18n.s("buy", [run.upgrade_price()]))
		var uc := _card(_upgrade_bbcode(int(o.uid), o.upgrade, extra), Color(1.0, 0.78, 0.35), _buy_upgrade, Vector2(270, 220),
			[Icons.portrait(m.species, Data.SPECIES[m.species].element, 96)], 56)
		uc.disabled = have or run.gold < run.upgrade_price()
		h.add_child(uc)
	v.add_child(h)
	var heal := _button(I18n.s("heal_potion", [25]), _buy_heal, 360)
	heal.disabled = run.gold < 25
	v.add_child(heal)
	v.add_child(_button(I18n.s("leave"), show_map, 160))
	if _autotest:
		for r in _shop_stock:
			if not r in run.relics and run.gold >= run.relic_price(r):
				_buy.call_deferred(r)
				return
		show_map.call_deferred()


func _buy_upgrade() -> void:
	if _shop_upgrade.is_empty() or run.gold < run.upgrade_price():
		return
	run.gold -= run.upgrade_price()
	run.apply_upgrade(int(_shop_upgrade.uid), _shop_upgrade.upgrade)
	audio.play("buff")
	show_shop(false)


func _buy_heal() -> void:
	if run.gold >= 25:
		run.gold -= 25
		run.heal_all(0.5)
		audio.play("heal")
		show_shop(false)


func _buy(id: String) -> void:
	var price: int = run.relic_price(id)
	if run.gold < price or id in run.relics:
		return
	run.gold -= price
	run.relics.append(id)
	audio.play("buff")
	show_shop(false)


# --- Events -------------------------------------------------------------------------------------------
func show_event(ev: Dictionary) -> void:
	_screen = show_event.bind(ev)
	_show_map_bg(false)
	_clear_ui()
	_top_bar()
	var v := _center_panel(780)
	v.add_child(_label(I18n.f(ev, "title"), 30, Color(0.6, 0.95, 0.7)))
	v.add_child(_rich(I18n.f(ev, "text"), 18, 720))
	for opt in ev.options:
		var b := _button(I18n.f(opt, "text"), _event_choice.bind(opt.act), 700)
		v.add_child(b)
	if _autotest:
		_event_choice.call_deferred(ev.options[0].act)


func _event_choice(act: String) -> void:
	var result: String = run.resolve_event(act)
	_clear_ui()
	_top_bar()
	var v := _center_panel(600)
	v.add_child(_rich("[center][font_size=24]%s[/font_size][/center]" % (result if result != "" else "…"), 18))
	var b := _button(I18n.s("continue"), show_map, 200)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	if _autotest:
		show_map.call_deferred()


# --- End of run -----------------------------------------------------------------------------------------
func show_end(won: bool) -> void:
	_screen = show_end.bind(won)
	_clear_world()
	_clear_ui()
	map = MapScene.new()
	map.title_mode = true
	world.add_child(map)
	var v := _center_panel(760)
	var t := _label(I18n.s("run_won_title" if won else "run_lost_title"), 48, BRASS if won else Color(1.0, 0.5, 0.5))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(_rich("[center]%s[/center]" % I18n.s("run_won_text" if won else "run_lost_text"), 18, 700))
	var row: int = run.node(run.current).row
	v.add_child(_rich("[center][color=#e6b35f]%s[/color][/center]" % I18n.s("run_summary", [row, run.stats.battles, run.stats.breaks, run.stats.chains, run.total_seams()]), 16))
	var team := ""
	for m in run.party:
		team += "%s %s  " % [run.display_name(m), "◆".repeat(int(m.mends))]
	v.add_child(_rich("[center]%s[/center]" % team, 16))
	var b := _button(I18n.s("new_run"), show_starters, 220)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	audio.play("victory" if won else "defeat")
	if _autotest:
		print("AUTOTEST RUN %s floor=%d battles=%d breaks=%d chains=%d seams=%d relics=%s dust=%s" % [
			"WON" if won else "LOST", row, run.stats.battles, run.stats.breaks, run.stats.chains, run.total_seams(), run.relics, run.dust])
		get_tree().quit(0)


# --- Balance simulation (--gm-sim) -------------------------------------------------------------------------
## Plays many fast battles with the AI on both sides and prints a table per starter and floor.
## Party model for floor r: level 4 + 0.8(r-1), about one craft upgrade per fight so far,
## one glaze shard every two fights, a 4th spirit from floor 4 on, full HP.
func _simulate(n: int) -> void:
	var rows := [[1, "battle"], [2, "battle"], [3, "battle"], [3, "elite"], [4, "battle"], [5, "battle"], [5, "elite"],
		[6, "battle"], [6, "elite"], [7, "battle"], [8, "boss"]]
	print("SIM n=%d per cell | starter kind row | win%% ally_act turns est_sec breaks chains intr hp_left" % n)
	var totals := {}
	for starter in Data.STARTERS.size():
		for rk in rows:
			var row: int = rk[0]
			var kind: String = rk[1]
			var agg := {"win": 0, "ally_turns": 0, "turns": 0, "time": 0.0, "breaks": 0, "chains": 0, "interrupts": 0, "hp": 0.0}
			for i in n:
				var r := Run.new()
				r.new_run(starter, 1000 * starter + 17 * row + i)
				if row >= 4:
					r.recruit(r.kiln_choices()[0])
				for m in r.party:
					m.level = 4 + roundi(0.8 * (row - 1))
				for k in maxi(0, row - 1):
					var ups: Array = r.upgrade_choices(1)
					if not ups.is_empty():
						r.apply_upgrade(int(ups[0].uid), ups[0].upgrade)
				for k in (row - 1) / 2:
					r.relics.append_array(r.relic_choices(1))
				var b := Battle.new()
				b.fast = true
				b.audio = audio
				b.auto_battle = true
				world.add_child(b)
				b.begin(r.ally_specs(), r.enemy_specs(row, kind), r.relics)
				var result: Array = await b.finished
				var rep: Dictionary = result[1]
				if result[0]:
					agg.win += 1
				for k in ["ally_turns", "turns", "breaks", "chains", "interrupts"]:
					agg[k] += int(rep[k])
				agg.time += float(rep.time)
				var hp := 0.0
				for a in rep.allies:
					hp += float(a.hp_ratio) if a.alive else 0.0
				agg.hp += hp / maxf(1.0, rep.allies.size())
				b.queue_free()
				await get_tree().process_frame
			var key := "%s %d" % [kind, row]
			if not totals.has(key):
				totals[key] = []
			totals[key].append(float(agg.win) / n)
			print("SIM %d %-6s %d | %3d%% %5.1f %5.1f %5.0f %4.1f %4.1f %4.1f %4.2f" % [starter, kind, row, roundi(100.0 * agg.win / n),
				float(agg.ally_turns) / n, float(agg.turns) / n, agg.time / n, float(agg.breaks) / n, float(agg.chains) / n,
				float(agg.interrupts) / n, agg.hp / n])
	print("SIM done")
	get_tree().quit(0)


# --- Controls used by HUD / console -----------------------------------------------------------------------
func set_auto(on: bool) -> void:
	auto_battle = on
	console.sync(on)
	if battle and is_instance_valid(battle):
		battle.set_auto(on)


func set_speed(m: int) -> void:
	speed = clampi(m, 1, 3)
	if not _autotest:
		Engine.time_scale = float(speed)
	if battle and is_instance_valid(battle):
		battle.hud.set_speed(speed)


func cycle_speed() -> void:
	set_speed(speed % 3 + 1)


func toggle_console() -> void:
	console.toggle()


func toggle_language() -> void:
	I18n.toggle()
	console.rebuild()
	if battle and is_instance_valid(battle):
		return
	if map and is_instance_valid(map) and not map.title_mode:
		# tokens carry text too: rebuild the plate
		_clear_world()
	if _screen.is_valid():
		_screen.call()


func cheat_flag(flag: String, on: bool) -> void:
	cheats[flag] = on
	if battle and is_instance_valid(battle):
		if flag == "no_cd":
			battle.cheat_no_cd = on
		else:
			battle.cheat_max_atb = on


func cheat(kind: String) -> void:
	var in_battle: bool = battle != null and is_instance_valid(battle)
	match kind:
		"win":
			if in_battle:
				battle.cheat_win()
		"kill":
			if in_battle:
				battle.cheat_kill_all()
		"heal":
			if in_battle:
				battle.cheat_heal()
			run.heal_all(1.0)
		"gold":
			run.gold += 100
		"relic":
			var r: Array = run.relic_choices(1)
			if not r.is_empty():
				run.relics.append(r[0])
		"mend":
			for m in run.party:
				if m.shattered:
					m.shattered = false
					m.mends = mini(int(m.mends) + 1, Data.MAX_MENDS)
					m.hp = 0.6
	if not in_battle and _screen.is_valid() and kind in ["gold", "relic", "mend", "heal"]:
		_screen.call()
