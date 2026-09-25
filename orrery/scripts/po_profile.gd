extends RefCounted
## Porcelain Orrery :: persistent player profile (roster, runes, team, loot).
## Saved as JSON under user:// -- never touches project files.

const Data = preload("po_data.gd")

const SAVE_PATH := "user://porcelain_orrery_save.json"
const VERSION := 1

var path := SAVE_PATH
var data: Dictionary = {}
var rng := RandomNumberGenerator.new()


func _init(save_path: String = SAVE_PATH) -> void:
	path = save_path
	rng.randomize()


func load_or_create() -> void:
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary and int(parsed.get("version", 0)) == VERSION:
				data = parsed
				_sanitize()
				return
	reset()


func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))


func reset() -> void:
	data = {"version": VERSION, "next_uid": 1, "wave": 1, "wins": 0, "losses": 0, "scrolls": 1,
		"roster": [], "runes": [], "team": []}
	var loadouts := {
		"emberlynx": ["fatal", "fatal", "fatal", "fatal", "blade", "blade"],
		"tidemoth": ["energy", "energy", "guard", "guard", "energy", "energy"],
		"chimeram": ["swift", "swift", "swift", "swift", "energy", "energy"],
		"lumenowl": ["energy", "energy", "guard", "guard", "blade", "blade"],
	}
	for sid in Data.DEFAULT_TEAM:
		var mon := _new_monster(sid, 5)
		for slot in 6:
			var rune := _store_rune(Data.make_rune(rng, slot, 0, loadouts[sid][slot]))
			mon.runes[slot] = rune.uid
		data.team.append(mon.uid)
	for i in 4:
		_store_rune(Data.make_rune(rng, -1, rng.randi_range(0, 1)))
	save()


# --- Queries --------------------------------------------------------------------
func get_monster(uid: int) -> Dictionary:
	for m in data.roster:
		if int(m.uid) == uid:
			return m
	return {}


func get_rune(uid: int) -> Dictionary:
	for r in data.runes:
		if int(r.uid) == uid:
			return r
	return {}


func team_monsters() -> Array:
	var out: Array = []
	for uid in data.team:
		var m := get_monster(int(uid))
		if not m.is_empty():
			out.append(m)
	return out


func runes_of(mon: Dictionary) -> Array:
	var out: Array = []
	for uid in mon.runes:
		out.append(null if int(uid) < 0 else get_rune(int(uid)))
	return out


func stats_of(mon: Dictionary) -> Dictionary:
	return Data.compute_stats(mon.species, int(mon.level), runes_of(mon))


func owner_of(rune_uid: int) -> Dictionary:
	for m in data.roster:
		if rune_uid in m.runes.map(func(x): return int(x)):
			return m
	return {}


# --- Mutations --------------------------------------------------------------------
func equip(mon_uid: int, rune_uid: int) -> void:
	var rune := get_rune(rune_uid)
	var mon := get_monster(mon_uid)
	if rune.is_empty() or mon.is_empty():
		return
	var prev_owner := owner_of(rune_uid)
	if not prev_owner.is_empty():
		prev_owner.runes[int(rune.slot)] = -1
	mon.runes[int(rune.slot)] = rune_uid
	save()


func unequip(mon_uid: int, slot: int) -> void:
	var mon := get_monster(mon_uid)
	if not mon.is_empty():
		mon.runes[slot] = -1
		save()


func set_team_slot(index: int, mon_uid: int) -> void:
	var team: Array = data.team
	var existing := team.map(func(x): return int(x)).find(mon_uid)
	if existing >= 0:
		team[existing] = team[index]
	team[index] = mon_uid
	save()


## Adds EXP; returns number of levels gained.
func add_exp(mon: Dictionary, amount: int) -> int:
	var gained := 0
	mon.exp = int(mon.exp) + amount
	while int(mon.level) < 40 and int(mon.exp) >= Data.exp_to_next(int(mon.level)):
		mon.exp = int(mon.exp) - Data.exp_to_next(int(mon.level))
		mon.level = int(mon.level) + 1
		gained += 1
	return gained


func grant_random_rune(max_grade: int) -> Dictionary:
	var roll := rng.randf()
	var grade := 0
	if max_grade >= 2 and roll < 0.15:
		grade = 2
	elif max_grade >= 1 and roll < 0.5:
		grade = 1
	return _store_rune(Data.make_rune(rng, -1, grade))


func grant_rune(grade: int) -> Dictionary:
	var r := _store_rune(Data.make_rune(rng, -1, grade))
	save()
	return r


## Uses a Summoning Scroll: adds a random monster to the roster.
func summon() -> Dictionary:
	if int(data.scrolls) <= 0:
		return {}
	data.scrolls = int(data.scrolls) - 1
	var sid: String = Data.SPECIES_ORDER[rng.randi_range(0, Data.SPECIES_ORDER.size() - 1)]
	var mon := _new_monster(sid, maxi(1, int(data.wave)))
	save()
	return mon


# --- Internals ----------------------------------------------------------------------
func _new_uid() -> int:
	var uid := int(data.next_uid)
	data.next_uid = uid + 1
	return uid


func _new_monster(sid: String, level: int) -> Dictionary:
	var mon := {"uid": _new_uid(), "species": sid, "level": level, "exp": 0, "runes": [-1, -1, -1, -1, -1, -1]}
	data.roster.append(mon)
	return mon


func _store_rune(rune: Dictionary) -> Dictionary:
	rune["uid"] = _new_uid()
	data.runes.append(rune)
	return rune


## JSON turns every number into a float; normalise the integer fields.
func _sanitize() -> void:
	for k in ["next_uid", "wave", "wins", "losses", "scrolls"]:
		data[k] = int(data.get(k, 0))
	data.team = data.team.map(func(x): return int(x))
	for m in data.roster:
		m.uid = int(m.uid)
		m.level = int(m.level)
		m.exp = int(m.exp)
		m.runes = m.runes.map(func(x): return int(x))
	for r in data.runes:
		r.uid = int(r.uid)
		r.slot = int(r.slot)
		r.grade = int(r.grade)
		r.value = int(r.value)
	if data.wave < 1:
		data.wave = 1
