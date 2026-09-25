extends Node3D
## Goldmend :: Vessel Spirit codex (器灵图鉴).
## All spirits stand on their plinths in two rows, like a museum display.
## Clicking one selects it; the game shows its real-world origin and lore.

const Data = preload("po_data.gd")
const I18n = preload("po_i18n.gd")
const M = preload("po_mat.gd")
const Arena = preload("po_arena.gd")
const Unit = preload("po_unit.gd")
const Cam = preload("po_camera.gd")

signal selected(species_id: String)

var cam: Camera3D
var _units: Array = []
var _time := 0.0
var _focus := -1


func _ready() -> void:
	Arena.make_environment(self)
	cam = Cam.new()
	add_child(cam)
	cam.make_current()
	# display shelf
	M.add_mesh(self, M.cylinder(11.0, 11.0, 0.4, 96), M.porcelain(Color(0.07, 0.1, 0.3), 0.0, Color(0.9, 0.8, 1.0), 1.0, 0.35, 0.0, Color(0.1, 0.1, 0.2)), Vector3(0, -0.2, 0))
	M.add_mesh(self, M.torus(10.9, 11.2, 128), M.brass(), Vector3(0, 0.0, 0))
	var ids: Array = Data.SPECIES_ORDER
	for i in ids.size():
		var row := i / 4
		var col := i % 4
		var u := Unit.new()
		u.setup(ids[i], 0, 1, Data.compute_stats(ids[i], 1))
		add_child(u)
		u.position = Vector3(-6.2 + col * 3.0, 0, -1.4 + row * 3.4)
		u.rotation.y = 0.0
		u.look_at(u.global_position + Vector3(0, 0, 1), Vector3.UP)
		_units.append(u)
		var l := Label3D.new()
		l.font = M.ui_font()
		var sp: Dictionary = Data.SPECIES[ids[i]]
		l.text = "%s\n%s" % [I18n.f(sp, "name"), I18n.f(sp.origin, "era")]
		l.font_size = 46
		l.pixel_size = 0.006
		l.modulate = Data.ELEMENT_COLORS[sp.element].lerp(Color.WHITE, 0.45)
		l.outline_size = 16
		l.outline_modulate = Color(0.02, 0.02, 0.08)
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.position = u.position + Vector3(0, 0.15, 1.35)
		add_child(l)
	cam.set_view(Vector3(-1.6, 5.2, 9.6), Vector3(-1.6, 0.9, 0.4), 2.0, true)


func _process(delta: float) -> void:
	_time += delta
	for i in _units.size():
		var u: Node3D = _units[i]
		var target := PI + (sin(_time * 0.6 + i) * 0.35 if i != _focus else _time * 0.8)
		u.rotation.y = lerp_angle(u.rotation.y, target, minf(1.0, delta * 3.0))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var best := -1
		var best_d := 90.0
		for i in _units.size():
			var p: Vector3 = _units[i].center_position()
			var d := cam.unproject_position(p).distance_to(event.position)
			if d < best_d:
				best_d = d
				best = i
		if best >= 0:
			focus(best)


func focus(i: int) -> void:
	_focus = i
	var u: Node3D = _units[i]
	cam.set_view(u.global_position + Vector3(0, 3.4, 4.4), u.global_position + Vector3(0, 1.0, 0), 2.5)
	selected.emit(Data.SPECIES_ORDER[i])
