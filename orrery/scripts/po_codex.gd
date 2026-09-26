extends Node3D
## Goldmend :: Vessel Spirit codex (器灵图鉴), laid out as a 博古架 (curio cabinet).
## Every spirit sits in its own compartment of a rosewood cabinet, seen straight
## on, so figures never overlap however many there are. A brass plaque under each
## compartment names it. Clicking one zooms the camera into its compartment;
## clicking empty space (or right-clicking) steps back to the whole cabinet.

const Data = preload("po_data.gd")
const I18n = preload("po_i18n.gd")
const M = preload("po_mat.gd")
const Arena = preload("po_arena.gd")
const Unit = preload("po_unit.gd")
const Cam = preload("po_camera.gd")

signal selected(species_id: String)

const COLS := 4
const CELL_W := 3.4          # compartment width
const CELL_H := 3.3          # compartment height
const DEPTH := 3.0           # cabinet depth
const BOARD := 0.16          # board thickness
const FIGURE_SCALE := 0.9
## The info panel covers the right of the screen, so the cabinet sits left of centre.
const VIEW_SHIFT := 3.2
const FOV := 32.0            # a long lens keeps the cabinet nearly flat, like a museum photo

var cam: Camera3D
var still := false          # screenshots: keep the focused spirit facing the camera
var _units: Array = []
var _lamps: Array = []      # the glowing strip at the top of each compartment
var _time := 0.0
var _focus := -1
var _rows := 1


func _ready() -> void:
	Arena.make_environment(self)
	cam = Cam.new()
	add_child(cam)
	cam.make_current()
	cam.fov = FOV
	# museum lighting: a soft key light from the front
	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.92, 0.8)
	key.light_energy = 0.7
	key.rotation_degrees = Vector3(-28, 12, 0)
	add_child(key)
	var ids: Array = Data.SPECIES_ORDER
	_rows = int(ceil(float(ids.size()) / COLS))
	_build_cabinet()
	for i in ids.size():
		var u := Unit.new()
		u.setup(ids[i], 0, 1, Data.compute_stats(ids[i], 1))
		add_child(u)
		u.scale = Vector3.ONE * FIGURE_SCALE
		u.position = cell_floor(i)
		u.rotation.y = PI
		_units.append(u)
		_plaque(i, Data.SPECIES[ids[i]])
	overview(true)


## Floor centre of compartment i. Rows fill top to bottom; a short last row is centred.
func cell_floor(i: int) -> Vector3:
	var row := i / COLS
	var col := i % COLS
	var in_row := mini(COLS, Data.SPECIES_ORDER.size() - row * COLS)
	var x := (col - (in_row - 1) * 0.5) * CELL_W
	var y := (_rows - 1 - row) * CELL_H + BOARD * 0.5
	return Vector3(x, y, 0.0)


func _build_cabinet() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.24, 0.1, 0.06)
	wood.roughness = 0.45
	wood.metallic_specular = 0.6
	var back_mat := StandardMaterial3D.new()
	back_mat.albedo_color = Color(0.13, 0.12, 0.26)   # indigo silk lining
	back_mat.roughness = 0.95
	var width := COLS * CELL_W
	var height := _rows * CELL_H
	var cx := 0.0
	# back panel, top, bottom and sides
	M.add_mesh(self, _box(Vector3(width + BOARD, height + BOARD, 0.1)), back_mat, Vector3(cx, height * 0.5, -DEPTH * 0.5))
	for r in _rows + 1:
		M.add_mesh(self, _box(Vector3(width + BOARD, BOARD, DEPTH)), wood, Vector3(cx, r * CELL_H, 0))
	# vertical dividers: per row, so a short last row gets its own spacing
	for r in _rows:
		var in_row := mini(COLS, Data.SPECIES_ORDER.size() - r * COLS)
		var y := (_rows - 1 - r) * CELL_H + CELL_H * 0.5
		var left := -in_row * CELL_W * 0.5
		for c in in_row + 1:
			M.add_mesh(self, _box(Vector3(BOARD, CELL_H, DEPTH)), wood, Vector3(left + c * CELL_W, y, 0))
		# fill the gaps beside a short row with carved lattice panels
		if in_row < COLS:
			for side in [-1.0, 1.0]:
				var gap_x: float = side * (width * 0.5 - (COLS - in_row) * CELL_W * 0.25)
				_lattice(Vector3(gap_x, y, 0), (COLS - in_row) * CELL_W * 0.5, wood)
	# a deep base under the bottom row carries its plaques
	M.add_mesh(self, _box(Vector3(width + BOARD * 3.0, 0.62, DEPTH + 0.1)), wood, Vector3(cx, -0.31, 0))
	# outer frame posts
	for side in [-1.0, 1.0]:
		M.add_mesh(self, _box(Vector3(BOARD * 1.6, height + BOARD * 2.0, DEPTH + 0.1)), wood, Vector3(cx + side * width * 0.5, height * 0.5, 0))
	# a gold trim along the front edge of every shelf
	for r in _rows + 1:
		M.add_mesh(self, _box(Vector3(width, 0.03, 0.03)), M.brass(Color(1.0, 0.78, 0.35), 0.3), Vector3(cx, r * CELL_H + BOARD * 0.5, DEPTH * 0.5))
	# a soft lamp at the top of each compartment
	for i in Data.SPECIES_ORDER.size():
		var p := cell_floor(i)
		var lamp := M.add_mesh(self, _box(Vector3(CELL_W * 0.7, 0.03, 0.4)), M.glow(Color(1.0, 0.85, 0.6), 1.2),
			Vector3(p.x, p.y + CELL_H - BOARD * 0.5 - 0.03, 0.4))
		_lamps.append(lamp)
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.88, 0.7)
		light.light_energy = 1.1
		light.omni_range = 3.2
		light.position = Vector3(p.x, p.y + CELL_H - 0.6, 0.9)
		add_child(light)


## Carved lattice filling an empty stretch of a row (a common 博古架 detail).
func _lattice(center: Vector3, w: float, wood: Material) -> void:
	M.add_mesh(self, _box(Vector3(w, CELL_H, 0.12)), wood, center + Vector3(0, 0, -DEPTH * 0.5 + 0.1))
	var trim := M.brass(Color(0.9, 0.68, 0.32), 0.35)
	for k in 3:
		var s := 0.35 + k * 0.28
		M.add_mesh(self, M.torus(s * w * 0.28, s * w * 0.28 + 0.04, 40), trim, center + Vector3(0, 0, -DEPTH * 0.5 + 0.2), Vector3(90, 0, 0))


func _plaque(i: int, sp: Dictionary) -> void:
	var p := cell_floor(i)
	var front := DEPTH * 0.5 + 0.03
	var py := p.y - BOARD - 0.24   # hangs just under the shelf board, clear of the figure
	var lacquer := StandardMaterial3D.new()
	lacquer.albedo_color = Color(0.05, 0.03, 0.03)
	lacquer.roughness = 0.25
	M.add_mesh(self, _box(Vector3(2.5, 0.42, 0.04)), lacquer, Vector3(p.x, py, front))
	M.add_mesh(self, _box(Vector3(2.56, 0.48, 0.02)), M.brass(Color(1.0, 0.78, 0.35), 0.3), Vector3(p.x, py, front - 0.02))
	# two lines, each shrunk to fit the plaque (English names are long)
	_plaque_line(I18n.f(sp, "name"), Vector3(p.x, py + 0.08, front + 0.03), 44, 2.3)
	_plaque_line(I18n.f(sp.origin, "era"), Vector3(p.x, py - 0.12, front + 0.03), 30, 2.3)


func _plaque_line(text: String, pos: Vector3, size: int, max_w: float) -> void:
	var l := Label3D.new()
	l.font = M.ui_font()
	l.text = text
	l.font_size = size
	var w_px: float = l.font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	l.pixel_size = minf(0.0042, max_w / maxf(w_px, 1.0))
	l.modulate = Color(1.0, 0.82, 0.45)
	l.outline_size = 0
	l.shaded = false
	l.position = pos
	add_child(l)


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func overview(snap: bool = false) -> void:
	_focus = -1
	var h := _rows * CELL_H
	var dist := (h * 0.5 + 1.6) / tan(deg_to_rad(FOV * 0.5)) + DEPTH * 0.5
	var y := h * 0.5 - 0.15
	cam.set_view(Vector3(VIEW_SHIFT, y + 0.6, dist), Vector3(VIEW_SHIFT, y, 0), 2.5, snap)


func _process(delta: float) -> void:
	_time += delta
	for i in _units.size():
		var u: Node3D = _units[i]
		var target := PI + (sin(_time * 0.6 + i) * 0.3 if i != _focus else (0.0 if still else _time * 0.8))
		u.rotation.y = lerp_angle(u.rotation.y, target, minf(1.0, delta * 3.0))
		var lamp: MeshInstance3D = _lamps[i]
		var mat: StandardMaterial3D = lamp.material_override
		mat.emission_energy_multiplier = lerpf(mat.emission_energy_multiplier, 3.5 if i == _focus else 1.2, minf(1.0, delta * 4.0))


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	if event.button_index == MOUSE_BUTTON_RIGHT:
		overview()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	var best := -1
	var best_d := 110.0
	for i in _units.size():
		var p: Vector3 = _units[i].center_position()
		var d := cam.unproject_position(p).distance_to(event.position)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		focus(best)
	elif _focus >= 0:
		overview()


func focus(i: int) -> void:
	_focus = i
	var p := cell_floor(i)
	# stand in front of the compartment, a little to the right so the panel does not cover it
	cam.set_view(Vector3(p.x + 1.8, p.y + 1.5, 13.5), Vector3(p.x + 1.8, p.y + 1.1, 0), 2.5)
	selected.emit(Data.SPECIES_ORDER[i])
