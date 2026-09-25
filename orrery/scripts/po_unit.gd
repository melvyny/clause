extends Node3D
## Porcelain Orrery :: a monster on the battlefield.
## Holds combat state (HP, Attack Bar, cooldowns, statuses) and drives its own
## procedural animations. Battle rules live in po_battle.gd.

const Data = preload("po_data.gd")
const M = preload("po_mat.gd")
const Builder = preload("po_monster_builder.gd")
const I18n = preload("po_i18n.gd")
const Anims = preload("po_anims.gd")

var species_id := ""
var species: Dictionary = {}
var display_name := ""
var element := 0
var team := 0                # 0 = player, 1 = enemy
var level := 1
var stats: Dictionary = {}
var max_hp := 1.0
var hp := 1.0
var atb := 0.0
var cooldowns := [0, 0, 0]
var statuses: Array = []     # [{id, turns}]
var alive := true
var skills: Array = []
var energy := 0.0
var ult_cost := 100.0
var mark := -1               # element Mark left by the last attacker (Element Fission)
var mark_turns := 0
var is_boss := false
var uid := -1                # run creature id (allies only)
var mends := 0               # gold seams from previous repairs
var scars: Array = []        # scar ids (see Data.SCARS)
var death_cause := {}        # how it broke: {element, crit, dot, cc}
const PLINTH_H := 0.2
var passive_id := ""
var home := Vector3.ZERO
var home_basis := Basis.IDENTITY

var model: Node3D
var muzzle: Node3D
var model_height := 2.0
var pick_radius := 0.8
var _base_positions := {}
var _time := randf() * 10.0
var _flash_mat: StandardMaterial3D
var _meshes: Array = []
var _target_ring: MeshInstance3D
var _active_ring: MeshInstance3D
var _arrow: Node3D
var _arrow_mesh: MeshInstance3D
var _highlight := 0
var _porcelain: Array = []
var _bob_paused := {}        # parts currently driven by a signature move
var _shown_damage := 0.0


func setup(p_species: String, p_team: int, p_level: int, p_stats: Dictionary, name_prefix: String = "") -> void:
	species_id = p_species
	species = Data.species_info(p_species)
	display_name = (name_prefix + I18n.f(species, "name")).strip_edges()
	element = species.element
	team = p_team
	level = p_level
	stats = p_stats
	max_hp = float(stats.hp)
	hp = max_hp
	skills = species.skills
	passive_id = species.passive.id
	energy = Data.ENERGY_START
	name = "%s_%s" % ["Ally" if team == 0 else "Enemy", p_species]


func _ready() -> void:
	model = Builder.build(species_id, team == 1)
	# every figure stands on a glazed porcelain plinth, like a display piece
	var stand := Node3D.new()
	stand.position.y = PLINTH_H
	add_child(stand)
	stand.add_child(model)
	model_height = model.get_meta("height", 2.0) + PLINTH_H
	pick_radius = model.get_meta("radius", 0.8)
	muzzle = model.get_meta("muzzle") if model.has_meta("muzzle") else null
	if is_boss:
		model.scale = Vector3.ONE * 1.35
		model_height = (model_height - PLINTH_H) * 1.35 + PLINTH_H
		pick_radius *= 1.3
	for entry in model.get_meta("bobbers"):
		_base_positions[entry[0]] = entry[0].position
	_porcelain = model.get_meta("porcelain", [])
	set_mends(mends)
	play_anim("idle")
	_collect_meshes(model)
	_flash_mat = StandardMaterial3D.new()
	_flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_flash_mat.albedo_color = Color(1, 1, 1, 0)

	# Picking collider (default collision layer; no project layer changes).
	var body := StaticBody3D.new()
	body.set_meta("unit", self)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = pick_radius
	cap.height = maxf(model_height, pick_radius * 2.0)
	shape.shape = cap
	shape.position = Vector3(0, model_height * 0.5, 0)
	body.add_child(shape)
	add_child(body)

	# Porcelain plinth glazed in the element colour, with a gold lip.
	var ecol: Color = Data.ELEMENT_COLORS[element]
	var pr := pick_radius + 0.25
	var plinth_mat := M.porcelain(Builder.GLAZES[element], 0.05, ecol, 0.0, 2.5, 0.012)
	M.add_mesh(self, M.cylinder(pr, pr + 0.1, PLINTH_H, 40), plinth_mat, Vector3(0, PLINTH_H * 0.5, 0))
	M.add_mesh(self, M.torus(pr - 0.05, pr + 0.02, 64), M.brass(), Vector3(0, PLINTH_H, 0))
	M.add_mesh(self, M.torus(pr + 0.1, pr + 0.16), M.glow(ecol, 2.5, 0.8), Vector3(0, 0.03, 0))
	_active_ring = M.add_mesh(self, M.torus(pick_radius + 0.45, pick_radius + 0.55), M.glow(Color(1.0, 0.85, 0.35), 4.0), Vector3(0, 0.05, 0))
	_active_ring.visible = false
	_target_ring = M.add_mesh(self, M.torus(pick_radius + 0.55, pick_radius + 0.68, 6), M.glow(Color(1, 1, 1), 3.0), Vector3(0, 0.06, 0))
	_target_ring.visible = false

	# Elemental advantage arrow (shown while targeting).
	_arrow = Node3D.new()
	_arrow.position = Vector3(0, model_height + 0.75, 0)
	add_child(_arrow)
	_arrow_mesh = M.add_mesh(_arrow, M.prism(Vector3(0.45, 0.45, 0.12)), M.glow(Color.GREEN, 3.0))
	M.add_mesh(_arrow_mesh, M.cylinder(0.08, 0.08, 0.3, 8), _arrow_mesh.material_override, Vector3(0, -0.35, 0))
	_arrow.visible = false


func _collect_meshes(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			_meshes.append(c)
		_collect_meshes(c)


func _process(delta: float) -> void:
	_time += delta
	if model == null:
		return
	for entry in model.get_meta("spinners"):
		var node: Node3D = entry[0]
		if entry[2] != 0.0:
			node.rotate_object_local(entry[1], deg_to_rad(entry[2]) * delta)
	for entry in model.get_meta("bobbers"):
		var node: Node3D = entry[0]
		if _bob_paused.has(node):
			continue
		node.position.y = _base_positions[node].y + sin(_time * entry[2] + entry[3]) * entry[1]
	var dmg := 1.0 - hp_ratio() if alive else 1.0
	if absf(dmg - _shown_damage) > 0.002:
		_shown_damage = lerpf(_shown_damage, dmg, minf(1.0, delta * 4.0))
		for m in _porcelain:
			m.set_shader_parameter("damage", _shown_damage)
	if _active_ring.visible:
		_active_ring.rotate_y(delta * 1.5)
		var s := 1.0 + sin(_time * 5.0) * 0.05
		_active_ring.scale = Vector3(s, 1, s)
	if _target_ring.visible:
		_target_ring.rotate_y(-delta * (3.0 if _highlight == 2 else 1.0))
	if _arrow.visible:
		_arrow.position.y = model_height + 0.75 + sin(_time * 4.0) * 0.1
		var cam := get_viewport().get_camera_3d()
		if cam:
			var look := cam.global_position
			look.y = _arrow.global_position.y
			if look.distance_to(_arrow.global_position) > 0.01:
				_arrow.look_at(look, Vector3.UP)


## Plays a clip on imported glTF creatures (no-op for procedural models).
## Non-idle clips fall back to idle when they finish.
func play_anim(role: String) -> bool:
	if not model.has_meta("anim_player"):
		return false
	var ap: AnimationPlayer = model.get_meta("anim_player")
	var map: Dictionary = model.get_meta("anims", {})
	if not map.has(role):
		return false
	ap.play(map[role], 0.15)
	if role != "idle" and role != "death" and map.has("idle"):
		ap.queue(map["idle"])
	return true


## Signature moves take over a part: stop its idle bob while they animate it.
func pause_bob(node: Node3D, paused: bool) -> void:
	if paused:
		_bob_paused[node] = true
	else:
		_bob_paused.erase(node)
		if _base_positions.has(node):
			node.position = _base_positions[node]


func set_mends(n: int) -> void:
	mends = n
	for m in _porcelain:
		m.set_shader_parameter("mended", float(n))


func has_scar(id: String) -> bool:
	return id in scars


# --- Stats ------------------------------------------------------------------------
func eff_atk() -> float:
	return float(stats.atk) * (1.0 + (Data.ATK_UP if has_status("atk_up") else 0.0))


func eff_def() -> float:
	var m := 1.0
	if has_status("def_up"):
		m += Data.DEF_UP
	if has_status("def_break"):
		m -= Data.DEF_BREAK
	return float(stats.def) * maxf(m, 0.1)


func eff_spd() -> float:
	return float(stats.spd)


func hp_ratio() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


func head_position() -> Vector3:
	return global_position + Vector3(0, model_height + 0.3, 0)


func center_position() -> Vector3:
	return global_position + Vector3(0, model_height * 0.55, 0)


func muzzle_position() -> Vector3:
	return muzzle.global_position if muzzle else center_position()


# --- Statuses ---------------------------------------------------------------------
func has_status(id: String) -> bool:
	for s in statuses:
		if s.id == id:
			return true
	return false


func count_status(id: String) -> int:
	var n := 0
	for s in statuses:
		if s.id == id:
			n += 1
	return n


func add_status(id: String, turns: int) -> void:
	# Continuous damage stacks; everything else refreshes duration.
	if id != "dot":
		for s in statuses:
			if s.id == id:
				s.turns = maxi(s.turns, turns)
				return
	statuses.append({"id": id, "turns": turns})


func remove_debuffs() -> int:
	var before := statuses.size()
	statuses = statuses.filter(func(s): return Data.STATUS[s.id].buff)
	return before - statuses.size()


## Called at the end of this unit's turn.
func tick_statuses() -> void:
	for s in statuses:
		s.turns -= 1
	statuses = statuses.filter(func(s): return s.turns > 0)
	if mark >= 0:
		mark_turns -= 1
		if mark_turns <= 0:
			mark = -1


func gain_energy(amount: float) -> void:
	energy = clampf(energy + amount, 0.0, 100.0)


func ultimate_ready() -> bool:
	return energy >= ult_cost


# --- Visual state -----------------------------------------------------------------
func set_active(on: bool) -> void:
	_active_ring.visible = on and alive


## mode: 0 = none, 1 = valid target, 2 = hovered target.
func set_target_highlight(mode: int, affinity: int = 0, show_arrow: bool = false) -> void:
	_highlight = mode
	_target_ring.visible = mode > 0 and alive
	var mat: StandardMaterial3D = _target_ring.material_override
	mat.albedo_color = Color(1, 1, 1) if mode == 2 else Color(0.8, 0.8, 0.8, 0.8)
	mat.emission_energy_multiplier = 5.0 if mode == 2 else 1.5
	_arrow.visible = show_arrow and mode > 0 and alive
	if _arrow.visible:
		var col := Color(1.0, 0.85, 0.2)
		var roll := 90.0
		if affinity > 0:
			col = Color(0.3, 1.0, 0.35)
			roll = 0.0
		elif affinity < 0:
			col = Color(1.0, 0.25, 0.2)
			roll = 180.0
		var am: StandardMaterial3D = _arrow_mesh.material_override
		am.albedo_color = col
		am.emission = col
		_arrow_mesh.rotation_degrees = Vector3(0, 0, roll)


func face_towards(point: Vector3) -> void:
	var p := Vector3(point.x, global_position.y, point.z)
	if p.distance_to(global_position) > 0.05:
		var t := create_tween()
		var target := global_transform.looking_at(p, Vector3.UP).basis
		t.tween_method(func(w: float): global_basis = global_basis.slerp(target, w), 0.0, 1.0, 0.18)


func reset_facing() -> void:
	var t := create_tween()
	var from := global_basis
	t.tween_method(func(w: float): global_basis = from.slerp(home_basis, w), 0.0, 1.0, 0.25)


# --- Animations (awaitable) -------------------------------------------------------
func anim_lunge(target_pos: Vector3) -> void:
	play_anim("attack")
	var dir := (target_pos - global_position)
	dir.y = 0
	var dist := maxf(dir.length() - 1.6, 0.5)
	var dest := global_position + dir.normalized() * dist
	var t := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(self, "global_position", dest + Vector3(0, 0.6, 0), 0.28)
	t.tween_property(self, "global_position", dest, 0.08)
	await t.finished


func anim_return() -> void:
	var t := create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "global_position", home + Vector3(0, 0.4, 0), 0.25)
	t.tween_property(self, "global_position", home, 0.12)
	await t.finished
	reset_facing()


func anim_cast() -> void:
	if not play_anim("cast"):
		play_anim("attack")
	var t := create_tween().set_trans(Tween.TRANS_SINE)
	var s0 := model.scale
	t.tween_property(model, "scale", s0 * Vector3(1.12, 0.9, 1.12), 0.12)
	t.tween_property(model, "scale", s0 * Vector3(0.95, 1.15, 0.95), 0.14)
	t.tween_property(model, "position:y", 0.35, 0.12)
	t.tween_property(model, "scale", s0, 0.12)
	t.parallel().tween_property(model, "position:y", 0.0, 0.2)
	await t.finished


func anim_ultimate() -> void:
	if not play_anim("cast"):
		play_anim("attack")
	var s0 := model.scale
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(model, "position:y", 1.3, 0.45)
	t.parallel().tween_property(model, "rotation:y", TAU, 0.6)
	t.tween_property(model, "scale", s0 * 1.25, 0.15)
	t.tween_interval(0.1)
	t.tween_property(model, "position:y", 0.0, 0.2).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(model, "scale", s0, 0.2)
	t.tween_callback(func(): model.rotation.y = 0.0)
	await t.finished


func anim_hit(crit: bool) -> void:
	play_anim("hit")
	if alive:
		Anims.hit(self, crit)
	for mi in _meshes:
		if is_instance_valid(mi):
			mi.material_overlay = _flash_mat
	_flash_mat.albedo_color = Color(1, 0.9, 0.8, 0.85 if crit else 0.6)
	var knock := -global_basis.z * (-0.35 if crit else -0.18)
	var t := create_tween()
	t.tween_property(_flash_mat, "albedo_color:a", 0.0, 0.25)
	t.parallel().tween_property(model, "position", Vector3(knock.x, 0, knock.z) * global_basis, 0.06)
	t.tween_property(model, "position", Vector3.ZERO, 0.18)
	t.tween_callback(_clear_overlay)


func _clear_overlay() -> void:
	for mi in _meshes:
		if is_instance_valid(mi):
			mi.material_overlay = null


func anim_death() -> void:
	set_active(false)
	set_target_highlight(0)
	var t := create_tween().set_trans(Tween.TRANS_QUAD)
	if play_anim("death"):
		t.tween_interval(0.6)
	t.tween_property(model, "rotation_degrees:z", 12.0, 0.12)
	t.tween_property(model, "scale", model.scale * 1.08, 0.12)
	await t.finished
	_shatter()
	model.visible = false


## Porcelain death: the figure bursts into glazed shards and gold dust.
func _shatter() -> void:
	var shard_mat := StandardMaterial3D.new()
	shard_mat.albedo_color = Color(0.95, 0.94, 0.9)
	shard_mat.roughness = 0.15
	shard_mat.metallic_specular = 0.8
	for pass_i in 2:
		var p := CPUParticles3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(0.14, 0.18, 0.03) if pass_i == 0 else Vector3(0.09, 0.12, 0.02)
		var mat := shard_mat
		if pass_i == 1:
			mat = StandardMaterial3D.new()
			mat.albedo_color = Data.ELEMENT_COLORS[element].lerp(Color.BLACK, 0.35)
			mat.roughness = 0.1
		mesh.material = mat
		p.mesh = mesh
		p.amount = 40
		p.one_shot = true
		p.explosiveness = 1.0
		p.lifetime = 1.6
		p.direction = Vector3.UP
		p.spread = 70.0
		p.initial_velocity_min = 3.0
		p.initial_velocity_max = 7.0
		p.gravity = Vector3(0, -14, 0)
		p.angular_velocity_min = -720.0
		p.angular_velocity_max = 720.0
		p.particle_flag_rotate_y = true
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = pick_radius * 0.7
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.6
		get_parent().add_child(p)
		p.global_position = center_position()
		p.emitting = true
		get_tree().create_timer(2.0).timeout.connect(p.queue_free)
	var gold := M.particles(Color(1.0, 0.8, 0.35), 40, 1.2, 0.12, 4.0, Vector3.UP, 180, Vector3(0, -2, 0), 0.4)
	gold.one_shot = true
	gold.explosiveness = 0.9
	get_parent().add_child(gold)
	gold.global_position = center_position()
	gold.emitting = true
	get_tree().create_timer(2.0).timeout.connect(gold.queue_free)


func anim_spawn(delay: float) -> void:
	var final_scale := model.scale
	model.scale = Vector3(0.01, 0.01, 0.01)
	model.position.y = 3.0
	var t := create_tween()
	t.tween_interval(delay)
	t.tween_property(model, "position:y", 0.0, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(model, "scale", final_scale, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await t.finished


func anim_cheer() -> void:
	var t := create_tween().set_loops(3)
	t.tween_property(model, "position:y", 0.6, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(model, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
