extends RefCounted
## Porcelain Orrery :: procedural creature models.
## Each creature is a porcelain automaton assembled from primitives, dipped in
## its element's glaze and mended with kintsugi gold (po_porcelain.gdshader).
## Models face -Z. The returned root carries metadata used by the unit:
##   "spinners":  Array of [Node3D, Vector3 axis, float deg_per_sec]
##   "bobbers":   Array of [Node3D, float amplitude, float speed, float phase]
##   "porcelain": Array of ShaderMaterial (unit drives their `damage` uniform)
##   "height", "radius", "muzzle"

const M = preload("po_mat.gd")
const Data = preload("po_data.gd")

## Glaze colour per element: oxblood, cobalt, celadon, ivory-gold, tenmoku.
const GLAZES := [
	Color(0.62, 0.07, 0.06),
	Color(0.07, 0.2, 0.68),
	Color(0.42, 0.68, 0.55),
	Color(0.93, 0.78, 0.42),
	Color(0.07, 0.05, 0.08),
]


class Kit:
	var root: Node3D
	var glaze: Color
	var core: Color
	var eye: Color

	func p(dip: float = 0.0, glaze_all: float = 0.0, crack: float = 3.2, body: Color = Color(0.95, 0.94, 0.9)) -> ShaderMaterial:
		var m := M.porcelain(glaze, dip, core, glaze_all, crack, 0.014, body)
		root.get_meta("porcelain").append(m)
		return m

	func spin(node: Node3D, axis: Vector3, speed: float) -> void:
		root.get_meta("spinners").append([node, axis, speed])

	func bob(node: Node3D, amp: float, speed: float, phase: float = 0.0) -> void:
		root.get_meta("bobbers").append([node, amp, speed, phase])

	func node(parent: Node3D, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Node3D:
		var n := Node3D.new()
		n.position = pos
		n.rotation_degrees = rot
		parent.add_child(n)
		return n

	func muzzle(parent: Node3D, pos: Vector3) -> void:
		var m := node(parent, pos)
		m.name = "Muzzle"
		root.set_meta("muzzle", m)

	func eyes(parent: Node3D, pos: Vector3, spread: float, size: float) -> void:
		for side in [-1.0, 1.0]:
			M.add_mesh(parent, M.sphere(size), M.glow(eye, 6.0), pos + Vector3(side * spread, 0, 0))


static func build(species_id: String, is_enemy: bool) -> Node3D:
	var k := Kit.new()
	k.root = Node3D.new()
	k.root.name = "Model"
	k.root.set_meta("spinners", [])
	k.root.set_meta("bobbers", [])
	k.root.set_meta("porcelain", [])
	var el: int = Data.SPECIES[species_id].element
	k.glaze = GLAZES[el]
	k.core = Data.ELEMENT_COLORS[el]
	k.eye = Color(1.0, 0.2, 0.25) if is_enemy else k.core.lerp(Color.WHITE, 0.35)
	match species_id:
		"emberlynx":
			_ember_lynx(k)
		"tidemoth":
			_tide_moth(k)
		"chimeram":
			_chime_ram(k)
		"lumenowl":
			_lumen_owl(k)
		"kilnbear":
			_kiln_bear(k)
		"cobaltshell":
			_cobalt_shell(k)
		"galemantis":
			_mantis(k)
		"tenmoku":
			_serpent(k)
	return k.root


# --- Ember Lynx: lithe porcelain cat, oxblood glaze, flame-tipped ear tufts --------
static func _ember_lynx(k: Kit) -> void:
	var body := k.node(k.root, Vector3.ZERO)
	k.bob(body, 0.035, 3.0)
	var torso := k.p(0.05)
	M.add_mesh(body, M.capsule(0.34, 1.4), torso, Vector3(0, 0.9, 0.05), Vector3(90, 0, 0))
	M.add_mesh(body, M.sphere(0.4), k.p(-0.05), Vector3(0, 1.02, -0.45), Vector3.ZERO, Vector3(1, 1, 1.1))
	M.add_mesh(body, M.torus(0.3, 0.37), M.brass(), Vector3(0, 1.18, -0.62), Vector3(65, 0, 0))
	var head := k.node(body, Vector3(0, 1.38, -0.85))
	k.bob(head, 0.03, 1.6, 1.0)
	M.add_mesh(head, M.sphere(0.3), k.p(-0.12), Vector3.ZERO, Vector3.ZERO, Vector3(1.1, 0.95, 1.0))
	M.add_mesh(head, M.sphere(0.15), k.p(0.2), Vector3(0, -0.08, -0.24), Vector3.ZERO, Vector3(1.2, 0.8, 1.0))
	M.add_mesh(head, M.sphere(0.045), M.brass(Color(0.3, 0.12, 0.1)), Vector3(0, -0.02, -0.38))
	k.eyes(head, Vector3(0, 0.06, -0.24), 0.12, 0.05)
	for side in [-1.0, 1.0]:
		var ear := k.node(head, Vector3(side * 0.17, 0.26, 0.02), Vector3(0, 0, side * -14))
		M.add_mesh(ear, M.prism(Vector3(0.18, 0.34, 0.06)), k.p(0.0, 1.0), Vector3(0, 0.1, 0))
		var tuft := M.particles(k.core, 14, 0.5, 0.16, 0.7, Vector3.UP, 15, Vector3(0, 1.0, 0), 0.02)
		tuft.position = Vector3(0, 0.3, 0)
		ear.add_child(tuft)
		M.add_mesh(head, M.prism(Vector3(0.2, 0.16, 0.05)), k.p(0.0, 1.0), Vector3(side * 0.3, -0.12, -0.02), Vector3(0, side * 30, side * 90))
	k.muzzle(head, Vector3(0, 0, -0.4))
	for lp in [Vector3(-0.2, 0, -0.5), Vector3(0.2, 0, -0.5), Vector3(-0.2, 0, 0.5), Vector3(0.2, 0, 0.5)]:
		var leg := k.node(body, lp + Vector3(0, 0.8, 0))
		M.add_mesh(leg, M.cylinder(0.09, 0.07, 0.72), k.p(-0.05), Vector3(0, -0.4, 0))
		M.add_mesh(leg, M.sphere(0.1), k.p(0.5, 1.0), Vector3(0, -0.76, -0.04), Vector3.ZERO, Vector3(1, 0.6, 1.3))
	var tail := k.node(body, Vector3(0, 1.0, 0.72), Vector3(-55, 0, 0))
	k.bob(tail, 0.06, 2.5, 0.5)
	for i in 4:
		M.add_mesh(tail, M.sphere(0.1 - i * 0.012), k.p(0.0, 1.0 if i == 3 else 0.0), Vector3(0, i * 0.18, i * 0.05))
	var flame := M.particles(k.core, 24, 0.55, 0.26, 1.0, Vector3.UP, 20, Vector3(0, 1.4, 0), 0.06)
	flame.position = Vector3(0, 0.72, 0.15)
	tail.add_child(flame)
	var embers := M.particles(Color(1.0, 0.75, 0.35), 18, 1.4, 0.07, 1.2, Vector3.UP, 45, Vector3(0, 0.4, 0), 0.55)
	embers.position = Vector3(0, 1.0, 0)
	body.add_child(embers)
	k.root.set_meta("height", 1.9)
	k.root.set_meta("radius", 0.8)


# --- Tide Moth: floating moth, cobalt-dipped porcelain wings, orbiting droplets ----
static func _tide_moth(k: Kit) -> void:
	var body := k.node(k.root, Vector3(0, 0.9, 0))
	k.bob(body, 0.14, 1.5)
	M.add_mesh(body, M.sphere(0.26), k.p(-0.1), Vector3(0, 0.75, 0), Vector3.ZERO, Vector3(1, 1.1, 1))
	for i in 3:
		M.add_mesh(body, M.sphere(0.24 - i * 0.05), k.p(0.1, 1.0 if i == 2 else 0.0), Vector3(0, 0.45 - i * 0.24, 0.12 + i * 0.1))
	var head := k.node(body, Vector3(0, 1.08, -0.1))
	M.add_mesh(head, M.sphere(0.17), k.p(0.1, 0.0))
	k.eyes(head, Vector3(0, 0.02, -0.13), 0.09, 0.055)
	for side in [-1.0, 1.0]:
		var ant := k.node(head, Vector3(side * 0.07, 0.12, -0.05), Vector3(-25, 0, side * -25))
		M.add_mesh(ant, M.capsule(0.015, 0.45), M.brass(), Vector3(0, 0.22, 0))
		for f in 4:
			M.add_mesh(ant, M.prism(Vector3(0.14 - f * 0.02, 0.05, 0.01)), M.brass(), Vector3(0, 0.12 + f * 0.08, 0))
		M.add_mesh(ant, M.sphere(0.035), M.glow(k.core, 5.0), Vector3(0, 0.46, 0))
		for w in 2:
			var pivot := k.node(body, Vector3(side * 0.12, 0.8 - w * 0.3, 0.05))
			var wing := k.node(pivot, Vector3.ZERO)
			var size := Vector3(0.95, 0.62, 0.04) if w == 0 else Vector3(0.7, 0.5, 0.04)
			M.add_mesh(wing, M.sphere(0.5, 20, 10), k.p(-0.05 + w * 0.05, 0.0, 4.5),
				Vector3(side * 0.48, 0.12 - w * 0.2, 0.05), Vector3(0, side * 12, side * (28 - w * 60)), size)
			M.add_mesh(wing, M.sphere(0.12, 12, 6), M.glow(k.core, 3.0), Vector3(side * 0.62, 0.2 - w * 0.28, 0.02),
				Vector3.ZERO, Vector3(1, 1, 0.3))
			k.bob(wing, 0.06, 7.5, w * 0.9)
			k.spin(wing, Vector3.FORWARD, 0.0)
	k.muzzle(head, Vector3(0, 0, -0.25))
	var orbit := k.node(body, Vector3(0, 0.55, 0))
	for i in 5:
		var a := TAU * i / 5.0
		M.add_mesh(orbit, M.sphere(0.07), M.glow(k.core.lerp(Color.WHITE, 0.3), 4.0, 0.85), Vector3(cos(a), 0.2 * sin(a * 3.0), sin(a)) * 0.95)
	k.spin(orbit, Vector3.UP, 70.0)
	for i in 2:
		var ring := M.add_mesh(k.root, M.torus(0.5 + i * 0.3, 0.55 + i * 0.3), M.glow(k.core, 2.0, 0.55), Vector3(0, 0.04 + i * 0.01, 0))
		k.bob(ring, 0.02, 2.0, i * 1.5)
	var dust := M.particles(k.core.lerp(Color.WHITE, 0.5), 30, 1.8, 0.1, 0.4, Vector3.DOWN, 50, Vector3(0, -0.4, 0), 0.8)
	dust.position = Vector3(0, 0.6, 0)
	body.add_child(dust)
	k.root.set_meta("height", 2.3)
	k.root.set_meta("radius", 0.8)


# --- Chime Ram: woolly porcelain ram with spiral horns hung with brass chimes -----
static func _chime_ram(k: Kit) -> void:
	var body := k.node(k.root, Vector3.ZERO)
	k.bob(body, 0.03, 2.2)
	var wool := k.p(0.0)
	M.add_mesh(body, M.sphere(0.55), wool, Vector3(0, 1.0, 0.05), Vector3.ZERO, Vector3(1.0, 0.85, 1.35))
	for i in 9:
		var a := TAU * i / 9.0
		M.add_mesh(body, M.sphere(0.22), k.p(-0.05), Vector3(cos(a) * 0.42, 1.2 + sin(a * 2.0) * 0.08, sin(a) * 0.55 + 0.05))
	var head := k.node(body, Vector3(0, 1.3, -0.72))
	k.bob(head, 0.025, 1.4, 0.6)
	M.add_mesh(head, M.sphere(0.26), k.p(0.3, 1.0), Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 1.0, 1.25))
	M.add_mesh(head, M.sphere(0.2), k.p(0.1), Vector3(0, 0.12, 0.02))
	k.eyes(head, Vector3(0, 0.05, -0.2), 0.14, 0.045)
	for side in [-1.0, 1.0]:
		var horn := k.node(head, Vector3(side * 0.2, 0.2, 0.05))
		for i in 7:
			var a := i * 0.8
			var r := 0.22 - i * 0.012
			var pos := Vector3(side * (0.12 + sin(a) * r), cos(a) * r * 0.9, 0.1 - i * 0.02 + (1.0 - cos(a)) * 0.05)
			M.add_mesh(horn, M.sphere(0.1 - i * 0.008), k.p(0.0, 1.0, 5.0), pos)
		for c in 3:
			var chime := k.node(horn, Vector3(side * (0.1 + c * 0.08), -0.25, 0.05 + c * 0.04))
			M.add_mesh(chime, M.cylinder(0.018, 0.018, 0.2 + c * 0.05, 8), M.brass(), Vector3(0, -0.12 - c * 0.02, 0))
			k.bob(chime, 0.02, 5.0 + c, c)
	k.muzzle(head, Vector3(0, 0.1, -0.3))
	for lp in [Vector3(-0.25, 0, -0.35), Vector3(0.25, 0, -0.35), Vector3(-0.25, 0, 0.45), Vector3(0.25, 0, 0.45)]:
		var leg := k.node(body, lp + Vector3(0, 0.6, 0))
		M.add_mesh(leg, M.cylinder(0.08, 0.07, 0.55), k.p(-0.1, 1.0), Vector3(0, -0.3, 0))
		M.add_mesh(leg, M.cylinder(0.09, 0.1, 0.1), M.brass(), Vector3(0, -0.56, 0))
	var swirl := M.particles(k.core, 36, 1.2, 0.18, 1.6, Vector3.UP, 12, Vector3.ZERO, 0.9)
	swirl.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	swirl.emission_ring_axis = Vector3.UP
	swirl.emission_ring_radius = 1.0
	swirl.emission_ring_inner_radius = 0.85
	swirl.emission_ring_height = 0.05
	swirl.tangential_accel_min = 3.0
	swirl.tangential_accel_max = 5.0
	swirl.position = Vector3(0, 0.15, 0)
	body.add_child(swirl)
	k.root.set_meta("height", 1.9)
	k.root.set_meta("radius", 0.8)


# --- Lumen Owl: round ivory owl hovering over a brass perch, lantern eyes ----------
static func _lumen_owl(k: Kit) -> void:
	var perch := k.node(k.root, Vector3(0, 0.4, 0))
	M.add_mesh(perch, M.torus(0.42, 0.48), M.brass(), Vector3.ZERO)
	k.spin(perch, Vector3.UP, 30.0)
	var body := k.node(k.root, Vector3(0, 0.55, 0))
	k.bob(body, 0.1, 1.4)
	M.add_mesh(body, M.sphere(0.5), k.p(-0.15), Vector3(0, 0.62, 0), Vector3.ZERO, Vector3(1, 1.2, 0.95))
	M.add_mesh(body, M.sphere(0.36), k.p(0.0, 0.0, 5.0, Color(1, 0.99, 0.95)), Vector3(0, 0.55, -0.22), Vector3.ZERO, Vector3(1, 1.2, 0.6))
	var head := k.node(body, Vector3(0, 1.25, -0.02))
	k.bob(head, 0.03, 0.9, 0.3)
	M.add_mesh(head, M.sphere(0.42), k.p(-0.3), Vector3.ZERO, Vector3.ZERO, Vector3(1.15, 0.9, 1.0))
	for side in [-1.0, 1.0]:
		M.add_mesh(head, M.sphere(0.17), k.p(0.3, 0.0, 3.2, Color(1, 1, 0.97)), Vector3(side * 0.17, 0.0, -0.3), Vector3.ZERO, Vector3(1, 1, 0.4))
		M.add_mesh(head, M.torus(0.1, 0.13), M.brass(), Vector3(side * 0.17, 0.0, -0.35), Vector3(90, 0, 0))
		M.add_mesh(head, M.prism(Vector3(0.14, 0.28, 0.06)), k.p(0.0, 1.0), Vector3(side * 0.3, 0.38, 0.0), Vector3(0, 0, side * -20))
		var wing := k.node(body, Vector3(side * 0.48, 0.7, 0.05), Vector3(0, 0, side * 8))
		M.add_mesh(wing, M.sphere(0.4), k.p(0.1, 0.0, 4.0), Vector3(0, -0.1, 0), Vector3(0, 0, side * 10), Vector3(0.3, 1.0, 0.8))
		k.bob(wing, 0.04, 3.0, side)
		M.add_mesh(body, M.cylinder(0.03, 0.05, 0.2, 8), M.brass(), Vector3(side * 0.15, 0.0, -0.05))
	k.eyes(head, Vector3(0, 0.0, -0.37), 0.17, 0.075)
	M.add_mesh(head, M.prism(Vector3(0.08, 0.12, 0.08)), M.brass(), Vector3(0, -0.12, -0.38), Vector3(180, 0, 0))
	var lantern := OmniLight3D.new()
	lantern.light_color = k.core
	lantern.light_energy = 1.2
	lantern.omni_range = 2.5
	lantern.position = Vector3(0, 0, -0.6)
	head.add_child(lantern)
	k.muzzle(head, Vector3(0, 0, -0.45))
	var halo := k.node(body, Vector3(0, 1.3, 0))
	for i in 8:
		var a := TAU * i / 8.0
		M.add_mesh(halo, M.prism(Vector3(0.06, 0.16, 0.02)), M.glow(k.core, 3.5), Vector3(cos(a), 0, sin(a)) * 0.78, Vector3(90, rad_to_deg(-a), 0))
	k.spin(halo, Vector3.UP, -40.0)
	var motes := M.particles(k.core, 22, 2.0, 0.1, 0.35, Vector3.UP, 90, Vector3(0, 0.2, 0), 0.9)
	motes.position = Vector3(0, 0.8, 0)
	body.add_child(motes)
	k.root.set_meta("height", 2.25)
	k.root.set_meta("radius", 0.75)


# --- Kiln Bear: hulking bear with a burning kiln in its chest and a chimney -------
static func _kiln_bear(k: Kit) -> void:
	var body := k.node(k.root, Vector3.ZERO)
	k.bob(body, 0.03, 1.4)
	M.add_mesh(body, M.sphere(0.72), k.p(-0.1, 0.0, 2.6), Vector3(0, 1.2, 0.05), Vector3.ZERO, Vector3(1.1, 1.05, 0.95))
	M.add_mesh(body, M.sphere(0.5), k.p(0.2), Vector3(0, 1.75, -0.08))
	# the kiln
	M.add_mesh(body, M.torus(0.26, 0.34), M.brass(Color(0.55, 0.38, 0.22), 0.45), Vector3(0, 1.2, -0.66), Vector3(90, 0, 0))
	M.add_mesh(body, M.cylinder(0.27, 0.27, 0.05, 24), M.glow(k.core, 5.0), Vector3(0, 1.2, -0.64), Vector3(90, 0, 0))
	var fire := M.particles(k.core, 30, 0.6, 0.22, 1.0, Vector3(0, 0.6, -1), 25, Vector3(0, 1.5, 0), 0.15)
	fire.position = Vector3(0, 1.2, -0.7)
	body.add_child(fire)
	var glow_light := OmniLight3D.new()
	glow_light.light_color = k.core
	glow_light.light_energy = 1.6
	glow_light.omni_range = 3.0
	glow_light.position = Vector3(0, 1.2, -1.0)
	body.add_child(glow_light)
	# chimney + smoke
	M.add_mesh(body, M.cylinder(0.12, 0.14, 0.5, 12), M.brass(Color(0.4, 0.3, 0.25), 0.5), Vector3(0.28, 2.2, 0.3), Vector3(-10, 0, -10))
	var smoke := M.particles(Color(0.55, 0.5, 0.6, 0.5), 20, 2.2, 0.45, 0.8, Vector3.UP, 12, Vector3(0, 0.3, 0.2), 0.08, false)
	smoke.position = Vector3(0.32, 2.5, 0.35)
	body.add_child(smoke)
	var head := k.node(body, Vector3(0, 2.15, -0.35))
	k.bob(head, 0.025, 1.2, 0.8)
	M.add_mesh(head, M.sphere(0.34), k.p(-0.05), Vector3.ZERO, Vector3.ZERO, Vector3(1.1, 0.95, 1.0))
	M.add_mesh(head, M.sphere(0.16), k.p(0.3, 1.0), Vector3(0, -0.08, -0.3), Vector3.ZERO, Vector3(1.2, 0.9, 1.0))
	k.eyes(head, Vector3(0, 0.08, -0.28), 0.13, 0.045)
	for side in [-1.0, 1.0]:
		M.add_mesh(head, M.sphere(0.12), k.p(0.0, 1.0), Vector3(side * 0.28, 0.28, 0.02), Vector3.ZERO, Vector3(1, 1, 0.6))
		var arm := k.node(body, Vector3(side * 0.82, 1.6, -0.1), Vector3(-15, 0, side * 12))
		M.add_mesh(arm, M.capsule(0.2, 0.9), k.p(0.1), Vector3(0, -0.4, 0))
		M.add_mesh(arm, M.sphere(0.26), k.p(0.2, 1.0), Vector3(0, -0.9, -0.05))
		k.bob(arm, 0.04, 1.4, side)
		M.add_mesh(body, M.cylinder(0.22, 0.25, 0.55), k.p(0.3, 1.0), Vector3(side * 0.38, 0.3, 0.05))
	k.muzzle(body, Vector3(0, 1.2, -0.9))
	k.root.set_meta("height", 2.6)
	k.root.set_meta("radius", 1.0)


# --- Cobalt Shell: blue-and-white porcelain tortoise with a gilded rim -------------
static func _cobalt_shell(k: Kit) -> void:
	var body := k.node(k.root, Vector3.ZERO)
	k.bob(body, 0.02, 1.0)
	var shell := k.node(body, Vector3(0, 0.75, 0.05))
	M.add_mesh(shell, M.sphere(0.95, 28, 14), k.p(0.4, 0.0, 2.2), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.62, 1.15))
	M.add_mesh(shell, M.torus(0.9, 1.0, 64), M.brass(), Vector3(0, -0.05, 0), Vector3.ZERO, Vector3(1.0, 1.0, 1.12))
	for i in 6:
		var a := TAU * i / 6.0
		M.add_mesh(shell, M.sphere(0.22, 6, 3), k.p(0.0, 1.0), Vector3(cos(a) * 0.5, 0.42, sin(a) * 0.58), Vector3.ZERO, Vector3(1, 0.4, 1))
	M.add_mesh(shell, M.sphere(0.26, 6, 3), k.p(0.0, 1.0), Vector3(0, 0.6, 0), Vector3.ZERO, Vector3(1, 0.45, 1))
	var head := k.node(body, Vector3(0, 0.85, -1.15))
	k.bob(head, 0.04, 1.3, 0.4)
	M.add_mesh(head, M.capsule(0.15, 0.5), k.p(0.0), Vector3(0, -0.1, 0.25), Vector3(60, 0, 0))
	M.add_mesh(head, M.sphere(0.22), k.p(-0.05), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.9, 1.2))
	k.eyes(head, Vector3(0, 0.06, -0.18), 0.12, 0.04)
	k.muzzle(head, Vector3(0, 0, -0.3))
	for lp in [Vector3(-0.7, 0, -0.6), Vector3(0.7, 0, -0.6), Vector3(-0.7, 0, 0.7), Vector3(0.7, 0, 0.7)]:
		M.add_mesh(body, M.sphere(0.24), k.p(0.1), lp + Vector3(0, 0.25, 0), Vector3.ZERO, Vector3(1, 1.2, 1))
	M.add_mesh(body, M.capsule(0.08, 0.35), k.p(0.1), Vector3(0, 0.55, 1.2), Vector3(70, 0, 0))
	for i in 2:
		var ring := M.add_mesh(k.root, M.torus(1.25 + i * 0.3, 1.3 + i * 0.3), M.glow(k.core, 2.0, 0.5), Vector3(0, 0.04, 0))
		k.bob(ring, 0.02, 1.6, i * 1.2)
	var bubbles := M.particles(k.core.lerp(Color.WHITE, 0.4), 16, 2.0, 0.12, 0.6, Vector3.UP, 20, Vector3(0, 0.2, 0), 1.0)
	bubbles.position = Vector3(0, 0.4, 0)
	body.add_child(bubbles)
	k.root.set_meta("height", 1.9)
	k.root.set_meta("radius", 1.1)


# --- Celadon Mantis: eggshell-thin mantis with gold-edged scythe arms -------------
static func _mantis(k: Kit) -> void:
	var body := k.node(k.root, Vector3.ZERO)
	k.bob(body, 0.05, 2.4)
	M.add_mesh(body, M.sphere(0.3), k.p(0.1), Vector3(0, 0.75, 0.55), Vector3(-20, 0, 0), Vector3(0.8, 0.75, 1.8))
	var thorax := k.node(body, Vector3(0, 1.1, -0.05), Vector3(-30, 0, 0))
	M.add_mesh(thorax, M.capsule(0.13, 0.9), k.p(-0.2), Vector3(0, 0.3, 0))
	var head := k.node(body, Vector3(0, 1.72, -0.4))
	k.bob(head, 0.04, 1.8, 0.4)
	M.add_mesh(head, M.prism(Vector3(0.42, 0.34, 0.2)), k.p(0.0, 1.0), Vector3.ZERO, Vector3(180, 0, 0))
	for side in [-1.0, 1.0]:
		M.add_mesh(head, M.sphere(0.09), M.glow(k.eye, 5.0), Vector3(side * 0.18, 0.08, -0.02), Vector3.ZERO, Vector3(1, 1.2, 1))
		M.add_mesh(head, M.capsule(0.01, 0.5), M.brass(), Vector3(side * 0.08, 0.35, 0.05), Vector3(-30, 0, side * -20))
		var arm := k.node(body, Vector3(side * 0.18, 1.45, -0.35), Vector3(-35, 0, side * 8))
		M.add_mesh(arm, M.capsule(0.05, 0.55), k.p(0.1), Vector3(0, -0.2, 0))
		var blade := k.node(arm, Vector3(0, -0.45, -0.05), Vector3(120, 0, 0))
		M.add_mesh(blade, M.prism(Vector3(0.05, 0.75, 0.16), 0.2), k.p(0.4, 1.0, 5.0), Vector3(0, 0.3, 0))
		M.add_mesh(blade, M.capsule(0.012, 0.7), M.brass(Color(1.0, 0.8, 0.4), 0.2), Vector3(0, 0.3, -0.07))
		k.bob(arm, 0.05, 2.0, side)
		for li in 2:
			var leg := k.node(body, Vector3(side * 0.12, 0.8, 0.1 + li * 0.35), Vector3(0, 0, side * 40))
			M.add_mesh(leg, M.capsule(0.025, 0.8), k.p(0.1, 1.0), Vector3(side * 0.0, -0.35, 0))
		var wing := k.node(body, Vector3(side * 0.1, 1.05, 0.35), Vector3(-15, side * 10, side * -8))
		M.add_mesh(wing, M.sphere(0.5, 16, 8), M.glow(k.core, 1.5, 0.3), Vector3(side * 0.15, 0, 0.3), Vector3.ZERO, Vector3(0.35, 0.05, 1.2))
		k.bob(wing, 0.03, 9.0, side)
	k.muzzle(head, Vector3(0, 0, -0.3))
	var leaves := M.particles(k.core, 20, 1.5, 0.14, 1.2, Vector3.UP, 30, Vector3(0, 0.2, 0), 0.6)
	leaves.position = Vector3(0, 0.6, 0)
	leaves.tangential_accel_min = 2.0
	leaves.tangential_accel_max = 3.0
	body.add_child(leaves)
	k.root.set_meta("height", 2.1)
	k.root.set_meta("radius", 0.75)


# --- Tenmoku Serpent: black-glazed coiled serpent with oil-spot sheen --------------
static func _serpent(k: Kit) -> void:
	var body := k.node(k.root, Vector3(0, 0.3, 0))
	k.bob(body, 0.12, 1.1)
	var coil := k.node(body, Vector3.ZERO)
	k.spin(coil, Vector3.UP, 25.0)
	var n := 16
	for i in n:
		var t := float(i) / n
		var a := t * TAU * 1.6
		var r := 0.62 - t * 0.2
		var seg := M.add_mesh(coil, M.sphere(0.24 - t * 0.08, 20, 10), k.p(0.3, 1.0, 4.0, Color(0.2, 0.18, 0.24)),
			Vector3(cos(a) * r, 0.2 + t * 0.9, sin(a) * r))
		k.bob(seg, 0.03, 3.0, t * 6.0)
	var neck := k.node(body, Vector3(0, 1.2, -0.2))
	for i in 3:
		M.add_mesh(neck, M.sphere(0.16 - i * 0.01), k.p(0.3, 1.0, 4.0, Color(0.2, 0.18, 0.24)), Vector3(0, i * 0.2, -i * 0.08))
	var head := k.node(body, Vector3(0, 1.92, -0.45))
	k.bob(head, 0.05, 1.3, 0.2)
	M.add_mesh(head, M.sphere(0.24), k.p(0.3, 1.0, 4.0, Color(0.2, 0.18, 0.24)), Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 0.7, 1.35))
	M.add_mesh(head, M.sphere(0.4, 20, 10), k.p(0.0, 1.0, 3.0, Color(0.2, 0.18, 0.24)), Vector3(0, 0.02, 0.25), Vector3(-10, 0, 0), Vector3(1.35, 1.1, 0.12))
	k.eyes(head, Vector3(0, 0.07, -0.2), 0.1, 0.045)
	for side in [-1.0, 1.0]:
		M.add_mesh(head, M.prism(Vector3(0.03, 0.1, 0.03)), M.brass(Color(1, 0.9, 0.7), 0.2), Vector3(side * 0.06, -0.12, -0.25), Vector3(180, 0, 0))
	k.muzzle(head, Vector3(0, 0, -0.35))
	# oil-spot motes
	var orbit := k.node(body, Vector3(0, 0.9, 0))
	for i in 4:
		var a := TAU * i / 4.0
		M.add_mesh(orbit, M.sphere(0.06), M.glow(Color(0.85, 0.65, 1.0), 5.0), Vector3(cos(a), 0.1 * sin(a * 2.0), sin(a)) * 1.0)
	k.spin(orbit, Vector3.UP, -90.0)
	var haze := M.particles(Color(0.55, 0.25, 0.85, 0.7), 30, 1.6, 0.35, 0.4, Vector3.DOWN, 40, Vector3(0, -0.3, 0), 0.6, false)
	haze.position = Vector3(0, 0.2, 0)
	body.add_child(haze)
	k.root.set_meta("height", 2.5)
	k.root.set_meta("radius", 0.8)
