extends Node3D
## Goldmend :: the run map, painted on a giant blue-and-white porcelain plate.
## Routes are brushed in cobalt; every path you travel is mended in gold. The
## party leader walks the plate as a small figurine. Also hosts the mending
## vignette (shards fly back together and a new gold seam lights up).

const Data = preload("po_data.gd")
const I18n = preload("po_i18n.gd")
const M = preload("po_mat.gd")
const Arena = preload("po_arena.gd")
const Builder = preload("po_monster_builder.gd")
const Cam = preload("po_camera.gd")
const PLATE_SHADER := preload("../shaders/po_plate.gdshader")

signal node_chosen(id: int)
signal node_hovered(id: int)

var run
var cam: Camera3D
var interactive := true
var title_mode := false
var _tokens := {}          # id -> {root, ring, label}
var _hover := -1
var _pawn: Node3D
var _time := 0.0
var _pedestal: Node3D


func setup(p_run) -> void:
	run = p_run


func _ready() -> void:
	Arena.make_environment(self)
	cam = Cam.new()
	add_child(cam)
	cam.make_current()
	_build_plate()
	if run:
		_build_routes()
		_build_tokens()
		_place_pawn()
		focus_current(true)
	else:
		cam.set_view(Vector3(0, 20, 22), Vector3(0, 0, 0), 1.0, true)


func _process(delta: float) -> void:
	_time += delta
	if title_mode:
		var a := _time * 0.08
		cam.set_view(Vector3(sin(a) * 19.0, 11.0, cos(a) * 19.0), Vector3(0, -1.5, 0), 2.0)
		return
	if run == null:
		return
	var avail: Array = run.available() if interactive else []
	for id in _tokens:
		var tk: Dictionary = _tokens[id]
		var on: bool = id in avail
		tk.ring.visible = on
		if on:
			var s := 1.0 + 0.12 * sin(_time * 4.0 + id)
			tk.ring.scale = Vector3(s, 1, s)
			tk.ring.rotate_y(delta * 1.2)
		var target := 1.25 if (id == _hover and id in avail) else 1.0
		tk.root.scale = tk.root.scale.lerp(Vector3.ONE * target, minf(1.0, delta * 10.0))
	if _pawn:
		_pawn.rotate_y(delta * 0.6)


# --- Building --------------------------------------------------------------------------------
func _build_plate() -> void:
	var r: float = 14.0
	var mat := ShaderMaterial.new()
	mat.shader = PLATE_SHADER
	mat.set_shader_parameter("radius", r)
	var plate := M.add_mesh(self, M.cylinder(r, r * 0.92, 0.5, 128), mat, Vector3(0, -0.25, 0))
	plate.name = "Plate"
	M.add_mesh(self, M.torus(r - 0.05, r + 0.35, 160), M.brass(Color(0.95, 0.75, 0.38), 0.25), Vector3(0, 0.0, 0))
	# foot ring and underside
	var under := M.porcelain(Color(0.07, 0.17, 0.55), 0.0, Color(0.6, 0.8, 1.0), 1.0, 0.6, 0.0)
	M.add_mesh(self, M.cylinder(r * 0.92, r * 0.5, 1.6, 96), under, Vector3(0, -1.3, 0))
	M.add_mesh(self, M.torus(r * 0.5 - 0.2, r * 0.5 + 0.2, 96), M.brass(), Vector3(0, -2.1, 0))
	# drifting gold dust above the plate
	var dust := M.particles(Color(1.0, 0.8, 0.45, 0.8), 90, 7.0, 0.12, 0.25, Vector3.UP, 180, Vector3.ZERO, 13.0)
	dust.preprocess = 7.0
	dust.position = Vector3(0, 1.5, 0)
	add_child(dust)


func _build_routes() -> void:
	var cobalt := M.glow(Color(0.1, 0.25, 0.75), 0.9)
	var gold := M.glow(Color(1.0, 0.75, 0.3), 3.5)
	for n in run.nodes:
		for nid in n.next:
			var b: Dictionary = run.node(nid)
			var travelled: bool = n.visited and b.visited
			_route(n.pos, b.pos, gold if travelled else cobalt, travelled)


## Painted brush dots for untravelled routes; a raised gold seam once travelled.
func _route(a: Vector3, b: Vector3, mat: Material, travelled: bool) -> void:
	var d := b - a
	var len := d.length()
	if travelled:
		var mi := M.add_mesh(self, M.cylinder(0.09, 0.09, len, 8), mat, (a + b) * 0.5 + Vector3(0, 0.06, 0))
		mi.look_at_from_position(mi.position, b + Vector3(0, 0.06, 0), Vector3.UP)
		mi.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		var sparkle := M.particles(Color(1.0, 0.85, 0.45), 10, 1.2, 0.12, 0.3, Vector3.UP, 30, Vector3.ZERO, 0.1)
		sparkle.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		sparkle.emission_box_extents = Vector3(0.1, 0.05, len * 0.5)
		sparkle.position = mi.position
		sparkle.rotation = Vector3(0, atan2(d.x, d.z), 0)
		add_child(sparkle)
	else:
		var steps := int(len / 0.45)
		for i in range(1, steps):
			var p := a.lerp(b, float(i) / steps)
			M.add_mesh(self, M.cylinder(0.07, 0.07, 0.02, 8), mat, p + Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1.0 + 0.3 * sin(i * 1.7), 1, 1.0))


func _build_tokens() -> void:
	for n in run.nodes:
		var info: Dictionary = Data.NODE_TYPES[n.type]
		var root := Node3D.new()
		root.position = n.pos
		add_child(root)
		var col: Color = info.color
		var big: bool = n.type == "boss"
		var radius := 1.1 if big else 0.62
		var mat := M.porcelain(col, 0.0, col, 1.0, 3.0, 0.014, Color(0.95, 0.94, 0.9))
		if big:
			mat.set_shader_parameter("gold", Color(0.8, 0.1, 0.06))
			mat.set_shader_parameter("damage", 0.6)
		M.add_mesh(root, M.cylinder(radius, radius + 0.08, 0.26, 40), mat, Vector3(0, 0.13, 0))
		M.add_mesh(root, M.torus(radius - 0.04, radius + 0.04, 48), M.brass(), Vector3(0, 0.27, 0))
		if n.visited:
			M.add_mesh(root, M.torus(radius + 0.1, radius + 0.18, 48), M.glow(Color(1, 0.8, 0.4), 3.0), Vector3(0, 0.05, 0))
		var label := Label3D.new()
		label.font = M.ui_font()
		label.text = I18n.f(info, "glyph")
		label.font_size = 110 if big else 72
		label.pixel_size = 0.006
		label.modulate = Color(1, 0.95, 0.85) if not n.visited else Color(1, 0.85, 0.45)
		label.outline_modulate = Color(0.03, 0.03, 0.08)
		label.outline_size = 18
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = Vector3(0, 0.75 if not big else 1.2, 0)
		root.add_child(label)
		var ring := M.add_mesh(root, M.torus(radius + 0.22, radius + 0.34, 6), M.glow(Color(1.0, 0.85, 0.4), 4.0), Vector3(0, 0.05, 0))
		ring.visible = false
		_tokens[n.id] = {"root": root, "ring": ring, "label": label}


func _place_pawn() -> void:
	var fighters: Array = run.fighters()
	if fighters.is_empty():
		return
	_pawn = Node3D.new()
	var model := Builder.build(fighters[0].species, false)
	model.scale = Vector3.ONE * 0.6
	_pawn.add_child(model)
	add_child(_pawn)
	_pawn.position = run.node(run.current).pos + Vector3(0, 0.27, 0)


# --- Camera & travel ----------------------------------------------------------------------------
func focus_current(snap: bool = false) -> void:
	var p: Vector3 = run.node(run.current).pos
	var look := Vector3(p.x * 0.4, 0, p.z - 3.5)
	cam.set_view(look + Vector3(0, 11.5, 10.5), look, 2.5, snap)


## Animates the pawn along the route and gilds the path. Awaitable.
func travel_to(id: int) -> void:
	var a: Vector3 = run.node(run.current).pos
	var b: Vector3 = run.node(id).pos
	var gold := M.glow(Color(1.0, 0.75, 0.3), 3.5)
	var seam := M.add_mesh(self, M.cylinder(0.09, 0.09, 1.0, 8), gold, a)
	var t := create_tween()
	t.tween_method(_travel_step.bind(a, b, seam), 0.0, 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	var look := Vector3(b.x * 0.4, 0, b.z - 3.5)
	cam.set_view(look + Vector3(0, 11.5, 10.5), look, 2.0)
	await t.finished


func _travel_step(w: float, a: Vector3, b: Vector3, seam: MeshInstance3D) -> void:
	var p := a.lerp(b, w)
	seam.position = (a + p) * 0.5 + Vector3(0, 0.06, 0)
	seam.scale = Vector3(1, maxf(a.distance_to(p), 0.01), 1)
	if a.distance_to(p) > 0.02:
		seam.look_at_from_position(seam.position, p + Vector3(0, 0.06, 0), Vector3.UP)
		seam.rotate_object_local(Vector3.RIGHT, PI / 2.0)
		seam.scale = Vector3(1, maxf(a.distance_to(p), 0.01), 1)
	if _pawn:
		_pawn.position = p + Vector3(0, 0.27 + sin(w * PI) * 0.8, 0)


# --- Picking ------------------------------------------------------------------------------------
func _unhandled_input(event: InputEvent) -> void:
	if not interactive or run == null:
		return
	if event is InputEventMouseMotion:
		var h := _pick(event.position, true)
		if h != _hover:
			_hover = h
			node_hovered.emit(h)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := _pick(event.position)
		if id >= 0:
			node_chosen.emit(id)


func _pick(screen: Vector2, any_node: bool = false) -> int:
	var best := -1
	var best_d := 60.0
	var ids: Array = range(run.nodes.size()) if any_node else run.available()
	for id in ids:
		var p: Vector3 = run.node(id).pos + Vector3(0, 0.4, 0)
		if cam.is_position_behind(p):
			continue
		var d := cam.unproject_position(p).distance_to(screen)
		if d < best_d:
			best_d = d
			best = id
	return best


func hovered() -> int:
	return _hover


# --- Mending vignette ---------------------------------------------------------------------------
## Shards fly back together into the figure, then its new gold seam lights up.
func play_mend(species: String, mends_after: int) -> void:
	if _pedestal:
		_pedestal.queue_free()
	_pedestal = Node3D.new()
	add_child(_pedestal)
	var look: Vector3 = cam.look_target
	var dir := (cam.global_position - look).normalized()
	_pedestal.position = look + dir * 5.0 + Vector3(0, -0.6, 0)
	_pedestal.look_at(cam.global_position * Vector3(1, 0, 1) + Vector3(0, _pedestal.position.y, 0), Vector3.UP)
	_pedestal.rotate_y(PI)
	M.add_mesh(_pedestal, M.cylinder(0.9, 1.0, 0.25, 40), M.porcelain(Color(0.07, 0.17, 0.55), 0.05, Color(1, 0.8, 0.4), 0.0, 2.5, 0.012), Vector3(0, 0.12, 0))
	M.add_mesh(_pedestal, M.torus(0.86, 0.94, 64), M.brass(), Vector3(0, 0.25, 0))
	var model := Builder.build(species, false)
	model.position.y = 0.25
	model.scale = Vector3.ONE * 0.8
	_pedestal.add_child(model)
	var mats: Array = model.get_meta("porcelain", [])
	for m in mats:
		m.set_shader_parameter("mended", float(maxi(mends_after - 1, 0)))
		m.set_shader_parameter("damage", 1.0)
	model.visible = false
	# imploding shards
	var shard := PrismMesh.new()
	shard.size = Vector3(0.12, 0.16, 0.03)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.95, 0.94, 0.9)
	smat.roughness = 0.15
	shard.material = smat
	var p := CPUParticles3D.new()
	p.mesh = shard
	p.amount = 70
	p.lifetime = 0.9
	p.one_shot = true
	p.explosiveness = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 2.2
	p.radial_accel_min = -12.0
	p.radial_accel_max = -9.0
	p.gravity = Vector3.ZERO
	p.angular_velocity_min = -540.0
	p.angular_velocity_max = 540.0
	p.particle_flag_rotate_y = true
	p.position = Vector3(0, 1.1, 0)
	_pedestal.add_child(p)
	p.emitting = true
	await get_tree().create_timer(0.8).timeout
	if not is_instance_valid(model):
		return
	model.visible = true
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.8, 0.4)
	flash.light_energy = 8.0
	flash.omni_range = 6.0
	flash.position = Vector3(0, 1.2, 0.8)
	_pedestal.add_child(flash)
	var gold := M.particles(Color(1.0, 0.8, 0.35), 60, 1.2, 0.14, 3.0, Vector3.UP, 180, Vector3(0, -2, 0), 0.5)
	gold.one_shot = true
	gold.explosiveness = 0.9
	gold.position = Vector3(0, 1.0, 0)
	_pedestal.add_child(gold)
	gold.emitting = true
	var t := create_tween()
	t.tween_method(_mend_step.bind(mats, mends_after), 0.0, 1.0, 1.4)
	t.parallel().tween_property(flash, "light_energy", 0.0, 1.4)
	t.parallel().tween_property(_pedestal, "rotation:y", _pedestal.rotation.y + TAU, 2.4).set_trans(Tween.TRANS_SINE)
	await t.finished


func clear_mend() -> void:
	if _pedestal:
		_pedestal.queue_free()
		_pedestal = null


func _mend_step(w: float, mats: Array, mends_after: int) -> void:
	for m in mats:
		m.set_shader_parameter("damage", 1.0 - w)
		m.set_shader_parameter("mended", lerpf(float(maxi(mends_after - 1, 0)), float(mends_after), w))
