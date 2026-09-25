extends RefCounted
## Goldmend :: state and rules of a single run (no nodes, no rendering).
## Map generation, party (HP carries over between fights, shattering and gold
## mending, craft upgrades), gold, glaze shards, enemy encounters, rewards and events.

const Data = preload("po_data.gd")
const I18n = preload("po_i18n.gd")

const ROWS := 9             # row 0 = start, row 8 = boss
const PLATE_RADIUS := 14.0
const MAX_PARTY := 4

var rng := RandomNumberGenerator.new()
var party: Array = []       # {uid, species, level, hp, mends, scars, shattered, cause, upgrades}
var dust: Array = []        # names of figures lost for good
var gold := 50
var relics: Array = []
var nodes: Array = []       # {id, row, type, pos: Vector3, next: [ids], visited}
var current := 0
var seen_events: Array = []
var stats := {"battles": 0, "breaks": 0, "chains": 0, "crits": 0}
var _next_uid := 1


func new_run(starter: int, seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
	else:
		rng.randomize()
	party.clear()
	dust.clear()
	relics.clear()
	seen_events.clear()
	gold = 50
	stats = {"battles": 0, "breaks": 0, "chains": 0, "crits": 0}
	for sid in Data.STARTERS[starter].team:
		recruit(sid)
	_gen_map()


# --- Party ---------------------------------------------------------------------------------
func recruit(sid: String, replace_uid: int = -1) -> Dictionary:
	var lvl := 4
	if not party.is_empty():
		var total := 0
		for m in party:
			total += int(m.level)
		lvl = maxi(4, roundi(float(total) / party.size()))
	var mon := {"uid": _next_uid, "species": sid, "level": lvl, "hp": 1.0, "mends": 0, "scars": [], "shattered": false, "cause": {}, "upgrades": []}
	_next_uid += 1
	if replace_uid >= 0:
		for i in party.size():
			if int(party[i].uid) == replace_uid:
				party[i] = mon
				return mon
	if party.size() < MAX_PARTY:
		party.append(mon)
	return mon


func member(uid: int) -> Dictionary:
	for m in party:
		if int(m.uid) == uid:
			return m
	return {}


func fighters() -> Array:
	return party.filter(func(m): return not m.shattered)


func display_name(m: Dictionary) -> String:
	return I18n.f(Data.SPECIES[m.species], "name")


func total_seams() -> int:
	var n := 0
	for m in party:
		n += int(m.mends)
	return n


func mend_cost(m: Dictionary) -> int:
	return 25 + 15 * int(m.mends)


## Mends a shattered figure. Returns the scar id it earned ("" if none new).
func mend(uid: int) -> String:
	var m := member(uid)
	if m.is_empty() or not m.shattered or gold < mend_cost(m):
		return ""
	gold -= mend_cost(m)
	m.mends = int(m.mends) + 1
	m.shattered = false
	m.hp = 0.6
	var scar := Data.scar_for(m.cause)
	if scar in m.scars:
		var pool: Array = Data.SCARS.keys().filter(func(k): return not k in m.scars)
		scar = pool[rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else ""
	if scar != "":
		m.scars.append(scar)
	return scar


func heal_all(fraction: float) -> void:
	for m in party:
		if not m.shattered:
			m.hp = minf(1.0, float(m.hp) + fraction)


# --- Upgrades (器艺: craft techniques, 4 per spirit) ----------------------------------------------
## Up to n offers of {uid, upgrade} for fighters, spread over different members.
func upgrade_choices(n: int) -> Array:
	var offers: Array = []
	var members := fighters().duplicate()
	_shuffle(members)
	for pass_i in 2:
		for m in members:
			if offers.size() >= n:
				return offers
			var pool: Array = Data.SPECIES[m.species].upgrades.filter(func(u): return not u.id in m.upgrades and not offers.any(func(o): return o.uid == m.uid and o.upgrade == u.id))
			if pool.is_empty() or (pass_i == 0 and offers.any(func(o): return o.uid == m.uid)):
				continue
			offers.append({"uid": int(m.uid), "upgrade": pool[rng.randi_range(0, pool.size() - 1)].id})
	return offers


func apply_upgrade(uid: int, upgrade_id: String) -> void:
	var m := member(uid)
	if not m.is_empty() and not upgrade_id in m.upgrades:
		m.upgrades.append(upgrade_id)


func upgrade_price() -> int:
	return 55


func team_traits() -> Dictionary:
	return Data.active_traits(fighters().slice(0, MAX_PARTY).map(func(m): return m.species))


# --- Battles --------------------------------------------------------------------------------
func ally_specs() -> Array:
	var out: Array = []
	var team := fighters().slice(0, MAX_PARTY)
	var leader: Dictionary = Data.SPECIES[team[0].species].leader if not team.is_empty() else {}
	var hp_mult := 1.2 if "thick_body" in relics else 1.0
	var traits := team_traits()
	for m in team:
		var st := Data.compute_stats(m.species, int(m.level), int(m.mends), hp_mult, leader, m.upgrades, traits)
		if "crit_glaze" in relics:
			st.crit_rate = minf(100.0, st.crit_rate + 15.0)
		out.append({"species": m.species, "level": m.level, "stats": st, "hp": st.hp * float(m.hp),
			"mends": m.mends, "scars": m.scars, "uid": m.uid, "upgrades": m.upgrades})
	return out


## Enemies scale by level, toughness (+5% per row) and, deeper in, their own upgrades
## (one from floor 4, two from floor 7).
func enemy_specs(row: int, kind: String) -> Array:
	var out: Array = []
	var pool: Array = Data.SPECIES_ORDER.duplicate()
	_shuffle(pool)
	if kind == "boss":
		var team := [pool[0], pool[1], pool[2]]
		var traits := Data.active_traits(team)
		out.append(_enemy(pool[0], 9, 1.0, 8, traits))
		var st := Data.compute_stats("boss", 11, 0, 5.5)
		out.append({"species": "boss", "level": 11, "stats": st, "boss": true})
		out.append(_enemy(pool[1], 9, 1.0, 8, traits))
		out.append(_enemy(pool[2], 9, 1.0, 8, traits))
		return out
	var elite := kind == "elite"
	var count := 3 if row <= (3 if elite else 4) else 4
	var lvl := Data.enemy_level(row, elite)
	var traits := Data.active_traits(pool.slice(0, count))
	for i in count:
		var hp_mult: float = 1.7 if (elite and i == 1) else ([0.7, 0.7, 0.85][row] if row <= 2 else 1.0)
		var e := _enemy(pool[i], lvl, hp_mult, row, traits)
		if elite and i == 1:
			e.boss = true
			e.stats.toughness = roundf(e.stats.toughness * 1.4)
		out.append(e)
	return out


func _enemy(sid: String, lvl: int, hp_mult: float, row: int, traits: Dictionary) -> Dictionary:
	var ups: Array = []
	var all_ups: Array = Data.SPECIES[sid].upgrades.map(func(u): return u.id)
	_shuffle(all_ups)
	ups = all_ups.slice(0, clampi((row - 1) / 3, 0, all_ups.size()))
	var st := Data.compute_stats(sid, lvl, 0, hp_mult, {}, ups, traits)
	st.toughness = roundf(st.toughness * (1.0 + 0.05 * row))
	# the first floors teach the rules: enemies hit a little softer there
	if row <= 3:
		st.atk = roundf(st.atk * [0.85, 0.85, 0.85, 0.93][row])
	return {"species": sid, "level": lvl, "stats": st, "upgrades": ups}


## Applies a battle report. Returns {"shattered": [names], "dust": [names], "gold": n}.
func apply_battle(victory: bool, report: Dictionary, kind: String, row: int) -> Dictionary:
	stats.battles += 1
	stats.breaks += int(report.get("breaks", 0))
	stats.chains += int(report.get("chains", 0))
	stats.crits += int(report.crits)
	var res := {"shattered": [], "dust": [], "gold": 0}
	for a in report.allies:
		var m := member(int(a.uid))
		if m.is_empty():
			continue
		if a.alive:
			m.hp = maxf(0.05, float(a.hp_ratio))
			if victory:
				m.level = int(m.level) + 1
				m.hp = minf(1.0, float(m.hp) + 0.3)
		elif int(m.mends) >= Data.MAX_MENDS:
			res.dust.append(display_name(m))
			dust.append(display_name(m))
			party.erase(m)
		else:
			m.shattered = true
			m.hp = 0.0
			m.cause = a.cause
			res.shattered.append(display_name(m))
	if victory:
		var g := (25 + row * 3) if kind == "battle" else (50 + row * 4)
		if "greedy_gold" in relics:
			g = roundi(g * 1.4)
		gold += g
		res.gold = g
	return res


# --- Relics -----------------------------------------------------------------------------------
func relic_choices(n: int, min_rarity: int = 0) -> Array:
	var pool: Array = Data.RELICS.keys().filter(func(k): return not k in relics and int(Data.RELICS[k].rarity) >= min_rarity)
	if pool.size() < n:
		pool = Data.RELICS.keys().filter(func(k): return not k in relics)
	_shuffle(pool)
	return pool.slice(0, n)


func relic_price(id: String) -> int:
	return [45, 70, 95][int(Data.RELICS[id].rarity)]


func kiln_choices() -> Array:
	var have: Array = party.map(func(m): return m.species)
	var pool: Array = Data.SPECIES_ORDER.filter(func(s): return not s in have)
	if pool.size() < 3:
		pool = Data.SPECIES_ORDER.duplicate()
	_shuffle(pool)
	return pool.slice(0, 3)


# --- Events -----------------------------------------------------------------------------------
func pick_event() -> Dictionary:
	var pool: Array = Data.EVENTS.filter(func(e): return not e.id in seen_events)
	if pool.is_empty():
		pool = Data.EVENTS.duplicate()
	var ev: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	seen_events.append(ev.id)
	return ev


## Resolves an event option. Returns a short localised result line.
func resolve_event(act: String) -> String:
	match act:
		"recruit_paid":
			if gold < 35:
				return I18n.s("not_enough")
			gold -= 35
			var sid: String = kiln_choices()[0]
			var replace := -1
			if party.size() >= MAX_PARTY:
				replace = int(party[party.size() - 1].uid)
			var m := recruit(sid, replace)
			return I18n.s("joined", [display_name(m)])
		"sell":
			gold += 30
			return I18n.s("reward_gold", [30])
		"altar":
			for m in party:
				if not m.shattered:
					m.hp = maxf(0.05, float(m.hp) * 0.75)
			var r: Array = relic_choices(1)
			if not r.is_empty():
				relics.append(r[0])
				return "◆ " + I18n.f(Data.RELICS[r[0]], "name")
			return ""
		"altar_heal":
			if gold < 40:
				return I18n.s("not_enough")
			gold -= 40
			heal_all(1.0)
			return "♥"
		"gaze":
			var best: Dictionary = {}
			for m in fighters():
				if best.is_empty() or int(m.mends) > int(best.mends):
					best = m
			if not best.is_empty():
				best.level = int(best.level) + 2
				return "%s Lv%d" % [display_name(best), int(best.level)]
			return ""
		"gold":
			gold += 45
			return I18n.s("reward_gold", [45])
	return ""


# --- Map -------------------------------------------------------------------------------------
func node(id: int) -> Dictionary:
	return nodes[id]


func available() -> Array:
	return nodes[current].next


func _gen_map() -> void:
	nodes.clear()
	var rows: Array = []
	for r in ROWS:
		var count := 1 if (r == 0 or r == ROWS - 1) else rng.randi_range(2, 3)
		var row_ids: Array = []
		for c in count:
			var t := _pick_type(r, c, count)
			var z := lerpf(PLATE_RADIUS * 0.78, -PLATE_RADIUS * 0.78, float(r) / (ROWS - 1))
			var half := sqrt(maxf(PLATE_RADIUS * PLATE_RADIUS * 0.6 - z * z, 4.0))
			var x := 0.0 if count == 1 else lerpf(-half * 0.7, half * 0.7, float(c) / (count - 1))
			x += rng.randf_range(-0.6, 0.6)
			var n := {"id": nodes.size(), "row": r, "type": t, "pos": Vector3(x, 0, z + rng.randf_range(-0.4, 0.4)), "next": [], "visited": r == 0}
			nodes.append(n)
			row_ids.append(n.id)
		rows.append(row_ids)
	# connect rows: each node links to the nearest node(s) above, and every node gets an incoming edge
	for r in ROWS - 1:
		var here: Array = rows[r]
		var above: Array = rows[r + 1]
		for i in here.size():
			var t := 0.0 if here.size() == 1 else float(i) / (here.size() - 1)
			var j := roundi(t * (above.size() - 1))
			_link(here[i], above[j])
			if above.size() > here.size() and j + 1 < above.size() and rng.randf() < 0.6:
				_link(here[i], above[j + 1])
		for j in above.size():
			var has_in := false
			for i in here:
				if above[j] in nodes[i].next:
					has_in = true
			if not has_in:
				var t2 := 0.0 if above.size() == 1 else float(j) / (above.size() - 1)
				_link(here[roundi(t2 * (here.size() - 1))], above[j])
	current = 0


func _link(a: int, b: int) -> void:
	if not b in nodes[a].next:
		nodes[a].next.append(b)


func _pick_type(r: int, c: int, count: int) -> String:
	match r:
		0:
			return "start"
		1:
			return "battle"
		2:
			return ["battle", "event", "battle"][c % 3]
		3:
			return "kiln" if c == 0 else ["battle", "elite"][rng.randi_range(0, 1)]
		4:
			return ["shop", "battle", "event"][c % 3]
		5:
			return "mend" if c == count - 1 else ["elite", "battle"][rng.randi_range(0, 1)]
		6:
			return ["battle", "event", "elite"][c % 3]
		7:
			return "mend" if c % 2 == 0 else "shop"
	return "boss"


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp
