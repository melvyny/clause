extends Node3D
## Porcelain Orrery :: battle controller (main scene script).
##
## Continuous-tick Attack Bar (ATB) engine: every tick each living unit gains
## SPD x 7% ATB; whoever reaches 100% first acts (ties -> higher SPD). Skills,
## elemental advantage, Element Fission reactions, energy-charged ultimates,
## passives, leader skills, AI, player input, cheats and loot all live here.
##
## Command-line (after `--`):
##   --po-autotest                 AI vs AI, 3 battles at high speed, then quit
##   --po-screenshot=<path.png>    save a screenshot after --po-shot-delay=<sec>
##   --po-shot-board               open the Rune Board before the screenshot

const Data = preload("po_data.gd")
const Profile = preload("po_profile.gd")
const Unit = preload("po_unit.gd")
const VFX = preload("po_vfx.gd")
const Audio = preload("po_audio.gd")
const Cam = preload("po_camera.gd")
const Arena = preload("po_arena.gd")
const HUD = preload("po_hud.gd")
const Console = preload("po_console.gd")

enum State { INTRO, TICKING, BUSY, WAIT_INPUT, ENDED }

signal player_action(choice: Dictionary)

const TICK_RATE := 22.0
const SLOTS_X := [-4.8, -1.6, 1.6, 4.8]
const TEAM_Z := 4.6

var profile: Profile
var units: Array = []
var state := State.INTRO
var serial := 0
var tick_accum := 0.0
var auto_battle := false
var speed_mult := 1
var cheat_no_cd := false
var cheat_max_atb := false
var rng := RandomNumberGenerator.new()
var current_unit: Node = null
var selected_skill := 0
var hovered: Node = null

var arena: Node3D
var cam: Camera3D
var vfx: Node3D
var audio: Node
var hud: CanvasLayer
var console: CanvasLayer
var units_root: Node3D

var _mouse := Vector2.ZERO
var _mouse_moved := false
var _pending_click := false
var _order_timer := 0.0
var _last_victory := false
var _stats := {"turns": 0, "reactions": 0, "crits": 0}
var _autotest := false
var _autotest_done := 0


func _ready() -> void:
	rng.randomize()
	var args := OS.get_cmdline_user_args()
	_autotest = "--po-autotest" in args
	profile = Profile.new("user://porcelain_orrery_autotest.json" if _autotest else Profile.SAVE_PATH)
	if _autotest:
		profile.reset()
	else:
		profile.load_or_create()

	arena = Arena.new()
	add_child(arena)
	cam = Cam.new()
	add_child(cam)
	cam.make_current()
	vfx = VFX.new()
	add_child(vfx)
	audio = Audio.new()
	add_child(audio)
	units_root = Node3D.new()
	units_root.name = "Units"
	add_child(units_root)
	hud = HUD.new()
	hud.battle = self
	add_child(hud)
	console = Console.new()
	console.battle = self
	add_child(console)

	hud.skill_pressed.connect(_on_skill_pressed)
	hud.portrait_pressed.connect(func(u): _try_target(u))
	hud.auto_toggled.connect(func(): set_auto(not auto_battle))
	hud.speed_pressed.connect(func(): set_speed(speed_mult % 3 + 1))
	hud.runes_pressed.connect(_open_board)
	hud.console_pressed.connect(func(): console.toggle())
	hud.next_pressed.connect(func(): start_battle())
	hud.retry_pressed.connect(_retry)

	_setup_cli(args)
	start_battle()


func _setup_cli(args: PackedStringArray) -> void:
	if _autotest:
		set_auto(true)
		audio.muted = true
		set_speed(3)
		Engine.time_scale = 10.0
		get_tree().create_timer(300.0, true, false, true).timeout.connect(func():
			printerr("AUTOTEST TIMEOUT")
			get_tree().quit(1))
	var shot := ""
	var delay := 5.0
	for a in args:
		if a.begins_with("--po-screenshot="):
			shot = a.get_slice("=", 1)
		elif a.begins_with("--po-shot-delay="):
			delay = float(a.get_slice("=", 1))
	if shot != "":
		get_tree().create_timer(delay, true, false, true).timeout.connect(func():
			if "--po-shot-board" in args:
				_open_board()
				await get_tree().process_frame
				await get_tree().process_frame
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot)
			print("screenshot saved: ", shot)
			get_tree().quit(0))


# --- Battle setup ---------------------------------------------------------------------
func start_battle() -> void:
	serial += 1
	var my := serial
	player_action.emit({})
	state = State.INTRO
	current_unit = null
	hovered = null
	for u in units:
		if is_instance_valid(u):
			u.queue_free()
	units.clear()
	hud.hide_result()
	hud.hide_skills()
	hud.clear_log()
	_stats = {"turns": 0, "reactions": 0, "crits": 0}

	var team: Array = profile.team_monsters()
	var leader: Dictionary = Data.SPECIES[team[0].species].leader if team.size() > 0 else {}
	for i in mini(team.size(), 4):
		var m: Dictionary = team[i]
		var st := Data.compute_stats(m.species, int(m.level), profile.runes_of(m), leader)
		_spawn(m.species, 0, i, int(m.level), st, false)

	var wave := int(profile.data.wave)
	var pool: Array = Data.SPECIES_ORDER.duplicate()
	pool.shuffle()
	var boss_wave := wave % 5 == 0
	var lvl := 3 + wave * 2
	var grade := clampi(floori((wave - 1) / 4.0), 0, 2)
	var e_leader: Dictionary = Data.SPECIES[pool[0]].leader
	for i in 4:
		var runes: Array = []
		for slot in 6:
			runes.append(Data.make_rune(rng, slot, grade))
		var st := Data.compute_stats(pool[i], lvl, runes, e_leader)
		var boss := boss_wave and i == 1
		if boss:
			st.hp = roundf(st.hp * 2.6)
			st.atk = roundf(st.atk * 1.15)
		_spawn(pool[i], 1, i, lvl, st, boss)

	hud.setup_units(units, wave, int(profile.data.wins), int(profile.data.losses))
	var leader_sp: Dictionary = Data.SPECIES[team[0].species] if team.size() > 0 else {}
	if not leader_sp.is_empty():
		hud.log_line("[color=#e6b35f]队长技[/color] %s：全队%s" % [leader_sp.name, Data.stat_text(leader.stat, leader.value)])
	hud.log_line("[color=#8fb8ff]提示[/color]：用不同元素攻击带[b]印记[/b]的敌人触发[b]元素裂变[/b]（点“裂变表”查看）")
	cam.set_view(Vector3(0, 26, 30), Vector3(0, 0, 0), 1.0, true)
	cam.overview(1.3)
	for i in units.size():
		units[i].anim_spawn(0.15 + i * 0.09)
	await _wait(1.3)
	if my != serial:
		return
	hud.banner("星轨第 %d 层" % wave, HUD.BRASS, "首领战！" if boss_wave else "4 v 4 · 元素裂变")
	audio.play("turn")
	state = State.TICKING


func _spawn(sid: String, team: int, idx: int, lvl: int, st: Dictionary, boss: bool) -> void:
	var u := Unit.new()
	u.is_boss = boss
	u.setup(sid, team, lvl, st)
	units_root.add_child(u)
	var x: float = SLOTS_X[idx]
	var z := TEAM_Z + (0.7 if absf(x) < 3.0 else 0.0)
	if team == 1:
		z = -z
	u.global_position = Vector3(x, 0, z)
	u.look_at(Vector3(x * 0.5, 0, -z), Vector3.UP)
	u.home = u.global_position
	u.home_basis = u.global_basis
	units.append(u)


func _retry() -> void:
	if _last_victory:
		profile.data.wave = maxi(1, int(profile.data.wave) - 1)
	start_battle()


# --- Queries ----------------------------------------------------------------------------
func _alive_team(team: int) -> Array:
	return units.filter(func(u): return is_instance_valid(u) and u.alive and u.team == team)


func _allies(u: Node) -> Array:
	return _alive_team(u.team)


func _enemies(u: Node) -> Array:
	return _alive_team(1 - u.team)


func _team_center(team: int) -> Vector3:
	return Vector3(0, 0, TEAM_Z if team == 0 else -TEAM_Z)


func _ok(my: int) -> bool:
	return my == serial and state != State.ENDED


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func hud_current_unit() -> Node:
	return current_unit if state == State.WAIT_INPUT else null


# --- ATB engine ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	hud.update_units(cam)
	if state != State.TICKING or hud.is_modal_open():
		return
	if cheat_max_atb:
		for u in _alive_team(0):
			u.atb = maxf(u.atb, 100.0)
	tick_accum += delta * TICK_RATE
	while tick_accum >= 1.0:
		tick_accum -= 1.0
		var ready := _ready_unit()
		if ready == null:
			for u in units:
				if u.alive:
					u.atb += u.eff_spd() * Data.ATB_PER_SPD
			ready = _ready_unit()
		if ready:
			tick_accum = 0.0
			_run_turn(ready)
			return
	_order_timer -= delta
	if _order_timer <= 0.0:
		_order_timer = 0.25
		_update_order()


func _ready_unit() -> Node:
	var best: Node = null
	for u in units:
		if not u.alive or u.atb < 100.0:
			continue
		if best == null or u.atb > best.atb or (u.atb == best.atb and u.eff_spd() > best.eff_spd()):
			best = u
	return best


## Simulates the ATB forward (ignoring future effects) to forecast turn order.
func _predict_order(count: int) -> Array:
	var sim := {}
	for u in units:
		if u.alive:
			sim[u] = u.atb
	var out: Array = []
	var guard := 0
	while out.size() < count and not sim.is_empty() and guard < 5000:
		guard += 1
		var best: Node = null
		for u in sim:
			if sim[u] >= 100.0 and (best == null or sim[u] > sim[best] or (sim[u] == sim[best] and u.eff_spd() > best.eff_spd())):
				best = u
		if best:
			out.append(best)
			sim[best] = 0.0
		else:
			for u in sim:
				sim[u] += u.eff_spd() * Data.ATB_PER_SPD
	return out


func _update_order() -> void:
	var order: Array = []
	if current_unit and current_unit.alive:
		order.append(current_unit)
	order.append_array(_predict_order(8 - order.size()))
	hud.update_turn_order(order)


# --- Turn flow ------------------------------------------------------------------------------
func _run_turn(u: Node) -> void:
	var my := serial
	state = State.BUSY
	current_unit = u
	u.atb = 0.0
	_stats.turns += 1
	_update_order()
	u.set_active(true)
	audio.play("turn", -6.0)
	for i in 3:
		u.cooldowns[i] = maxi(0, int(u.cooldowns[i]) - 1)
	u.set_meta("killed", false)

	# start-of-turn passives
	if u.passive_id == "moon_dew":
		var low: Array = _allies(u)
		low.sort_custom(func(a, b): return a.hp_ratio() < b.hp_ratio())
		if low.size() > 0 and low[0].hp_ratio() < 1.0:
			_heal(low[0], low[0].max_hp * 0.08)
	elif u.passive_id == "clear_glaze":
		for s in u.statuses:
			if not Data.STATUS[s.id].buff:
				u.statuses.erase(s)
				vfx.text(u.head_position(), "净釉", Color(1, 0.95, 0.7), 40)
				break

	var dots: int = u.count_status("dot")
	if dots > 0:
		_deal_damage(null, u, u.max_hp * Data.DOT_PCT * dots, {"dot": true})
		await _wait(0.45)
		if not _ok(my):
			return
		if not u.alive:
			_finish_turn(u, my)
			return

	if u.has_status("stun") or u.has_status("freeze"):
		var frozen: bool = u.has_status("freeze")
		vfx.text(u.head_position(), "冰冻中" if frozen else "眩晕中", Color(0.6, 0.9, 1.0) if frozen else Color(1, 0.85, 0.2), 52)
		hud.log_line("%s %s，跳过回合" % [_name(u), "被冰冻" if frozen else "眩晕"])
		await _wait(0.7)
		if not _ok(my):
			return
		u.tick_statuses()
		_finish_turn(u, my)
		return

	var choice: Dictionary
	if u.team == 1 or auto_battle:
		cam.over_shoulder(u.global_position, _team_center(1 - u.team))
		await _wait(0.4)
		if not _ok(my):
			return
		choice = _ai_choose(u)
	else:
		choice = await _player_choose(u)
		if not _ok(my) or choice.is_empty():
			return
	await _execute(u, int(choice.skill), choice.target, my)
	if not _ok(my):
		return
	u.tick_statuses()
	var extra := false
	if u.alive and u.passive_id == "tailwind" and rng.randf() < 0.2:
		extra = true
	if u.alive and u.passive_id == "oil_spot" and u.get_meta("killed", false):
		extra = true
	if extra and not _enemies(u).is_empty():
		u.atb = 100.5
		vfx.text(u.head_position() + Vector3.UP * 0.6, "额外回合!", Color(0.5, 1.0, 0.8), 60)
		hud.log_line("%s 触发被动，获得[b]额外回合[/b]" % _name(u))
	_finish_turn(u, my)


func _finish_turn(u: Node, my: int) -> void:
	if my != serial:
		return
	if is_instance_valid(u):
		u.set_active(false)
	current_unit = null
	if _check_end():
		return
	cam.overview(2.2)
	state = State.TICKING


func _check_end() -> bool:
	if state == State.ENDED:
		return true
	if _alive_team(1).is_empty():
		_end_battle(true)
		return true
	if _alive_team(0).is_empty():
		_end_battle(false)
		return true
	return false


# --- Player input ------------------------------------------------------------------------------
func _player_choose(u: Node) -> Dictionary:
	state = State.WAIT_INPUT
	selected_skill = 2 if u.ultimate_ready() else 0
	cam.over_shoulder(u.global_position, _team_center(1 - u.team))
	_refresh_targeting()
	hud.set_hint("点击目标释放 · [1][2][3] 切换技能 · [空格] 自动选目标 · 绿▲克制 红▼被克")
	var choice: Dictionary = await player_action
	if state == State.WAIT_INPUT:
		state = State.BUSY
	_clear_highlights()
	hud.hide_skills()
	return choice


func _skill_usable(u: Node, i: int) -> bool:
	if cheat_no_cd:
		return true
	if i == 2:
		return u.ultimate_ready()
	return int(u.cooldowns[i]) <= 0


func _valid_targets(u: Node, i: int) -> Array:
	var sk: Dictionary = u.skills[i]
	return _enemies(u) if sk.target in ["enemy", "all_enemies"] else _allies(u)


func _on_skill_pressed(i: int) -> void:
	if state != State.WAIT_INPUT or current_unit == null:
		return
	if not _skill_usable(current_unit, i):
		return
	audio.play("ui")
	var sk: Dictionary = current_unit.skills[i]
	if selected_skill == i and sk.target != "enemy":
		# second press on an area skill confirms it
		player_action.emit({"skill": i, "target": _valid_targets(current_unit, i)[0]})
		return
	selected_skill = i
	_refresh_targeting()


func _try_target(t: Node) -> void:
	if state != State.WAIT_INPUT or current_unit == null or t == null or not t.alive:
		return
	if t in _valid_targets(current_unit, selected_skill) and _skill_usable(current_unit, selected_skill):
		player_action.emit({"skill": selected_skill, "target": t})


func _refresh_targeting() -> void:
	if current_unit == null:
		return
	hud.show_skills(current_unit, selected_skill, cheat_no_cd)
	var sk: Dictionary = current_unit.skills[selected_skill]
	var valid := _valid_targets(current_unit, selected_skill)
	var area: bool = sk.target != "enemy"
	var hover_valid := hovered != null and hovered in valid
	var offensive: bool = sk.target != "all_allies"
	for u in units:
		if not u.alive:
			continue
		if u in valid:
			var mode := 2 if (hover_valid and (area or u == hovered)) else 1
			u.set_target_highlight(mode, Data.affinity(current_unit.element, u.element), offensive)
		else:
			u.set_target_highlight(0)
	if hover_valid:
		hud.set_preview(_preview_text(current_unit, hovered, selected_skill))


func _clear_highlights() -> void:
	for u in units:
		if is_instance_valid(u):
			u.set_target_highlight(0)


func _preview_text(c: Node, t: Node, i: int) -> String:
	var sk: Dictionary = c.skills[i]
	var txt := "[color=#e6b35f][b]%s[/b][/color] → %s\n" % [sk.name, _name(t)]
	if sk.mult > 0.0:
		var aff := Data.affinity(c.element, t.element)
		var base := _base_damage(c, t, sk, aff) * int(sk.hits)
		var crit := base * (1.0 + float(c.stats.crit_dmg) / 100.0)
		var cr := minf(100.0, float(c.stats.crit_rate) + (Data.ADV_CRIT_BONUS if aff == 1 else 0.0))
		var aff_txt: String = ["[color=#ff6a5a]▼被克制（30%偏斜）[/color]", "[color=#e8d27a]◆无克制[/color]", "[color=#6dff8a]▲克制 +30%伤害[/color]"][aff + 1]
		txt += "预计伤害 [b]%d[/b] · 暴击 [b]%d[/b]（暴击率 %d%%） %s" % [base, crit, cr, aff_txt]
		if t.hp <= base:
			txt += "  [color=#ff5050][b]可击杀[/b][/color]"
		var re := Data.reaction(t.mark, c.element)
		if re != "":
			txt += "\n[color=#ffcc55]将触发元素裂变【%s】[/color]：%s" % [Data.REACTIONS[re].name, Data.REACTIONS[re].desc]
		for eff in sk.effects:
			if eff.type == "debuff":
				var resist := maxf(Data.MIN_RESIST, float(t.stats.res) - float(c.stats.acc))
				var land := float(eff.chance) * (1.0 - resist / 100.0)
				txt += "\n%s 实际命中率 ≈ %d%%%s" % [Data.STATUS[eff.status].name, land, "（目标免疫）" if t.has_status("immunity") else ""]
	else:
		txt += sk.desc
	return txt


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1, KEY_QUOTELEFT:
				console.toggle()
			KEY_R:
				if hud.is_modal_open():
					hud.close_board()
				else:
					_open_board()
			KEY_ESCAPE:
				if hud.is_modal_open():
					hud.close_board()
			KEY_1, KEY_2, KEY_3:
				_on_skill_pressed(event.keycode - KEY_1)
			KEY_SPACE:
				if state == State.WAIT_INPUT and current_unit:
					var c := _ai_choose(current_unit, selected_skill)
					player_action.emit(c)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		_mouse_moved = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse = event.position
		_pending_click = true


func _physics_process(_delta: float) -> void:
	if state != State.WAIT_INPUT:
		_pending_click = false
		return
	if not (_mouse_moved or _pending_click):
		return
	var hit := _pick(_mouse)
	if _mouse_moved:
		_mouse_moved = false
		if hit != hovered:
			hovered = hit
			_refresh_targeting()
	if _pending_click:
		_pending_click = false
		_try_target(hit)


func _pick(screen: Vector2) -> Node:
	var from := cam.project_ray_origin(screen)
	var to := from + cam.project_ray_normal(screen) * 300.0
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit and hit.collider and hit.collider.has_meta("unit"):
		var u: Node = hit.collider.get_meta("unit")
		if u.alive:
			return u
	return null


# --- AI ------------------------------------------------------------------------------------------
func _ai_choose(u: Node, forced_skill: int = -1) -> Dictionary:
	var skill := 0
	if forced_skill >= 0:
		skill = forced_skill
	else:
		for i in [2, 1, 0]:
			if _skill_usable(u, i) and _ai_worth(u, i):
				skill = i
				break
	var sk: Dictionary = u.skills[skill]
	var target: Node = u
	if sk.target != "all_allies":
		var best_score := -INF
		for t in _enemies(u):
			var score: float = (1.0 - t.hp_ratio()) * 40.0 + rng.randf() * 6.0
			var aff := Data.affinity(u.element, t.element)
			score += 22.0 if aff == 1 else (-18.0 if aff == -1 else 0.0)
			if Data.reaction(t.mark, u.element) != "":
				score += 35.0
			if sk.mult > 0.0 and t.hp <= _base_damage(u, t, sk, aff) * int(sk.hits):
				score += 50.0
			if score > best_score:
				best_score = score
				target = t
	return {"skill": skill, "target": target}


func _ai_worth(u: Node, i: int) -> bool:
	var sk: Dictionary = u.skills[i]
	if sk.target != "all_allies":
		return true
	var heals := false
	for eff in sk.effects:
		if eff.type == "heal_allies" or eff.type == "cleanse_allies":
			heals = true
	if not heals:
		return true
	for a in _allies(u):
		if a.hp_ratio() < 0.7:
			return true
		for s in a.statuses:
			if not Data.STATUS[s.id].buff:
				return true
	return i == 2 and u.skills[2].effects.size() > 2


# --- Skill execution ----------------------------------------------------------------------------
func _execute(c: Node, idx: int, target: Node, my: int) -> void:
	var sk: Dictionary = c.skills[idx]
	if idx == 1:
		c.cooldowns[1] = 0 if cheat_no_cd else int(sk.cd)
	if idx == 2:
		c.energy = 100.0 if cheat_no_cd else 0.0
	else:
		c.gain_energy(Data.ENERGY_PER_ACTION)
	var ecol: Color = Data.ELEMENT_COLORS[c.element]
	hud.log_line("[color=#%s]%s[/color] 使用 [b]%s[/b]" % [ecol.to_html(false), _name(c), sk.name])
	vfx.text(c.head_position() + Vector3.UP * 0.35, sk.name, ecol.lerp(Color.WHITE, 0.3), 50, 0.8, 1.0)

	var targets: Array = []
	match sk.target:
		"enemy":
			targets = [target]
		"all_enemies":
			targets = _enemies(c)
		"all_allies":
			targets = _allies(c)
	var focus: Vector3 = target.global_position if sk.target == "enemy" else _team_center(targets[0].team if targets.size() > 0 else 1 - c.team)
	c.face_towards(focus)

	match sk.anim:
		"melee":
			cam.focus_on(focus, c.global_position - focus, 6.5, 2.4, 4.0)
			audio.play(audio.element_sfx(c.element), -4.0)
			await c.anim_lunge(focus)
		"projectile":
			audio.play(audio.element_sfx(c.element), -4.0)
			await c.anim_cast()
		"cast":
			audio.play(audio.element_sfx(c.element))
			vfx.ring(c.global_position, ecol, 3.0, 0.6)
			vfx.buff_fx(c.center_position(), ecol)
			await c.anim_cast()
		"ultimate":
			audio.play("ultimate")
			hud.banner(sk.name, ecol, "奥 义")
			cam.focus_on(c.global_position, focus - c.global_position, 5.5, 1.8, 5.0)
			vfx.pillar(c.global_position, ecol)
			vfx.ring(c.global_position, ecol, 4.0, 0.8)
			await c.anim_ultimate()
			if not _ok(my):
				return
			if sk.target == "enemy":
				cam.focus_on(focus, c.global_position - focus, 7.0, 2.8, 5.0)
			else:
				cam.set_view(Vector3(0, 11, _team_center(c.team).z * 2.6), focus, 4.0)
	if not _ok(my):
		return

	if sk.mult > 0.0:
		var glanced := {}
		var reacted := {}
		for h in int(sk.hits):
			if sk.anim == "projectile":
				var last: Node = null
				for t in targets:
					if t.alive:
						last = t
						vfx.projectile(c.muzzle_position(), t.center_position(), ecol, 0.3)
				if last:
					await _wait(0.3)
			elif sk.target == "all_enemies":
				for t in targets:
					if t.alive:
						vfx.shockwave(t.center_position(), ecol)
			if not _ok(my):
				return
			for t in targets:
				if not t.alive:
					continue
				var r := _roll_hit(c, t, sk)
				_apply_hit(c, t, r, reacted)
				if r.glancing:
					glanced[t] = true
			await _wait(0.22 if int(sk.hits) > 1 else 0.14)
			if not _ok(my):
				return
		for t in targets:
			if not t.alive:
				continue
			for eff in sk.effects:
				if eff.type == "debuff" and not glanced.has(t):
					_try_debuff(c, t, eff.status, int(eff.turns), float(eff.chance))
				elif eff.type == "atb_reduce" and not glanced.has(t):
					_try_atb_reduce(c, t, float(eff.amount), float(eff.chance))

	for eff in sk.effects:
		match eff.type:
			"heal_allies":
				for a in _allies(c):
					_heal(a, a.max_hp * float(eff.pct) / 100.0)
				audio.play("heal")
			"cleanse_allies":
				for a in _allies(c):
					if a.remove_debuffs() > 0:
						vfx.text(a.head_position() + Vector3.UP * 0.4, "净化", Color(0.8, 1.0, 1.0), 44)
			"buff_allies":
				for a in _allies(c):
					_buff(a, eff.status, int(eff.turns))
				audio.play("buff")
			"buff_self":
				_buff(c, eff.status, int(eff.turns))
				audio.play("buff")
			"atb_boost_allies":
				for a in _allies(c):
					if a != c:
						a.atb = minf(a.atb + float(eff.amount), 100.0)
						vfx.text(a.head_position() + Vector3.UP * 0.2, "攻击条+%d%%" % int(eff.amount), Color(0.55, 0.9, 1.0), 40)
	await _wait(0.45)
	if not _ok(my):
		return
	if sk.anim == "melee" and c.alive:
		await c.anim_return()
	else:
		c.reset_facing()


# --- Combat math ----------------------------------------------------------------------------
func _base_damage(c: Node, t: Node, sk: Dictionary, aff: int) -> float:
	var d: float = c.eff_atk() * float(sk.mult) * 1000.0 / (1140.0 + 3.5 * t.eff_def())
	if aff == 1:
		d *= Data.ADV_DAMAGE_MULT
	elif aff == -1:
		d *= Data.DISADV_DAMAGE_MULT
	match c.passive_id:
		"molten_core":
			if t.has_status("dot"):
				d *= 1.25
		"hairline":
			if t.hp_ratio() < 0.5:
				d *= 1.4
	if t.passive_id == "fired_shell" and t.hp_ratio() > 0.5:
		d *= 0.8
	return d


func _roll_hit(c: Node, t: Node, sk: Dictionary) -> Dictionary:
	var aff := Data.affinity(c.element, t.element)
	var crit_rate := float(c.stats.crit_rate) + (Data.ADV_CRIT_BONUS if aff == 1 else 0.0)
	var glancing := aff == -1 and rng.randf() < Data.GLANCING_CHANCE
	var crit := not glancing and rng.randf() * 100.0 < crit_rate
	var crushing := aff == 1 and not crit and rng.randf() < Data.CRUSHING_CHANCE
	var dmg := _base_damage(c, t, sk, aff)
	if crit:
		dmg *= 1.0 + float(c.stats.crit_dmg) / 100.0
	if glancing:
		dmg *= Data.GLANCING_MULT
	if crushing:
		dmg *= Data.CRUSHING_MULT
	dmg *= rng.randf_range(0.95, 1.05)
	return {"aff": aff, "crit": crit, "glancing": glancing, "crushing": crushing, "dmg": dmg}


func _apply_hit(c: Node, t: Node, r: Dictionary, reacted: Dictionary) -> void:
	var ecol: Color = Data.ELEMENT_COLORS[c.element]
	var top: Vector3 = t.head_position() + Vector3.UP * 0.5
	if r.crit:
		_stats.crits += 1
		vfx.text(top, "暴击!", Color(1.0, 0.7, 0.2), 48, 1.0, 0.9)
		cam.shake(0.45)
	elif r.glancing:
		vfx.text(top, "偏斜", Color(0.7, 0.7, 0.75), 40, 1.0, 0.9)
	elif r.crushing:
		vfx.text(top, "碾压!", Color(1.0, 0.4, 0.35), 44, 1.0, 0.9)
	if r.aff == 1 and not reacted.has(t):
		vfx.text(top + Vector3.UP * 0.3, "克制▲", Color(0.45, 1.0, 0.5), 34, 1.0, 0.9)
	vfx.sparks(t.center_position(), ecol)
	_deal_damage(c, t, r.dmg, r)
	if t.alive:
		t.gain_energy(Data.ENERGY_ON_HIT)
		if t.passive_id == "stoked":
			t.atb = minf(t.atb + 10.0, 100.0)
	if not reacted.has(t):
		reacted[t] = true
		_element_mark(c, t, float(r.dmg))


func _deal_damage(src: Node, t: Node, amount: float, info: Dictionary) -> void:
	if not t.alive:
		return
	amount = roundf(maxf(amount, 1.0))
	t.hp = maxf(0.0, t.hp - amount)
	var crit: bool = info.get("crit", false)
	var col := Color(1, 0.97, 0.9)
	if crit:
		col = Color(1.0, 0.75, 0.25)
	elif info.get("dot", false):
		col = Color(0.8, 0.45, 1.0)
	vfx.text(t.head_position(), str(int(amount)), col, 72 if crit else 58)
	t.anim_hit(crit)
	audio.play("crit" if crit else "hit", -3.0)
	if t.hp <= 0.0:
		_kill(t, src)


func _kill(t: Node, src: Node) -> void:
	t.alive = false
	t.hp = 0.0
	t.statuses.clear()
	t.mark = -1
	t.anim_death()
	audio.play("shatter")
	cam.shake(0.3)
	hud.log_line("[color=#ff8080]%s 碎裂了[/color]" % _name(t))
	if src and is_instance_valid(src):
		src.gain_energy(Data.ENERGY_ON_KILL)
		src.set_meta("killed", true)


func _heal(t: Node, amount: float) -> void:
	if not t.alive:
		return
	var before: float = t.hp
	t.hp = minf(t.max_hp, t.hp + amount)
	vfx.text(t.head_position(), "+%d" % int(t.hp - before), Color(0.45, 1.0, 0.55), 52)
	vfx.heal_fx(t.global_position)


func _buff(t: Node, status: String, turns: int) -> void:
	if not t.alive:
		return
	t.add_status(status, turns)
	var info: Dictionary = Data.STATUS[status]
	vfx.text(t.head_position() + Vector3.UP * 0.3, info.name, info.color, 38)
	vfx.buff_fx(t.center_position(), info.color)


func _try_debuff(c: Node, t: Node, status: String, turns: int, chance: float) -> void:
	if rng.randf() * 100.0 >= chance:
		return
	if t.has_status("immunity"):
		vfx.text(t.head_position() + Vector3.UP * 0.3, "免疫", Color(1, 0.95, 0.6), 40)
		return
	var resist := maxf(Data.MIN_RESIST, float(t.stats.res) - float(c.stats.acc))
	if rng.randf() * 100.0 < resist:
		vfx.text(t.head_position() + Vector3.UP * 0.3, "抵抗!", Color(0.75, 0.8, 1.0), 40)
		return
	t.add_status(status, turns)
	var info: Dictionary = Data.STATUS[status]
	vfx.text(t.head_position() + Vector3.UP * 0.3, info.name, info.color, 40)
	audio.play("debuff", -6.0)


func _try_atb_reduce(c: Node, t: Node, amount: float, chance: float) -> void:
	if rng.randf() * 100.0 >= chance or t.has_status("immunity"):
		return
	var resist := maxf(Data.MIN_RESIST, float(t.stats.res) - float(c.stats.acc))
	if rng.randf() * 100.0 < resist:
		vfx.text(t.head_position() + Vector3.UP * 0.3, "抵抗!", Color(0.75, 0.8, 1.0), 40)
		return
	t.atb = maxf(0.0, t.atb - amount)
	vfx.text(t.head_position() + Vector3.UP * 0.3, "攻击条-%d%%" % int(amount), Color(0.5, 0.8, 1.0), 40)


# --- Element Fission ----------------------------------------------------------------------------
func _element_mark(c: Node, t: Node, dmg: float) -> void:
	if not t.alive:
		return
	var old: int = t.mark
	var re := Data.reaction(old, c.element)
	if re == "":
		t.mark = c.element
		t.mark_turns = Data.MARK_TURNS
		return
	t.mark = -1
	_stats.reactions += 1
	var info: Dictionary = Data.REACTIONS[re]
	var c1: Color = Data.ELEMENT_COLORS[old]
	var c2: Color = Data.ELEMENT_COLORS[c.element]
	vfx.text(t.head_position() + Vector3.UP * 1.0, "裂变·%s" % info.name, c1.lerp(c2, 0.5).lerp(Color.WHITE, 0.2), 80, 1.6, 1.4)
	vfx.burst(t.center_position(), c1, 60, 9.0, 0.35)
	vfx.burst(t.center_position(), c2, 60, 9.0, 0.35)
	vfx.shockwave(t.center_position(), c2)
	vfx.flash(t.center_position(), c2, 10.0, 0.5)
	audio.play("reaction")
	cam.shake(0.35)
	hud.banner("元素裂变 · %s" % info.name, c2.lerp(Color.WHITE, 0.25), "%s  —  %s" % [info.en, info.desc])
	arena.pulse_element(old)
	arena.pulse_element(c.element)
	hud.log_line("[color=#ffcc55]★ 元素裂变【%s】[/color] %s+%s → %s" % [info.name, Data.ELEMENT_NAMES[old], Data.ELEMENT_NAMES[c.element], _name(t)])
	match re:
		"wildfire":
			for o in _alive_team(t.team):
				if o != t:
					vfx.burst(o.center_position(), Data.ELEMENT_COLORS[Data.Element.FIRE], 40, 6.0)
					_deal_damage(c, o, dmg * 0.4, {})
		"steam":
			t.atb = maxf(0.0, t.atb - 40.0)
			vfx.text(t.head_position() + Vector3.UP * 0.2, "攻击条-40%", Color(0.8, 0.9, 1.0), 44)
		"frost":
			if t.has_status("immunity"):
				vfx.text(t.head_position(), "免疫", Color(1, 0.95, 0.6), 40)
			else:
				t.add_status("freeze", 1)
		"annihilate":
			_deal_damage(c, t, t.max_hp * 0.12, {"crit": true})
		"radiance":
			for a in _allies(c):
				_heal(a, a.max_hp * 0.10)
		"corrode":
			if not t.has_status("immunity"):
				t.add_status("def_break", 2)
				t.add_status("dot", 2)


# --- End of battle -------------------------------------------------------------------------------
func _end_battle(victory: bool) -> void:
	if state == State.ENDED:
		return
	var was_waiting := state == State.WAIT_INPUT
	state = State.ENDED
	_last_victory = victory
	_clear_highlights()
	hud.hide_skills()
	for u in units:
		u.set_active(false)
	if was_waiting:
		player_action.emit({})
	var body := ""
	var wave := int(profile.data.wave)
	if victory:
		audio.play("victory")
		profile.data.wins = int(profile.data.wins) + 1
		var exp_gain := 60 + wave * 20
		for m in profile.team_monsters():
			var lv: int = profile.add_exp(m, exp_gain)
			body += "%s  EXP +%d%s\n" % [Data.full_name(m.species), exp_gain, ("  [color=#ffd060]升级！Lv%d[/color]" % int(m.level)) if lv > 0 else ""]
		body += "\n"
		var max_grade := clampi(floori(wave / 3.0), 0, 2)
		for i in (2 if rng.randf() < 0.5 else 1):
			var r: Dictionary = profile.grant_random_rune(max_grade)
			body += "获得符文：[color=#%s]%s[/color]\n" % [Data.GRADE_COLORS[int(r.grade)].to_html(false), Data.rune_text(r)]
		if rng.randf() < 0.35 or wave % 5 == 0:
			profile.data.scrolls = int(profile.data.scrolls) + 1
			body += "[color=#ffd060]获得 召唤卷轴 ×1[/color]（在符文盘中使用）\n"
		body += "\n本场：%d 回合 · %d 次元素裂变 · %d 次暴击" % [_stats.turns, _stats.reactions, _stats.crits]
		profile.data.wave = wave + 1
		for u in _alive_team(0):
			u.anim_cheer()
		cam.orbit_point(_team_center(0), 9.0, 4.0)
		hud.banner("胜 利", HUD.BRASS)
	else:
		audio.play("defeat")
		profile.data.losses = int(profile.data.losses) + 1
		body = "瓷偶们碎了一地……\n\n试试：调整符文、换队长、或利用[b]元素裂变[/b]组合。\n\n本场：%d 回合 · %d 次元素裂变" % [_stats.turns, _stats.reactions]
		cam.orbit_point(_team_center(1), 9.0, 4.0)
		hud.banner("败 北", HUD.ENEMY_COL)
	profile.save()
	var my := serial
	await _wait(1.4)
	if my != serial:
		return
	hud.show_result(victory, body)
	if _autotest:
		_autotest_done += 1
		print("AUTOTEST battle %d: %s turns=%d reactions=%d crits=%d" % [_autotest_done, "VICTORY" if victory else "DEFEAT", _stats.turns, _stats.reactions, _stats.crits])
		if _autotest_done >= 3:
			print("AUTOTEST OK")
			get_tree().quit(0)
		else:
			start_battle()


# --- Public controls (HUD / console) -------------------------------------------------------------
func set_auto(on: bool) -> void:
	auto_battle = on
	hud.set_auto(on)
	console.sync(on)
	if on and state == State.WAIT_INPUT and current_unit:
		player_action.emit(_ai_choose(current_unit))


func set_speed(mult: int) -> void:
	speed_mult = clampi(mult, 1, 3)
	Engine.time_scale = float(speed_mult)
	hud.set_speed(speed_mult)


func _open_board() -> void:
	hud.open_board(profile)


func cheat_win() -> void:
	if state == State.ENDED or state == State.INTRO:
		return
	for e in _alive_team(1):
		e.hp = 0.0
		e.alive = false
		e.anim_death()
	audio.play("shatter")
	_end_battle(true)


func cheat_kill_all() -> void:
	if state == State.ENDED or state == State.INTRO:
		return
	for e in _alive_team(1):
		vfx.pillar(e.global_position, Color(0.4, 1.0, 0.6), 10.0, 0.6)
		_deal_damage(null, e, e.hp + 1.0, {"crit": true})
	_check_end()


func cheat_heal() -> void:
	for a in _alive_team(0):
		a.hp = a.max_hp
		a.remove_debuffs()
		vfx.heal_fx(a.global_position)


func cheat_runes() -> void:
	for i in 5:
		profile.grant_rune(2)


func cheat_scrolls() -> void:
	profile.data.scrolls = int(profile.data.scrolls) + 3
	profile.save()


func cheat_reset() -> void:
	profile.reset()
	start_battle()


func _name(u: Node) -> String:
	return "[color=#%s]%s%s[/color]" % [("8fd0ff" if u.team == 0 else "ff8a8a"), "" if u.team == 0 else "敌·", u.display_name]
