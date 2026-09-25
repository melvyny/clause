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

const Data = preload("po_data.gd")
const I18n = preload("po_i18n.gd")
const M = preload("po_mat.gd")
const Run = preload("po_run.gd")
const MapScene = preload("po_map.gd")
const Battle = preload("po_battle.gd")
const HUD = preload("po_hud.gd")
const Audio = preload("po_audio.gd")
const Console = preload("po_console.gd")

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
	if _autotest:
		audio.muted = true
		auto_battle = true
		Engine.time_scale = 10.0
		get_tree().create_timer(600.0, true, false, true).timeout.connect(func():
			printerr("AUTOTEST TIMEOUT")
			get_tree().quit(1))
	_setup_screenshot()
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
func _card(bbcode: String, border: Color, cb: Callable, size: Vector2 = Vector2(300, 250)) -> Button:
	var b := Button.new()
	b.custom_minimum_size = size
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", HUD._sb(Color(0.05, 0.05, 0.13, 0.95), border.darkened(0.2), 2, 12, 14))
	b.add_theme_stylebox_override("hover", HUD._sb(Color(0.12, 0.1, 0.24, 0.98), border.lightened(0.2), 3, 12, 14))
	b.add_theme_stylebox_override("pressed", HUD._sb(Color(0.2, 0.15, 0.08, 0.98), BRASS, 3, 12, 14))
	var r := _rich(bbcode, 15)
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
	var t := "[font_size=22][color=#%s][b]%s[/b][/color][/font_size]\n" % [_hex(col), I18n.f(sp, "name")]
	t += "[color=#%s]%s[/color] · %s\n" % [_hex(col), I18n.element(sp.element), I18n.f(sp, "role")]
	t += "[color=#8fb8ff]%s[/color] %s\n" % [I18n.f(sp.passive, "name"), I18n.f(sp.passive, "desc")]
	for sk in sp.skills:
		t += "[color=#e6b35f]•[/color] %s\n" % I18n.f(sk, "name")
	return t + extra


func _relic_bbcode(id: String, extra: String = "") -> String:
	var r: Dictionary = Data.RELICS[id]
	var col: Color = Data.RARITY_COLORS[int(r.rarity)]
	return "[font_size=21][color=#%s][b]◆ %s[/b][/color][/font_size]\n\n%s%s" % [_hex(col), I18n.f(r, "name"), I18n.f(r, "desc"), extra]


## Gold, floor, party and glaze shards across the top of every run screen.
func _top_bar() -> void:
	var bar := HBoxContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_left = 16
	bar.offset_right = -16
	bar.offset_top = 12
	bar.add_theme_constant_override("separation", 14)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(bar)
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_child(_label(I18n.s("title_small"), 22, BRASS))
	var row: int = run.node(run.current).row
	left.add_child(_label("%s    %s" % [I18n.s("gold", [run.gold]), I18n.s("floor", [row, Run.ROWS - 1])], 17, Color(1, 0.85, 0.45)))
	bar.add_child(left)
	for m in run.party:
		var sp: Dictionary = Data.SPECIES[m.species]
		var col: Color = Data.ELEMENT_COLORS[sp.element]
		var p := PanelContainer.new()
		p.custom_minimum_size = Vector2(170, 0)
		p.mouse_filter = Control.MOUSE_FILTER_PASS
		p.add_theme_stylebox_override("panel", HUD._sb(Color(0.05, 0.05, 0.12, 0.9), (Color(0.9, 0.3, 0.3) if m.shattered else col.darkened(0.3)), 2, 8, 6))
		var v := VBoxContainer.new()
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_theme_constant_override("separation", 2)
		var seams := "◆".repeat(int(m.mends)) + "◇".repeat(Data.MAX_MENDS - int(m.mends))
		v.add_child(_rich("[color=#%s]%s[/color] %s [color=#9aa]%s[/color]\n[color=#ffc860]%s[/color]" % [
			_hex(col), I18n.element(sp.element), I18n.f(sp, "name"), I18n.s("lv", [int(m.level)]), seams], 13))
		var hp := ProgressBar.new()
		hp.show_percentage = false
		hp.custom_minimum_size = Vector2(0, 8)
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
		if m.shattered:
			v.add_child(_label(I18n.s("shattered"), 13, Color(1, 0.45, 0.45)))
		var tip := ""
		for sc in m.scars:
			tip += "%s — %s\n" % [I18n.f(Data.SCARS[sc], "name"), I18n.f(Data.SCARS[sc], "desc")]
		p.tooltip_text = tip.strip_edges()
		p.add_child(v)
		bar.add_child(p)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(spacer)
	var rel := VBoxContainer.new()
	rel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rel.add_child(_label(I18n.s("relics"), 15, BRASS))
	var txt := ""
	for r in run.relics:
		var info: Dictionary = Data.RELICS[r]
		txt += "[hint=%s][color=#%s]◆%s[/color][/hint]  " % [I18n.f(info, "desc"), _hex(Data.RARITY_COLORS[int(info.rarity)]), I18n.f(info, "name")]
	var rt := _rich(txt if txt != "" else I18n.s("no_relics"), 14, 330)
	rt.mouse_filter = Control.MOUSE_FILTER_PASS
	rel.add_child(rt)
	bar.add_child(rel)
	var lang := _button(I18n.s("lang_btn"), toggle_language, 90)
	bar.add_child(lang)


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
	h.add_child(_button(I18n.s("lang_btn"), toggle_language, 140))
	v.add_child(h)
	_fade_in()
	if _autotest:
		show_starters.call_deferred()


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
		var txt := "[font_size=24][color=#e6b35f][b]%s[/b][/color][/font_size]\n[color=#aab]%s[/color]\n\n" % [I18n.f(st, "name"), I18n.f(st, "desc")]
		for sid in st.team:
			var sp: Dictionary = Data.SPECIES[sid]
			txt += "[color=#%s]● %s[/color]  %s · %s\n" % [_hex(Data.ELEMENT_COLORS[sp.element]), I18n.f(sp, "name"), I18n.element(sp.element), I18n.f(sp, "role")]
		h.add_child(_card(txt, BRASS, _start_run.bind(i), Vector2(320, 230)))
	v.add_child(h)
	if _autotest:
		_start_run.call_deferred(0)


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
	var legend := ""
	for k in ["battle", "elite", "kiln", "mend", "shop", "event", "boss"]:
		var info: Dictionary = Data.NODE_TYPES[k]
		legend += "[color=#%s]%s[/color] %s\n" % [_hex(info.color.lightened(0.3)), I18n.f(info, "glyph"), I18n.f(info, "name")]
	var lg := _rich(legend, 15)
	lg.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	lg.grow_vertical = Control.GROW_DIRECTION_BEGIN
	lg.offset_left = 20
	lg.offset_bottom = -20
	lg.custom_minimum_size = Vector2(200, 0)
	ui.add_child(lg)
	if _autotest:
		_autopilot_map.call_deferred()


func _autopilot_map() -> void:
	await get_tree().create_timer(0.3).timeout
	var avail: Array = run.available()
	if not avail.is_empty():
		_on_node_chosen(avail[run.rng.randi_range(0, avail.size() - 1)])


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
		print("AUTOTEST %s row=%d: %s turns=%d reactions=%d gold=%d party=%s" % [kind, row, "WIN" if victory else "LOSS", report.turns, report.reactions, run.gold,
			run.party.map(func(m): return "%s L%d hp%.2f s%d%s" % [m.species, m.level, m.hp, m.mends, " X" if m.shattered else ""])])
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
	var pick := _label(I18n.s("pick_relic"), 20, IVORY)
	pick.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(pick)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 16)
	var choices: Array = run.relic_choices(3, 1 if kind == "elite" else 0)
	for r in choices:
		h.add_child(_card(_relic_bbcode(r), Data.RARITY_COLORS[int(Data.RELICS[r].rarity)], _take_relic.bind(r), Vector2(290, 170)))
	v.add_child(h)
	var skip := _button(I18n.s("skip"), show_map, 160)
	skip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(skip)
	if _autotest:
		if choices.is_empty():
			show_map.call_deferred()
		else:
			_take_relic.call_deferred(choices[0])


func _take_relic(id: String) -> void:
	run.relics.append(id)
	audio.play("buff")
	show_map()


# --- Kiln ------------------------------------------------------------------------------------------
func show_kiln() -> void:
	_screen = show_kiln
	_show_map_bg(false)
	_clear_ui()
	_top_bar()
	var v := _center_panel(1040)
	v.add_child(_label(I18n.s("kiln_title"), 32, Color(1.0, 0.6, 0.3)))
	v.add_child(_rich(I18n.s("kiln_text"), 16, 980))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var choices: Array = run.kiln_choices()
	for sid in choices:
		h.add_child(_card(_creature_bbcode(sid), Data.ELEMENT_COLORS[Data.SPECIES[sid].element], _kiln_pick.bind(sid), Vector2(320, 250)))
	v.add_child(h)
	v.add_child(_button(I18n.s("skip"), show_map, 160))
	if _autotest:
		_kiln_pick.call_deferred(choices[0])


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
		h.add_child(_card(_creature_bbcode(m.species, "\n" + "◆".repeat(int(m.mends))), Color(0.9, 0.4, 0.4), _kiln_replace.bind(sid, int(m.uid)), Vector2(200, 230)))
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
	v.add_child(_rich(I18n.s("mend_text"), 15, 510))
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


func show_shop(restock: bool = true) -> void:
	if restock or _screen != show_shop:
		_shop_stock = run.relic_choices(3)
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
		var c := _card(_relic_bbcode(r, extra), Data.RARITY_COLORS[int(Data.RELICS[r].rarity)], _buy.bind(r), Vector2(290, 190))
		c.disabled = owned or run.gold < price
		h.add_child(c)
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
	v.add_child(_rich("[center][color=#e6b35f]%s[/color][/center]" % I18n.s("run_summary", [row, run.stats.battles, run.stats.reactions, run.total_seams()]), 16))
	var team := ""
	for m in run.party:
		team += "%s %s  " % [run.display_name(m), "◆".repeat(int(m.mends))]
	v.add_child(_rich("[center]%s[/center]" % team, 16))
	var b := _button(I18n.s("new_run"), show_starters, 220)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	audio.play("victory" if won else "defeat")
	if _autotest:
		print("AUTOTEST RUN %s floor=%d battles=%d reactions=%d seams=%d relics=%s dust=%s" % [
			"WON" if won else "LOST", row, run.stats.battles, run.stats.reactions, run.total_seams(), run.relics, run.dust])
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
