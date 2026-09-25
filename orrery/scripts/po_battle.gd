extends Node3D
## Goldmend :: one battle (created by po_game.gd for each fight node).
##
## Continuous-tick Attack Bar (ATB) engine: every tick each living unit gains
## SPD x 7% ATB; whoever reaches 100% first acts (ties -> higher SPD).
## On top of that, three porcelain-grounded systems (see docs/DESIGN.md):
##   五行 Five Phases  : 相克 overcoming = more damage and much more crack
##   裂纹/崩裂 Crack    : hits build crack up to a figure's toughness (胎厚); at
##                       full crack it BREAKS: loses 35% Attack Bar, its telegraphed
##                       move is interrupted, takes +30% damage until its next
##                       turn, and suffers a 窑变 effect set by the breaker's element
##   相生 Chains        : an ally whose element feeds yours (木生火 ...) acting right
##                       before you on your side makes your action a chain link
## Enemies telegraph their next move (intent) so the player can plan a break.
##
## Usage: add as child, call begin(allies, enemies, relics), await `finished`.
## Unit spec: {species, level, stats, hp (-1 = full), mends, scars, uid, boss, upgrades}
## `fast = true` runs the same rules with no animation or waiting (balance sim).

const Data = preload("po_data.gd")
const I18n = preload("po_i18n.gd")
const Unit = preload("po_unit.gd")
const VFX = preload("po_vfx.gd")
const Cam = preload("po_camera.gd")
const Arena = preload("po_arena.gd")
const HUD = preload("po_hud.gd")
const Anims = preload("po_anims.gd")

enum State { INTRO, TICKING, BUSY, WAIT_INPUT, ENDED }

signal player_action(choice: Dictionary)
signal finished(victory: bool, report: Dictionary)

const TICK_RATE := 22.0
const SLOTS := {1: [0.0], 2: [-2.0, 2.0], 3: [-3.4, 0.0, 3.4], 4: [-4.8, -1.6, 1.6, 4.8]}
const TEAM_Z := 4.6
## Estimated seconds each animation takes at 1x (used by the fast simulation).
const ANIM_TIME := {"melee": 1.7, "projectile": 1.2, "cast": 1.1, "ultimate": 2.6}

var game: Node
var audio: Node
var relics: Array = []
var units: Array = []
var state := State.INTRO
var tick_accum := 0.0
var auto_battle := false
var cheat_no_cd := false
var cheat_max_atb := false
var rng := RandomNumberGenerator.new()
var current_unit: Node = null
var selected_skill := 0
var hovered: Node = null
var floor_text := ""
var banner_text := ""
var banner_sub := ""
var fast := false
var trace := false                  # print every turn (debugging balance)
var sim_time := 0.0                 # estimated seconds of battle at 1x speed
var traits := [{}, {}]              # active traits per team
var last_element := [-1, -1]        # element of each side's previous action (相生)
var chain_len := [0, 0]

var arena: Node3D
var cam: Camera3D
var vfx: Node3D
var hud: CanvasLayer
var units_root: Node3D

var _mouse := Vector2.ZERO
var _mouse_moved := false
var _pending_click := false
var _order_timer := 0.0
var _gold_dust_used := false
var stats := {"turns": 0, "ally_turns": 0, "breaks": 0, "chains": 0, "max_chain": 0, "crits": 0, "interrupts": 0}


func _ready() -> void:
	rng.randomize()
	arena = Arena.new()
	add_child(arena)
	cam = Cam.new()
	add_child(cam)
	cam.make_current()
	vfx = VFX.new()
	add_child(vfx)
	Anims.audio = audio
	units_root = Node3D.new()
	units_root.name = "Units"
	add_child(units_root)
	hud = HUD.new()
	hud.battle = self
	add_child(hud)
	hud.skill_pressed.connect(_on_skill_pressed)
	if game:
		hud.auto_toggled.connect(func(): game.set_auto(not auto_battle))
		hud.speed_pressed.connect(func(): game.cycle_speed())
		hud.console_pressed.connect(func(): game.toggle_console())


func _has(relic: String) -> bool:
	return relic in relics


func _trait(team: int, id: String) -> int:
	return int(traits[team].get(id, -1))


func _sfx(id: String, db: float = 0.0) -> void:
	if audio and not fast:
		audio.play(id, db)


# --- Setup -------------------------------------------------------------------------------
func begin(allies: Array, enemies: Array, p_relics: Array) -> void:
	relics = p_relics
	state = State.INTRO
	traits[0] = Data.active_traits(allies.map(func(a): return a.species))
	traits[1] = Data.active_traits(enemies.filter(func(e): return e.species != "boss").map(func(e): return e.species))
	for i in allies.size():
		_spawn(allies[i], 0, i, allies.size())
	for i in enemies.size():
		_spawn(enemies[i], 1, i, enemies.size())
	for team in 2:
		var wx := _trait(team, "wuxing")
		for u in _alive_team(team):
			if wx >= 0:
				u.atb = 15.0 * (wx + 1)
	for u in _alive_team(0):
		if _has("quick_fire"):
			u.ult_cost = 70.0
		if _has("first_glaze"):
			u.atb = maxf(u.atb, 40.0)
		if _has("blue_guard"):
			u.add_status("def_up", 2)
	for e in _alive_team(1):
		_plan_intent(e)
	hud.setup_units(units, relics, floor_text, traits)
	hud.set_auto(auto_battle)
	var leader: Node = _alive_team(0)[0] if not _alive_team(0).is_empty() else null
	if leader and not leader.species.leader.is_empty():
		hud.log_line(I18n.s("log_leader", [leader.display_name, Data.stat_text(leader.species.leader.stat, leader.species.leader.value)]))
	hud.log_line(I18n.s("log_tip"))
	if not fast:
		cam.set_view(Vector3(0, 26, 30), Vector3(0, 0, 0), 1.0, true)
		cam.battle_view(Vector3.ZERO, 0.0, 1.3)
		for i in units.size():
			units[i].anim_spawn(0.15 + i * 0.09)
	await _wait(1.3)
	if state == State.ENDED:
		return
	if not fast:
		hud.banner(banner_text, HUD.BRASS, banner_sub)
	_sfx("turn")
	state = State.TICKING


func _spawn(spec: Dictionary, team: int, idx: int, count: int) -> void:
	var u := Unit.new()
	u.is_boss = spec.get("boss", false)
	u.uid = int(spec.get("uid", -1))
	u.mends = int(spec.get("mends", 0))
	u.scars = spec.get("scars", []).duplicate()
	u.upgrades = spec.get("upgrades", []).duplicate()
	u.setup(spec.species, team, int(spec.level), spec.stats)
	var hp: float = float(spec.get("hp", -1.0))
	if hp > 0.0:
		u.hp = minf(hp, u.max_hp)
	units_root.add_child(u)
	var xs: Array = SLOTS[clampi(count, 1, 4)]
	var x: float = xs[idx]
	var z := TEAM_Z + (0.7 if absf(x) < 3.0 else 0.0)
	if u.is_boss:
		z = TEAM_Z + 1.2
	if team == 1:
		z = -z
	u.global_position = Vector3(x, 0, z)
	u.look_at(Vector3(x * 0.5, 0, -z), Vector3.UP)
	u.home = u.global_position
	u.home_basis = u.global_basis
	units.append(u)


# --- Queries ----------------------------------------------------------------------------
func _alive_team(team: int) -> Array:
	return units.filter(func(u): return is_instance_valid(u) and u.alive and u.team == team)


func _allies(u: Node) -> Array:
	return _alive_team(u.team)


func _enemies(u: Node) -> Array:
	return _alive_team(1 - u.team)


func _team_center(team: int) -> Vector3:
	return Vector3(0, 0, TEAM_Z if team == 0 else -TEAM_Z)


func _ok() -> bool:
	return state != State.ENDED and is_inside_tree()


func _wait(t: float) -> void:
	if fast:
		sim_time += t
		return
	await get_tree().create_timer(t).timeout


func hud_current_unit() -> Node:
	return current_unit if state == State.WAIT_INPUT else null


# --- ATB engine ----------------------------------------------------------------------------
func _process(delta: float) -> void:
	if not fast:
		hud.update_units(cam)
	if state != State.TICKING:
		return
	if cheat_max_atb:
		for u in _alive_team(0):
			u.atb = maxf(u.atb, 100.0)
	if fast:
		for _i in 2000:
			var r := _ready_unit()
			if r:
				_run_turn(r)
				return
			_tick()
			sim_time += 1.0 / TICK_RATE
		return
	tick_accum += delta * TICK_RATE
	while tick_accum >= 1.0:
		tick_accum -= 1.0
		var ready := _ready_unit()
		if ready == null:
			_tick()
			ready = _ready_unit()
		if ready:
			tick_accum = 0.0
			_run_turn(ready)
			return
	_order_timer -= delta
	if _order_timer <= 0.0:
		_order_timer = 0.25
		_update_order()


func _tick() -> void:
	for u in units:
		if u.alive:
			u.atb += u.eff_spd() * Data.ATB_PER_SPD


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


## For a forecast, the chain length each entry would reach (0 = no 相生 link).
func chain_forecast(order: Array) -> Array:
	var last := last_element.duplicate()
	var n := chain_len.duplicate()
	var out: Array = []
	for i in order.size():
		var u: Node = order[i]
		if i == 0 and u == current_unit and state != State.TICKING:
			out.append(u.chain)
			last[u.team] = u.element
			n[u.team] = u.chain
			continue
		var link := int(n[u.team]) + 1 if (int(last[u.team]) >= 0 and Data.generates(int(last[u.team]), u.element)) else 0
		link = mini(link, Data.CHAIN_MAX)
		out.append(link)
		last[u.team] = u.element
		n[u.team] = link
	return out


func _update_order() -> void:
	var order: Array = []
	if current_unit and current_unit.alive:
		order.append(current_unit)
	order.append_array(_predict_order(8 - order.size()))
	hud.update_turn_order(order, chain_forecast(order))


# --- Turn flow ------------------------------------------------------------------------------
func _run_turn(u: Node) -> void:
	state = State.BUSY
	current_unit = u
	if trace:
		print("TRACE t%d %s%s atb=%.0f spd=%.0f | %s" % [stats.turns, "A " if u.team == 0 else "E ", u.species_id, u.atb, u.eff_spd(),
			" ".join(units.filter(func(x): return x.alive).map(func(x): return "%s%s:%.0f/%s" % ["a" if x.team == 0 else "e", x.species_id.substr(0, 4), x.atb, str(x.statuses.map(func(st): return st.id))]))])
	u.atb = 0.0
	stats.turns += 1
	if u.team == 0:
		stats.ally_turns += 1
	# a broken figure pulls itself together when its turn comes round
	if u.broken:
		u.broken = false
		u.crack = 0.0
	# chain link this action would make (committed when it acts)
	var link := 0
	if int(last_element[u.team]) >= 0 and Data.generates(int(last_element[u.team]), u.element):
		link = mini(int(chain_len[u.team]) + 1, Data.CHAIN_MAX)
	u.chain = link
	if not fast:
		_update_order()
	u.set_active(true)
	_sfx("turn", -6.0)
	for i in 3:
		u.cooldowns[i] = maxi(0, int(u.cooldowns[i]) - 1)
	u.set_meta("killed", false)

	if u.passive_id == "moon_dew":
		var low: Array = _allies(u)
		low.sort_custom(func(a, b): return a.hp_ratio() < b.hp_ratio())
		if low.size() > 0 and low[0].hp_ratio() < 1.0:
			_heal(low[0], low[0].max_hp * 0.06)
	elif u.passive_id == "clear_glaze":
		for s in u.statuses:
			if not Data.STATUS[s.id].buff:
				u.statuses.erase(s)
				_text(u.head_position(), I18n.s("cleansed"), Color(1, 0.95, 0.7), 40)
				break

	var dots: int = u.count_status("dot")
	if dots > 0:
		var pct := 0.08 if (u.team == 1 and _has("ember_glaze")) else Data.DOT_PCT
		_deal_damage(null, u, u.max_hp * pct * dots, {"dot": true})
		await _wait(0.45)
		if not _ok():
			return
		if not u.alive:
			_finish_turn(u)
			return

	if u.has_status("stun") or u.has_status("freeze"):
		var frozen: bool = u.has_status("freeze")
		_text(u.head_position(), I18n.s("frozen_skip" if frozen else "stunned_skip"), Color(0.6, 0.9, 1.0) if frozen else Color(1, 0.85, 0.2), 52)
		hud.log_line(I18n.s("log_skip", [_name(u)]))
		# losing a turn breaks your side's chain
		last_element[u.team] = -1
		chain_len[u.team] = 0
		await _wait(0.7)
		if not _ok():
			return
		u.tick_statuses()
		if u.team == 1:
			_plan_intent(u)
		_finish_turn(u)
		return

	var choice: Dictionary
	if u.team == 1:
		if not fast:
			cam.battle_view(u.global_position, 0.1)
		await _wait(0.4)
		if not _ok():
			return
		choice = _intent_choice(u)
	elif auto_battle:
		if not fast:
			cam.battle_view(u.global_position, 0.1)
		await _wait(0.4)
		if not _ok():
			return
		choice = _ai_choose(u)
	else:
		choice = await _player_choose(u)
		if not _ok() or choice.is_empty():
			return
	_commit_chain(u)
	await _execute(u, int(choice.skill), choice.target)
	if not _ok():
		return
	u.tick_statuses()
	var extra := false
	if u.alive and u.passive_id == "tailwind" and rng.randf() < 0.2:
		extra = true
	if u.alive and u.passive_id == "oil_spot" and u.get_meta("killed", false):
		extra = true
	if extra and not _enemies(u).is_empty():
		u.atb = 100.5
		_text(u.head_position() + Vector3.UP * 0.6, I18n.s("extra_turn"), Color(0.5, 1.0, 0.8), 60)
		hud.log_line(I18n.s("log_extra", [_name(u)]))
	if u.alive and u.team == 1:
		_plan_intent(u)
	_finish_turn(u)


## Locks in this action's 相生 link: bonus energy, banner, and the Monochrome heal.
func _commit_chain(u: Node) -> void:
	last_element[u.team] = u.element
	chain_len[u.team] = u.chain
	if u.chain <= 0:
		return
	stats.chains += 1
	if u.team == 0:
		stats.max_chain = maxi(stats.max_chain, u.chain)
	var energy := Data.CHAIN_ENERGY + (15.0 if (u.team == 0 and _has("linked_kilns")) else 0.0)
	u.gain_energy(energy)
	if _trait(u.team, "mono") >= 1:
		_heal(u, u.max_hp * 0.06)
	var prev: int = Data.SHENG.find_key(u.element)
	var col: Color = Data.ELEMENT_COLORS[u.element]
	_text(u.head_position() + Vector3.UP * 0.9, I18n.s("chain_pop", [u.chain]), col.lerp(Color.WHITE, 0.35), 58, 1.2, 1.2)
	if not fast:
		arena.pulse_element(prev)
		arena.pulse_element(u.element)
		_sfx("reaction", -6.0)
	hud.log_line(I18n.s("log_chain", [I18n.element(prev), I18n.element(u.element), _name(u), u.chain, int(round(_chain_damage(u) * 100.0 - 100.0))]))


func _finish_turn(u: Node) -> void:
	if not _ok():
		return
	if is_instance_valid(u):
		u.set_active(false)
		u.chain = 0
	current_unit = null
	if _check_end():
		return
	if not fast:
		cam.battle_view()
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


# --- Enemy intents -------------------------------------------------------------------------------
## Enemies decide their next move right after acting and show it above their head.
func _plan_intent(e: Node) -> void:
	if not e.alive:
		e.intent = {}
		return
	var c := _ai_choose(e, -1, true)
	e.intent = {"skill": int(c.skill), "target": c.target}


## The telegraphed move, re-targeted if its target is gone or it can no longer be used.
func _intent_choice(e: Node) -> Dictionary:
	var it: Dictionary = e.intent
	e.intent = {}
	if it.is_empty() or not _skill_usable(e, int(it.skill)):
		return _ai_choose(e)
	var sk: Dictionary = e.skills[int(it.skill)]
	var t = it.target
	if sk.target == "enemy" and (t == null or not is_instance_valid(t) or not t.alive):
		return _ai_choose(e, int(it.skill))
	if sk.target != "enemy":
		t = _valid_targets(e, int(it.skill))[0]
	return {"skill": int(it.skill), "target": t}


## True for intents worth interrupting (skills and ultimates, not basic attacks).
func intent_threat(e: Node) -> bool:
	return not e.intent.is_empty() and int(e.intent.skill) > 0


# --- Player input ------------------------------------------------------------------------------
func _player_choose(u: Node) -> Dictionary:
	state = State.WAIT_INPUT
	selected_skill = 2 if u.ultimate_ready() else 0
	cam.battle_view(u.global_position, 0.12)
	_refresh_targeting()
	hud.set_hint(I18n.s("battle_hint"))
	var choice: Dictionary = await player_action
	if state == State.WAIT_INPUT:
		state = State.BUSY
	_clear_highlights()
	hud.hide_skills()
	hud.hide_tip(self)
	return choice


func _skill_usable(u: Node, i: int, planning: bool = false) -> bool:
	if cheat_no_cd and u.team == 0:
		return true
	if i == 2:
		return u.ultimate_ready()
	return int(u.cooldowns[i]) <= (1 if planning else 0)


func _valid_targets(u: Node, i: int) -> Array:
	var sk: Dictionary = u.skills[i]
	return _enemies(u) if sk.target in ["enemy", "all_enemies"] else _allies(u)


func _on_skill_pressed(i: int) -> void:
	if state != State.WAIT_INPUT or current_unit == null:
		return
	if not _skill_usable(current_unit, i):
		return
	_sfx("ui")
	var sk: Dictionary = current_unit.skills[i]
	if selected_skill == i and sk.target != "enemy":
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
		hud.show_tip(_preview_text(current_unit, hovered, selected_skill), self)
	elif hovered and hovered.alive:
		hud.show_tip(hud.unit_tip(hovered), self)
	else:
		hud.hide_tip(self)


func _clear_highlights() -> void:
	for u in units:
		if is_instance_valid(u):
			u.set_target_highlight(0)


func _preview_text(c: Node, t: Node, i: int) -> String:
	var sk: Dictionary = c.skills[i]
	var txt := "[color=#e6b35f][b]%s[/b][/color] → %s\n" % [I18n.f(sk, "name"), t.display_name]
	if c.chain > 0:
		txt += I18n.s("preview_chain", [c.chain, int(round(_chain_damage(c) * 100.0 - 100.0))]) + "\n"
	if sk.mult > 0.0:
		var aff := Data.affinity(c.element, t.element)
		var base := _base_damage(c, t, sk, aff) * int(sk.hits)
		var crit := base * (1.0 + float(c.stats.crit_dmg) / 100.0)
		txt += I18n.s("preview_dmg", [base, crit, int(c.stats.crit_rate)]) + " " + I18n.s(["aff_down", "aff_none", "aff_up"][aff + 1])
		if t.hp + t.shield <= base:
			txt += I18n.s("can_kill")
		if t.broken:
			txt += "\n" + I18n.s("preview_broken")
		else:
			var cr := _crack_amount(c, t, sk, aff) * int(sk.hits)
			txt += "\n" + I18n.s("preview_crack", [int(cr), int(t.crack), int(t.toughness)])
			if t.crack + cr >= t.toughness:
				var be: Dictionary = Data.BREAK_EFFECTS[c.element]
				txt += I18n.s("will_break", [I18n.f(be, "name"), I18n.f(be, "desc")])
				if intent_threat(t):
					txt += I18n.s("will_interrupt")
		for eff in sk.effects:
			if eff.type == "debuff":
				var resist := maxf(Data.MIN_RESIST, float(t.stats.res) - float(c.stats.acc))
				var land := float(eff.chance) * (1.0 - resist / 100.0)
				txt += I18n.s("land_chance", [I18n.f(Data.STATUS[eff.status], "name"), land, I18n.s("target_immune") if t.has_status("immunity") else ""])
	else:
		txt += I18n.f(sk, "desc")
	return txt


func handle_key(keycode: int) -> void:
	match keycode:
		KEY_1, KEY_2, KEY_3:
			_on_skill_pressed(keycode - KEY_1)
		KEY_SPACE:
			if state == State.WAIT_INPUT and current_unit:
				player_action.emit(_ai_choose(current_unit, selected_skill))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		_mouse_moved = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse = event.position
		_pending_click = true


func _physics_process(_delta: float) -> void:
	if fast:
		return
	if state != State.WAIT_INPUT:
		_pending_click = false
		# outside targeting, hovering a unit shows its summary
		if _mouse_moved:
			_mouse_moved = false
			var h := _pick(_mouse)
			if h != hovered:
				hovered = h
				if h:
					hud.show_tip(hud.unit_tip(h), self)
				else:
					hud.hide_tip(self)
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
## Picks a skill and target. `planning` = deciding an enemy intent one turn ahead.
func _ai_choose(u: Node, forced_skill: int = -1, planning: bool = false) -> Dictionary:
	var skill := 0
	if forced_skill >= 0:
		skill = forced_skill
	else:
		for i in [2, 1, 0]:
			if _skill_usable(u, i, planning) and _ai_worth(u, i):
				skill = i
				break
	var sk: Dictionary = u.skills[skill]
	var target: Node = u
	if sk.target != "all_allies":
		var best_score := -INF
		for t in _enemies(u):
			var aff := Data.affinity(u.element, t.element)
			var score: float = (1.0 - t.hp_ratio()) * 40.0 + rng.randf() * 6.0
			score += 22.0 if aff == 1 else (-18.0 if aff == -1 else 0.0)
			if sk.mult > 0.0:
				if t.hp + t.shield <= _base_damage(u, t, sk, aff) * int(sk.hits):
					score += 50.0
				if t.broken:
					score += 18.0
				elif t.crack + _crack_amount(u, t, sk, aff) * int(sk.hits) >= t.toughness:
					score += 30.0
					if intent_threat(t):
						score += 30.0
				else:
					score += t.crack_ratio() * 12.0
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
		if a.hp_ratio() < 0.7 or a.crack_ratio() > 0.6:
			return true
		for s in a.statuses:
			if not Data.STATUS[s.id].buff:
				return true
	return i == 2 and u.skills[2].effects.size() > 2


# --- Skill execution ----------------------------------------------------------------------------
func _execute(c: Node, idx: int, target: Node) -> void:
	var sk: Dictionary = c.skills[idx]
	var cheat: bool = cheat_no_cd and c.team == 0
	if idx == 1:
		c.cooldowns[1] = 0 if cheat else int(sk.cd)
	if idx == 2:
		c.energy = 100.0 if cheat else maxf(0.0, c.energy - c.ult_cost)
	else:
		c.gain_energy(Data.ENERGY_PER_ACTION)
	var ecol: Color = Data.ELEMENT_COLORS[c.element]
	var sk_name := I18n.f(sk, "name")
	hud.log_line(I18n.s("log_uses", [_name(c), sk_name]))
	_text(c.head_position() + Vector3.UP * 0.35, sk_name, ecol.lerp(Color.WHITE, 0.3), 50, 0.8, 1.0)

	var targets: Array = []
	match sk.target:
		"enemy":
			targets = [target]
		"all_enemies":
			targets = _enemies(c)
		"all_allies":
			targets = _allies(c)
	var focus: Vector3 = target.global_position if sk.target == "enemy" else _team_center(targets[0].team if targets.size() > 0 else 1 - c.team)

	if fast:
		sim_time += float(ANIM_TIME.get(sk.anim, 1.2))
	else:
		c.face_towards(focus)
		match sk.anim:
			"melee":
				cam.battle_view(focus, 0.25)
				audio.play(audio.element_sfx(c.element), -4.0)
				var own: bool = await Anims.play(c, sk, focus)
				if not own:
					await c.anim_lunge(focus)
			"projectile":
				audio.play(audio.element_sfx(c.element), -4.0)
				var own: bool = await Anims.play(c, sk, focus)
				if not own:
					await c.anim_cast()
			"cast":
				audio.play(audio.element_sfx(c.element))
				vfx.ring(c.global_position, ecol, 3.0, 0.6)
				vfx.buff_fx(c.center_position(), ecol)
				var own: bool = await Anims.play(c, sk, focus)
				if not own:
					await c.anim_cast()
			"ultimate":
				audio.play("ultimate")
				hud.banner(sk_name, ecol, "奥 义" if not I18n.en() else "ULTIMATE")
				cam.battle_view(c.global_position, 0.5, 2.5)
				vfx.pillar(c.global_position, ecol)
				vfx.ring(c.global_position, ecol, 4.0, 0.8)
				var own: bool = await Anims.play(c, sk, focus)
				if not own:
					await c.anim_ultimate()
				if not _ok():
					return
				cam.battle_view(focus, 0.3, 2.5)
	if not _ok():
		return

	if sk.mult > 0.0:
		for h in int(sk.hits):
			if not fast:
				if sk.anim == "projectile":
					var any := false
					for t in targets:
						if t.alive:
							any = true
							vfx.projectile(c.muzzle_position(), t.center_position(), ecol, 0.3)
					if any:
						await _wait(0.3)
				elif sk.target == "all_enemies":
					for t in targets:
						if t.alive:
							vfx.shockwave(t.center_position(), ecol)
			if not _ok():
				return
			for t in targets:
				if not t.alive:
					continue
				_apply_hit(c, t, _roll_hit(c, t, sk), sk)
			await _wait(0.22 if int(sk.hits) > 1 else 0.14)
			if not _ok():
				return
		for t in targets:
			if not t.alive:
				continue
			for eff in sk.effects:
				if eff.type == "debuff":
					_try_debuff(c, t, eff.status, int(eff.turns), float(eff.chance))
				elif eff.type == "atb_reduce":
					_try_atb_reduce(c, t, float(eff.amount), float(eff.chance))

	for eff in sk.effects:
		match eff.type:
			"heal_allies":
				for a in _allies(c):
					_heal(a, a.max_hp * float(eff.pct) / 100.0, true)
				_sfx("heal")
			"shield_allies":
				for a in _allies(c):
					_shield(a, a.max_hp * float(eff.pct) / 100.0)
				_sfx("buff")
			"cleanse_allies":
				for a in _allies(c):
					if a.remove_debuffs() > 0:
						_text(a.head_position() + Vector3.UP * 0.4, I18n.s("cleansed"), Color(0.8, 1.0, 1.0), 44)
			"buff_allies":
				for a in _allies(c):
					_buff(a, eff.status, int(eff.turns))
				_sfx("buff")
			"buff_self":
				_buff(c, eff.status, int(eff.turns))
				_sfx("buff")
			"atb_boost_allies":
				for a in _allies(c):
					if a != c:
						a.atb = minf(a.atb + float(eff.amount), 100.0)
						_text(a.head_position() + Vector3.UP * 0.2, I18n.s("atb_up", [int(eff.amount)]), Color(0.55, 0.9, 1.0), 40)
	await _wait(0.45)
	if not _ok():
		return
	if fast:
		return
	# anything that left its plinth (lunges, pounces, hops) walks back home
	if c.alive and c.global_position.distance_to(c.home) > 0.3:
		await c.anim_return()
	else:
		c.reset_facing()


# --- Combat math ----------------------------------------------------------------------------
## Damage multiplier from the attacker's current 相生 chain.
func _chain_damage(c: Node) -> float:
	if c.chain <= 0:
		return 1.0
	var step := Data.CHAIN_DAMAGE_STEP * (Data.MONO_CHAIN if _trait(c.team, "mono") >= 0 else 1.0)
	if c.team == 0 and _has("five_phases"):
		step += 0.1
	return 1.0 + step * c.chain


## Crack a single hit of `sk` puts on `t`.
func _crack_amount(c: Node, t: Node, sk: Dictionary, aff: int) -> float:
	var cr: float = float(sk.get("crack", 0)) / maxf(1.0, float(sk.hits))
	if aff == 1:
		cr *= Data.ADV_CRACK
	elif aff == -1:
		cr *= Data.DISADV_CRACK
	if c.chain > 0:
		cr *= 1.0 + Data.CHAIN_CRACK_STEP * c.chain * (Data.MONO_CHAIN if _trait(c.team, "mono") >= 0 else 1.0)
	var painted := _trait(c.team, "painted")
	if painted >= 0:
		cr *= 1.2 + 0.2 * painted
	return cr


func _base_damage(c: Node, t: Node, sk: Dictionary, aff: int) -> float:
	var d: float = c.eff_atk() * float(sk.mult) * 1100.0 / (1140.0 + 3.5 * t.eff_def())
	if aff == 1:
		d *= Data.ADV_DAMAGE
	elif aff == -1:
		d *= Data.DISADV_DAMAGE
	d *= _chain_damage(c)
	match c.passive_id:
		"molten_core":
			if t.has_status("dot"):
				d *= 1.25
		"hairline":
			if t.hp_ratio() < 0.5:
				d *= 1.4
		"unmended":
			if c.hp_ratio() < 0.5:
				d *= 1.3
	if t.passive_id == "fired_shell" and t.hp_ratio() > 0.5:
		d *= 0.8
	if t.has_scar("res_%d" % c.element):
		d *= 0.7
	if t.broken:
		d *= 1.5 if (t.team == 1 and _has("ice_crackle")) else Data.BROKEN_DAMAGE_TAKEN
	if _trait(t.team, "song") >= 1:
		d *= 0.88
	if c.team == 0:
		if _has("golden_heart"):
			d *= 1.0 + 0.1 * c.mends
		if _has("listen_crack") and t.crack_ratio() >= 0.5:
			d *= 1.2
	return d


func _roll_hit(c: Node, t: Node, sk: Dictionary) -> Dictionary:
	var aff := Data.affinity(c.element, t.element)
	var crit: bool = rng.randf() * 100.0 < float(c.stats.crit_rate) and not t.has_scar("crit_proof")
	var dmg := _base_damage(c, t, sk, aff)
	if crit:
		dmg *= 1.0 + float(c.stats.crit_dmg) / 100.0
	dmg *= rng.randf_range(0.95, 1.05)
	return {"aff": aff, "crit": crit, "dmg": dmg, "crack": _crack_amount(c, t, sk, aff), "element": c.element}


func _apply_hit(c: Node, t: Node, r: Dictionary, _sk: Dictionary) -> void:
	var ecol: Color = Data.ELEMENT_COLORS[c.element]
	var top: Vector3 = t.head_position() + Vector3.UP * 0.5
	if r.crit:
		stats.crits += 1
		_text(top, I18n.s("crit"), Color(1.0, 0.7, 0.2), 48, 1.0, 0.9)
		if not fast:
			cam.shake(0.45)
	elif r.aff == 1:
		_text(top, I18n.s("advantage"), Color(0.5, 1.0, 0.55), 38, 1.0, 0.8)
	if not fast:
		vfx.sparks(t.center_position(), ecol)
	_deal_damage(c, t, r.dmg, r)
	if not t.alive:
		return
	t.gain_energy(Data.ENERGY_ON_HIT)
	if t.passive_id == "stoked":
		t.atb = minf(t.atb + t.passive_value, 100.0)
	if not t.broken and r.crack > 0.0:
		t.crack = minf(t.toughness, t.crack + float(r.crack))
		if t.crack >= t.toughness:
			_break(c, t)


## 崩裂: the figure's glaze gives way.
func _break(c: Node, t: Node) -> void:
	t.broken = true
	t.crack = t.toughness
	t.atb = maxf(0.0, t.atb - Data.BREAK_ATB)
	stats.breaks += 1
	var be: Dictionary = Data.BREAK_EFFECTS[c.element]
	var col: Color = Data.ELEMENT_COLORS[c.element]
	_text(t.head_position() + Vector3.UP * 1.0, "%s · %s" % [I18n.s("broken"), I18n.f(be, "name")], col.lerp(Color.WHITE, 0.25), 70, 1.5, 1.3)
	hud.log_line(I18n.s("log_break", [_name(t), I18n.f(be, "name"), I18n.f(be, "desc")]))
	if not fast:
		vfx.burst(t.center_position(), Color(0.96, 0.94, 0.88), 50, 8.0, 0.3)
		vfx.burst(t.center_position(), col, 40, 7.0, 0.3)
		vfx.shockwave(t.center_position(), col)
		cam.shake(0.35)
		_sfx("shatter", -8.0)
		_sfx("reaction", -4.0)
		arena.pulse_element(c.element)
	# interrupt: a telegraphed skill or ultimate falls back to a basic attack
	if t.team == 1 and intent_threat(t):
		t.intent.skill = 0
		stats.interrupts += 1
		_text(t.head_position() + Vector3.UP * 1.6, I18n.s("interrupted"), Color(1.0, 0.9, 0.5), 52, 1.2, 1.2)
	match c.element:
		Data.Element.METAL:
			for a in _allies(c):
				_shield(a, a.max_hp * 0.12)
		Data.Element.WOOD:
			for a in _allies(c):
				_heal(a, a.max_hp * 0.08)
		Data.Element.WATER:
			if not t.has_status("immunity"):
				t.add_status("slow", 2)
		Data.Element.FIRE:
			if not _blocks(t, "dot"):
				t.add_status("dot", 2)
				t.add_status("dot", 2)
		Data.Element.EARTH:
			if not _blocks(t, "def_break"):
				t.add_status("def_break", 2)
	if _trait(c.team, "painted") >= 1:
		c.gain_energy(20.0)
	if c.team == 0 and _has("thermal_shock"):
		_deal_damage(c, t, t.max_hp * 0.15, {})


func _deal_damage(src: Node, t: Node, amount: float, info: Dictionary) -> void:
	if not t.alive:
		return
	amount = roundf(maxf(amount, 1.0))
	var shown := amount
	if t.shield > 0.0:
		var absorbed := minf(t.shield, amount)
		t.shield -= absorbed
		amount -= absorbed
	t.hp = maxf(0.0, t.hp - amount)
	var crit: bool = info.get("crit", false)
	if not fast:
		var col := Color(1, 0.97, 0.9)
		if crit:
			col = Color(1.0, 0.75, 0.25)
		elif info.get("dot", false):
			col = Color(0.8, 0.45, 1.0)
		elif amount < shown:
			col = Color(1.0, 0.86, 0.5)
		vfx.text(t.head_position(), str(int(shown)), col, 72 if crit else 58)
		t.anim_hit(crit)
		audio.play("crit" if crit else "hit", -3.0)
	if t.hp <= 0.0:
		t.death_cause = {
			"element": src.element if (src and is_instance_valid(src)) else -1,
			"crit": crit, "dot": info.get("dot", false),
			"cc": t.has_status("stun") or t.has_status("freeze"),
		}
		_kill(t, src)


func _kill(t: Node, src: Node) -> void:
	# Gold Dust Vial: the first ally to break reassembles on the spot.
	if t.team == 0 and _has("gold_dust") and not _gold_dust_used:
		_gold_dust_used = true
		t.hp = t.max_hp * 0.3
		t.crack = 0.0
		t.broken = false
		if not fast:
			vfx.burst(t.center_position(), Color(1.0, 0.8, 0.35), 70, 5.0, 0.3)
		_text(t.head_position() + Vector3.UP * 0.6, I18n.s("reassemble"), Color(1.0, 0.85, 0.4), 60)
		_sfx("heal")
		return
	t.alive = false
	t.hp = 0.0
	t.statuses.clear()
	t.crack = 0.0
	t.broken = false
	t.shield = 0.0
	t.intent = {}
	if not fast:
		t.anim_death()
		cam.shake(0.3)
	_sfx("shatter")
	hud.log_line(I18n.s("log_shatter", [_name(t)]))
	if src and is_instance_valid(src):
		src.gain_energy(Data.ENERGY_ON_KILL)
		src.set_meta("killed", true)
	for b in units:
		if b.alive and b.passive_id == "unmended" and b != t:
			b.atb = minf(b.atb + 25.0, 100.0)
			_heal(b, b.max_hp * 0.06)
	if t.team == 0 and _has("shard_edge"):
		for a in _alive_team(0):
			a.atb = minf(a.atb + 30.0, 100.0)
			_buff(a, "atk_up", 2)


## Heals HP; heals from skills also mend crack (the gold goes into the cracks first).
func _heal(t: Node, amount: float, mend_crack: bool = false) -> void:
	if not t.alive:
		return
	var before: float = t.hp
	t.hp = minf(t.max_hp, t.hp + amount)
	if mend_crack and not t.broken:
		t.crack = maxf(0.0, t.crack - Data.MEND_CRACK)
	_text(t.head_position(), "+%d" % int(t.hp - before), Color(0.45, 1.0, 0.55), 52)
	if not fast:
		vfx.heal_fx(t.global_position)


## 金釉护盾: absorbs damage; capped at half of max HP.
func _shield(t: Node, amount: float) -> void:
	if not t.alive:
		return
	t.shield = minf(t.shield + amount, t.max_hp * 0.5)
	_text(t.head_position() + Vector3.UP * 0.2, I18n.s("shield_pop", [int(amount)]), Color(1.0, 0.85, 0.4), 42)
	if not fast:
		vfx.buff_fx(t.center_position(), Color(1.0, 0.8, 0.35))


func _buff(t: Node, status: String, turns: int) -> void:
	if not t.alive:
		return
	t.add_status(status, turns)
	var info: Dictionary = Data.STATUS[status]
	_text(t.head_position() + Vector3.UP * 0.3, I18n.f(info, "name"), info.color, 38)
	if not fast:
		vfx.buff_fx(t.center_position(), info.color)


func _blocks(t: Node, status: String) -> bool:
	if t.has_status("immunity"):
		return true
	if status == "dot" and t.has_scar("dot_proof"):
		return true
	if (status == "stun" or status == "freeze") and t.has_scar("cc_proof"):
		return true
	return false


func _try_debuff(c: Node, t: Node, status: String, turns: int, chance: float) -> void:
	if rng.randf() * 100.0 >= chance:
		return
	if _blocks(t, status):
		_text(t.head_position() + Vector3.UP * 0.3, I18n.s("immune"), Color(1, 0.95, 0.6), 40)
		return
	var resist := maxf(Data.MIN_RESIST, float(t.stats.res) - float(c.stats.acc))
	if rng.randf() * 100.0 < resist:
		_text(t.head_position() + Vector3.UP * 0.3, I18n.s("resist"), Color(0.75, 0.8, 1.0), 40)
		return
	t.add_status(status, turns)
	var info: Dictionary = Data.STATUS[status]
	_text(t.head_position() + Vector3.UP * 0.3, I18n.f(info, "name"), info.color, 40)
	_sfx("debuff", -6.0)


func _try_atb_reduce(c: Node, t: Node, amount: float, chance: float) -> void:
	if rng.randf() * 100.0 >= chance or t.has_status("immunity"):
		return
	var resist := maxf(Data.MIN_RESIST, float(t.stats.res) - float(c.stats.acc))
	if rng.randf() * 100.0 < resist:
		_text(t.head_position() + Vector3.UP * 0.3, I18n.s("resist"), Color(0.75, 0.8, 1.0), 40)
		return
	t.atb = maxf(0.0, t.atb - amount)
	_text(t.head_position() + Vector3.UP * 0.3, I18n.s("atb_down", [int(amount)]), Color(0.5, 0.8, 1.0), 40)


func _text(pos: Vector3, msg: String, color: Color, size: int = 64, rise: float = 1.4, duration: float = 1.1) -> void:
	if not fast:
		vfx.text(pos, msg, color, size, rise, duration)


# --- End of battle -------------------------------------------------------------------------------
func _end_battle(victory: bool) -> void:
	if state == State.ENDED:
		return
	var was_waiting := state == State.WAIT_INPUT
	state = State.ENDED
	_clear_highlights()
	hud.hide_skills()
	for u in units:
		u.set_active(false)
	if was_waiting:
		player_action.emit({})
	if not fast:
		if victory:
			audio.play("victory")
			for u in _alive_team(0):
				u.anim_cheer()
			cam.battle_view(_team_center(0), 0.4, 1.0)
			hud.banner(I18n.s("victory"), HUD.BRASS)
		else:
			audio.play("defeat")
			cam.battle_view(_team_center(1), 0.4, 1.0)
			hud.banner(I18n.s("defeat"), HUD.ENEMY_COL)
	var report := {"allies": [], "turns": stats.turns, "ally_turns": stats.ally_turns, "breaks": stats.breaks, "chains": stats.chains,
		"max_chain": stats.max_chain, "crits": stats.crits, "interrupts": stats.interrupts, "time": sim_time}
	for u in units:
		if u.team == 0:
			report.allies.append({"uid": u.uid, "alive": u.alive, "hp_ratio": u.hp_ratio(), "cause": u.death_cause})
	if fast:
		# let the caller start awaiting before we emit
		await get_tree().process_frame
	else:
		await _wait(1.8)
	finished.emit(victory, report)


# --- Cheats (dev console) ------------------------------------------------------------------------
func cheat_win() -> void:
	if state == State.ENDED or state == State.INTRO:
		return
	for e in _alive_team(1):
		e.hp = 0.0
		e.alive = false
		e.anim_death()
	_sfx("shatter")
	_end_battle(true)


func cheat_kill_all() -> void:
	if state == State.ENDED or state == State.INTRO:
		return
	for e in _alive_team(1):
		vfx.pillar(e.global_position, Color(0.4, 1.0, 0.6), 10.0, 0.6)
		_deal_damage(null, e, e.hp + e.shield + 1.0, {"crit": true})
	_check_end()


func cheat_heal() -> void:
	for a in _alive_team(0):
		a.hp = a.max_hp
		a.crack = 0.0
		a.remove_debuffs()
		vfx.heal_fx(a.global_position)


func set_auto(on: bool) -> void:
	auto_battle = on
	hud.set_auto(on)
	if on and state == State.WAIT_INPUT and current_unit:
		player_action.emit(_ai_choose(current_unit))


func _name(u: Node) -> String:
	return "[color=#%s]%s[/color]" % [("8fd0ff" if u.team == 0 else "ff8a8a"), u.display_name]
