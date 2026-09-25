extends RefCounted
## Goldmend :: Vessel Spirit models (器灵).
## Each figure is a real historical porcelain piece drawn as a cartoon. Vessel
## bodies are lathe-turned from a profile curve (like pottery thrown on a
## wheel), then given faces and limbs, and glazed with po_porcelain.gdshader
## using the matching real surface technique (doucai, Ru crackle, sancai, ...).
## Models face -Z. The returned root carries metadata used by the unit:
##   "spinners":  Array of [Node3D, Vector3 axis, float deg_per_sec]
##   "bobbers":   Array of [Node3D, float amplitude, float speed, float phase]
##   "porcelain": Array of ShaderMaterial (unit drives `damage` / `mended`)
##   "height", "radius", "muzzle"

const M = preload("po_mat.gd")
const Data = preload("po_data.gd")

## Plinth glaze per Five-Phase element (金木水火土), after the great kilns:
## Ding ivory with gilding, Longquan celadon, Ru sky-blue, Jun copper red,
## and the brown-black of a Jian / Cizhou stoneware body.
const GLAZES := [
	Color(0.93, 0.88, 0.74),
	Color(0.42, 0.62, 0.5),
	Color(0.52, 0.7, 0.74),
	Color(0.62, 0.12, 0.14),
	Color(0.36, 0.22, 0.14),
]
const WHITE := Color(0.96, 0.95, 0.91)
const IVORY := Color(0.94, 0.9, 0.78)


class Kit:
	var root: Node3D
	var glaze: Color
	var core: Color
	var enemy := false

	## Porcelain material. opts: glaze, glaze2, glaze3, pattern, pscale, dip, all, crack, body, gloss
	func mat(opts: Dictionary = {}) -> ShaderMaterial:
		var m := M.porcelain(opts.get("glaze", glaze), opts.get("dip", 0.0), core, opts.get("all", 0.0),
			opts.get("crack", 3.2), opts.get("outline", 0.014), opts.get("body", WHITE))
		m.set_shader_parameter("pattern", opts.get("pattern", 0))
		m.set_shader_parameter("glaze2", opts.get("glaze2", Color(0.2, 0.45, 0.2)))
		m.set_shader_parameter("glaze3", opts.get("glaze3", Color(0.85, 0.6, 0.2)))
		m.set_shader_parameter("pattern_scale", opts.get("pscale", 4.0))
		if opts.has("gloss"):
			m.set_shader_parameter("gloss", opts.gloss)
		root.get_meta("porcelain").append(m)
		return m

	## Legacy helper kept for the boss model.
	func p(dip: float = 0.0, glaze_all: float = 0.0, crack: float = 3.2, body: Color = WHITE) -> ShaderMaterial:
		return mat({"dip": dip, "all": glaze_all, "crack": crack, "body": body})

	func spin(n: Node3D, axis: Vector3, speed: float) -> void:
		root.get_meta("spinners").append([n, axis, speed])

	func bob(n: Node3D, amp: float, speed: float, phase: float = 0.0) -> void:
		root.get_meta("bobbers").append([n, amp, speed, phase])

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

	## Cartoon eyes: white, pupil and glint. `mood`: "open", "fierce", "sleepy", "happy".
	func eyes(parent: Node3D, pos: Vector3, spread: float, size: float, mood: String = "open") -> void:
		var white := M.glow(Color(0.98, 0.97, 0.94), 0.25)
		var pupil_col := Color(0.9, 0.12, 0.1) if enemy else Color(0.05, 0.04, 0.06)
		var pupil := M.glow(pupil_col, 2.5 if enemy else 0.0)
		var ink := M.glow(Color(0.05, 0.04, 0.06), 0.0)
		for side in [-1.0, 1.0]:
			var e := node(parent, pos + Vector3(side * spread, 0, 0))
			if mood == "sleepy" or mood == "happy":
				# closed, curved eyes: ^ ^ (happy) or - - (sleepy)
				var arc := M.add_mesh(e, M.torus(size * 0.75, size * 0.95, 20), ink, Vector3.ZERO, Vector3(90, 0, 0), Vector3(1, 1, 0.5))
				if mood == "sleepy":
					arc.scale = Vector3(1.0, 1.0, 0.25)
				continue
			M.add_mesh(e, M.sphere(size, 16, 8), white, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.15, 0.45))
			M.add_mesh(e, M.sphere(size * 0.55, 12, 6), pupil, Vector3(0, -size * 0.1, -size * 0.3), Vector3.ZERO, Vector3(1, 1.1, 0.5))
			M.add_mesh(e, M.sphere(size * 0.18, 8, 4), M.glow(Color.WHITE, 1.5), Vector3(size * 0.2, size * 0.2, -size * 0.45))
			if mood == "fierce":
				M.add_mesh(e, M.capsule(size * 0.14, size * 1.9), ink, Vector3(0, size * 1.05, -size * 0.2), Vector3(0, 0, 90 + side * 18))

	func blush(parent: Node3D, pos: Vector3, spread: float, size: float) -> void:
		for side in [-1.0, 1.0]:
			M.add_mesh(parent, M.sphere(size, 12, 6), M.glow(Color(1.0, 0.55, 0.55), 0.6, 0.55), pos + Vector3(side * spread, 0, 0), Vector3.ZERO, Vector3(1, 0.6, 0.3))


# --- Lathe (wheel-thrown) meshes -------------------------------------------------------------
## Revolves a profile (x = radius, y = height) around Y. `petals` scallops the
## rim like a lotus. Reverse the profile to get an inward-facing surface.
static func lathe(profile: PackedVector2Array, segments: int = 48, petals: int = 0, petal_amp: float = 0.0) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for i in profile.size() - 1:
		for j in segments:
			var a0 := TAU * j / segments
			var a1 := TAU * (j + 1) / segments
			var p00 := _rev(profile[i], a0, petals, petal_amp)
			var p01 := _rev(profile[i], a1, petals, petal_amp)
			var p10 := _rev(profile[i + 1], a0, petals, petal_amp)
			var p11 := _rev(profile[i + 1], a1, petals, petal_amp)
			for v in [p00, p11, p10, p00, p01, p11]:
				st.add_vertex(v)
	st.index()
	st.generate_normals()
	return st.commit()


static func _rev(p: Vector2, a: float, petals: int, amp: float) -> Vector3:
	var r := p.x * (1.0 + amp * cos(petals * a) if petals > 0 else 1.0)
	return Vector3(cos(a) * r, p.y, sin(a) * r)


## Outer + inner surfaces of an open vessel (bowl, cup). Returns [outer, inner].
static func vessel(outer: PackedVector2Array, wall: float, segments: int = 48, petals: int = 0, petal_amp: float = 0.0) -> Array:
	var inner := PackedVector2Array()
	for i in range(outer.size() - 1, 0, -1):
		var q := outer[i]
		inner.append(Vector2(maxf(q.x - wall, 0.0), q.y + (wall if i < 2 else 0.0)))
	inner.append(Vector2(0.0, outer[1].y + wall))
	var rim := PackedVector2Array([outer[outer.size() - 1], inner[0]])
	return [lathe(outer, segments, petals, petal_amp), lathe(inner, segments, petals, petal_amp), lathe(rim, segments, petals, petal_amp)]


static func pv(points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(Vector2(p[0], p[1]))
	return out


# --- Build entry -------------------------------------------------------------------------------
## Target model heights when normalising imported glTF creatures.
const GLTF_HEIGHT := {
	"chickencup": 2.0, "rulotus": 1.8, "sancaihorse": 2.1, "childpillow": 1.5,
	"tigerpillow": 1.7, "generaljar": 2.4, "phoenixvase": 2.4, "yohenbowl": 2.0,
}
## Animation name keywords (matched case-insensitively, first hit wins).
const ANIM_KEYS := {
	"idle": ["idle", "flying_idle", "stand", "survey"],
	"attack": ["attack", "bite", "punch", "headbutt", "slash", "sword", "weapon", "claw", "kick"],
	"cast": ["spell", "cast", "roar", "yell", "dance", "yes", "wave", "jump"],
	"hit": ["hitreact", "hit_react", "hitrecieve", "hitreceive", "hit", "damage", "hurt"],
	"death": ["death", "die", "dead"],
}


## Optional drop-in: `res://orrery/models/<species_id>.glb` (or .gltf) replaces
## the procedural model and is re-glazed with the porcelain shader.
static func model_path(species_id: String) -> String:
	for ext in ["glb", "gltf"]:
		var p := "res://orrery/models/%s.%s" % [species_id, ext]
		if ResourceLoader.exists(p):
			return p
	return ""


static func build(species_id: String, is_enemy: bool) -> Node3D:
	var k := Kit.new()
	k.root = Node3D.new()
	k.root.name = "Model"
	k.root.set_meta("spinners", [])
	k.root.set_meta("bobbers", [])
	k.root.set_meta("porcelain", [])
	var el: int = Data.species_info(species_id).element
	k.glaze = GLAZES[el]
	k.core = Data.ELEMENT_COLORS[el]
	k.enemy = is_enemy
	var gltf := model_path(species_id)
	if gltf != "":
		var scene = load(gltf)
		if scene is PackedScene:
			_from_gltf(k, scene, GLTF_HEIGHT.get(species_id, 2.0))
			return k.root
	match species_id:
		"chickencup":
			_chicken_cup(k)
		"rulotus":
			_ru_lotus(k)
		"sancaihorse":
			_sancai_horse(k)
		"childpillow":
			_child_pillow(k)
		"tigerpillow":
			_tiger_pillow(k)
		"generaljar":
			_general_jar(k)
		"phoenixvase":
			_phoenix_vase(k)
		"yohenbowl":
			_yohen_bowl(k)
		"boss":
			_boss(k)
	return k.root


# --- 鸡缸杯 Chicken Cup: a doucai rooster wearing its own cup ---------------------------------
static func _chicken_cup(k: Kit) -> void:
	var red := Color(0.86, 0.16, 0.1)
	var green := Color(0.2, 0.58, 0.32)
	var yellow := Color(0.98, 0.78, 0.2)
	var body := k.node(k.root, Vector3.ZERO)
	k.bob(body, 0.04, 3.2)
	# legs
	for side in [-1.0, 1.0]:
		M.add_mesh(body, M.cylinder(0.035, 0.045, 0.5), k.mat({"glaze": yellow, "all": 1.0}), Vector3(side * 0.15, 0.25, 0))
		M.add_mesh(body, M.prism(Vector3(0.22, 0.05, 0.2)), k.mat({"glaze": yellow, "all": 1.0}), Vector3(side * 0.15, 0.02, -0.05), Vector3(-90, 0, 0))
	# the cup (Chenghua "chicken cup" profile: small foot, gently flaring wall)
	var cup := k.node(body, Vector3(0, 0.45, 0))
	var cup_mat := k.mat({"pattern": 7, "glaze2": red, "glaze3": green, "pscale": 3.0, "dip": -1.0})
	var parts := vessel(pv([[0.0, 0.0], [0.24, 0.0], [0.27, 0.06], [0.3, 0.1], [0.55, 0.3], [0.72, 0.55], [0.8, 0.72]]), 0.04)
	M.add_mesh(cup, parts[0], cup_mat)
	M.add_mesh(cup, parts[1], k.mat({"dip": -1.0}))
	M.add_mesh(cup, parts[2], M.brass(Color(1.0, 0.78, 0.35), 0.25))
	# rooster rising out of the cup
	var bird := k.node(cup, Vector3(0, 0.45, 0))
	M.add_mesh(bird, M.sphere(0.46), k.mat({"pattern": 7, "glaze2": red, "glaze3": yellow, "pscale": 5.0, "dip": -1.0}), Vector3(0, 0.25, 0.05), Vector3.ZERO, Vector3(1.0, 0.95, 1.2))
	var head := k.node(bird, Vector3(0, 0.85, -0.3))
	k.bob(head, 0.05, 2.6, 0.5)
	M.add_mesh(head, M.sphere(0.27), k.mat({"dip": -1.0}), Vector3.ZERO)
	for i in 3:
		M.add_mesh(head, M.sphere(0.1 - i * 0.012), k.mat({"glaze": red, "all": 1.0}), Vector3(0, 0.26 + i * 0.03, 0.08 - i * 0.12))
	M.add_mesh(head, M.prism(Vector3(0.14, 0.2, 0.14)), k.mat({"glaze": yellow, "all": 1.0}), Vector3(0, -0.02, -0.3), Vector3(-90, 0, 0))
	M.add_mesh(head, M.sphere(0.07), k.mat({"glaze": red, "all": 1.0}), Vector3(0, -0.17, -0.2), Vector3.ZERO, Vector3(0.8, 1.3, 0.8))
	k.eyes(head, Vector3(0, 0.06, -0.2), 0.12, 0.07, "fierce")
	k.muzzle(head, Vector3(0, 0, -0.45))
	# enamel tail fan
	var tail := k.node(bird, Vector3(0, 0.4, 0.45), Vector3(-30, 0, 0))
	k.bob(tail, 0.05, 2.0, 1.0)
	var cols := [red, green, yellow, Color(0.2, 0.4, 0.85), red]
	for i in 5:
		var a := -50.0 + i * 25.0
		M.add_mesh(tail, M.prism(Vector3(0.18, 0.75, 0.05)), k.mat({"glaze": cols[i], "all": 1.0}), Vector3(sin(deg_to_rad(a)) * 0.2, 0.35, 0), Vector3(0, 0, -a))
	for side in [-1.0, 1.0]:
		M.add_mesh(bird, M.sphere(0.25, 16, 8), k.mat({"glaze": green, "all": 1.0}), Vector3(side * 0.4, 0.25, 0.1), Vector3(0, 0, side * 20), Vector3(0.35, 0.7, 1.1))
	var fire := M.particles(Color(1.0, 0.45, 0.15, 0.9), 22, 0.6, 0.22, 1.0, Vector3.UP, 20, Vector3(0, 1.4, 0), 0.08)
	fire.position = Vector3(0, 0.4, 0.0)
	head.add_child(fire)
	k.root.set_meta("parts", {"body": body, "bird": bird, "head": head, "tail": tail})
	k.root.set_meta("height", 2.2)
	k.root.set_meta("radius", 0.8)


# --- 汝窑莲碗 Ru Lotus Bowl: sky-blue crackled lotus bowl, full of water ------------------------
static func _ru_lotus(k: Kit) -> void:
	var sky := Color(0.6, 0.74, 0.78)
	var body := k.node(k.root, Vector3(0, 0.45, 0))
	k.bob(body, 0.12, 1.5)
	var glaze := k.mat({"glaze": sky, "all": 1.0, "pattern": 3, "pscale": 7.0, "body": sky, "crack": 2.6})
	var parts := vessel(pv([[0.0, 0.0], [0.26, 0.0], [0.3, 0.08], [0.33, 0.12], [0.6, 0.3], [0.82, 0.62], [0.9, 0.82]]), 0.05, 64, 10, 0.07)
	M.add_mesh(body, parts[0], glaze)
	M.add_mesh(body, parts[1], glaze)
	M.add_mesh(body, parts[2], glaze)
	var water := M.add_mesh(body, M.cylinder(0.76, 0.76, 0.02, 48), M.glow(Color(0.35, 0.75, 1.0), 1.2, 0.75), Vector3(0, 0.68, 0))
	k.bob(water, 0.02, 3.0)
	var ripple := M.add_mesh(body, M.torus(0.35, 0.4), M.glow(Color(0.7, 0.95, 1.0), 2.0, 0.7), Vector3(0, 0.7, 0))
	k.spin(ripple, Vector3.UP, 40.0)
	# a lotus bud floating in the water
	var bud := k.node(body, Vector3(0, 0.78, 0.05))
	for i in 6:
		var a := TAU * i / 6.0
		M.add_mesh(bud, M.sphere(0.13, 12, 6), k.mat({"glaze": Color(0.95, 0.72, 0.78), "all": 1.0}), Vector3(cos(a), 0.9, sin(a)) * 0.1, Vector3(0, rad_to_deg(-a), 25), Vector3(0.6, 1.3, 0.35))
	k.spin(bud, Vector3.UP, 20.0)
	k.eyes(body, Vector3(0, 0.42, -0.72), 0.2, 0.09, "happy")
	k.blush(body, Vector3(0, 0.33, -0.74), 0.34, 0.07)
	for side in [-1.0, 1.0]:
		var hand := k.node(body, Vector3(side * 0.88, 0.45, -0.1), Vector3(0, 0, side * -30))
		M.add_mesh(hand, M.sphere(0.2, 16, 8), k.mat({"glaze": Color(0.35, 0.6, 0.5), "all": 1.0}), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 0.25, 0.7))
		k.bob(hand, 0.06, 2.2, side)
	k.muzzle(body, Vector3(0, 0.8, -0.3))
	var drops := M.particles(Color(0.6, 0.9, 1.0, 0.9), 26, 1.6, 0.1, 0.6, Vector3.UP, 50, Vector3(0, -0.5, 0), 0.6)
	drops.position = Vector3(0, 0.8, 0)
	body.add_child(drops)
	k.root.set_meta("parts", {"bowl": body, "water": water})
	k.root.set_meta("height", 1.9)
	k.root.set_meta("radius", 0.95)


# --- 三彩马 Sancai Steed: Tang tri-colour horse with running glazes ------------------------------
static func _sancai_horse(k: Kit) -> void:
	var amber := Color(0.8, 0.5, 0.14)
	var green := Color(0.22, 0.5, 0.24)
	var cream := Color(0.95, 0.88, 0.7)
	var sancai := {"pattern": 2, "glaze": amber, "glaze2": green, "glaze3": cream, "body": cream, "dip": 0.3, "pscale": 3.0}
	var body := k.node(k.root, Vector3.ZERO)
	k.bob(body, 0.04, 2.8)
	M.add_mesh(body, M.capsule(0.36, 1.45), k.mat(sancai), Vector3(0, 1.05, 0.05), Vector3(90, 0, 0))
	# saddle with green cloth
	M.add_mesh(body, M.cylinder(0.38, 0.4, 0.08, 24), k.mat({"glaze": green, "all": 1.0}), Vector3(0, 1.37, 0.1), Vector3(0, 0, 0), Vector3(1, 1, 1.25))
	M.add_mesh(body, M.cylinder(0.26, 0.3, 0.14, 20), k.mat({"glaze": amber, "all": 1.0}), Vector3(0, 1.45, 0.1), Vector3.ZERO, Vector3(1, 1, 1.3))
	var neck := k.node(body, Vector3(0, 1.25, -0.55), Vector3(-35, 0, 0))
	M.add_mesh(neck, M.capsule(0.2, 0.8), k.mat(sancai), Vector3(0, 0.3, 0))
	for i in 5:
		M.add_mesh(neck, M.prism(Vector3(0.06, 0.18, 0.14)), k.mat({"glaze": green, "all": 1.0}), Vector3(0, 0.1 + i * 0.13, 0.17), Vector3(-20, 0, 0))
	# head points forward and a little down; its axis is local +Y
	var head := k.node(neck, Vector3(0, 0.72, -0.05), Vector3(-75, 0, 0))
	k.bob(head, 0.03, 2.0, 0.6)
	M.add_mesh(head, M.cylinder(0.12, 0.2, 0.62, 16), k.mat({"glaze": cream, "all": 1.0}), Vector3(0, 0.2, 0))
	M.add_mesh(head, M.sphere(0.14), k.mat({"glaze": cream, "all": 1.0}), Vector3(0, 0.5, 0))
	M.add_mesh(head, M.sphere(0.2), k.mat({"glaze": cream, "all": 1.0}), Vector3(0, -0.02, 0.04))
	for side in [-1.0, 1.0]:
		M.add_mesh(head, M.prism(Vector3(0.08, 0.2, 0.05)), k.mat({"glaze": amber, "all": 1.0}), Vector3(side * 0.1, -0.08, 0.2), Vector3(-90, 0, side * 15))
	# eyes live on the body so they face forward regardless of the head tilt
	k.eyes(body, Vector3(0, 1.98, -1.02), 0.16, 0.065, "open")
	k.muzzle(head, Vector3(0, 0.55, 0))
	for lp in [Vector3(-0.2, 0, -0.5), Vector3(0.2, 0, -0.5), Vector3(-0.2, 0, 0.55), Vector3(0.2, 0, 0.55)]:
		var leg := k.node(body, lp + Vector3(0, 0.95, 0))
		M.add_mesh(leg, M.cylinder(0.09, 0.07, 0.9), k.mat(sancai), Vector3(0, -0.47, 0))
		M.add_mesh(leg, M.cylinder(0.09, 0.1, 0.1), k.mat({"glaze": Color(0.2, 0.15, 0.1), "all": 1.0}), Vector3(0, -0.93, 0))
	var tail := k.node(body, Vector3(0, 1.1, 0.8), Vector3(40, 0, 0))
	k.bob(tail, 0.06, 3.0, 1.0)
	for i in 3:
		M.add_mesh(tail, M.prism(Vector3(0.12, 0.6, 0.05)), k.mat({"glaze": [amber, green, amber][i], "all": 1.0}), Vector3((i - 1) * 0.05, -0.3, 0), Vector3(0, 0, (i - 1) * 12))
	var dust := M.particles(Color(0.9, 0.8, 0.5, 0.7), 20, 1.0, 0.18, 1.2, Vector3.UP, 30, Vector3(0, 0.5, 0), 0.6, false)
	dust.position = Vector3(0, 0.1, 0.4)
	body.add_child(dust)
	k.root.set_meta("parts", {"body": body, "neck": neck, "head": head, "tail": tail})
	k.root.set_meta("height", 2.4)
	k.root.set_meta("radius", 0.85)


# --- 孩儿枕 Child Pillow: the sleepy Ding ware child lying on his tummy ---------------------------
static func _child_pillow(k: Kit) -> void:
	var ivory := {"glaze": IVORY, "all": 1.0, "body": IVORY, "pattern": 1, "glaze2": Color(0.98, 0.94, 0.84), "pscale": 2.0, "gloss": 0.2}
	var body := k.node(k.root, Vector3(0, 0.25, 0))
	k.bob(body, 0.07, 1.2)
	# the mat he lies on (the pillow base, incised with a lotus pattern)
	M.add_mesh(body, M.cylinder(0.72, 0.66, 0.24, 40), k.mat({"glaze": IVORY, "all": 1.0, "body": IVORY, "pattern": 4, "pscale": 5.0}), Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1.0, 1, 1.35))
	M.add_mesh(body, M.torus(0.66, 0.72, 48), M.brass(), Vector3(0, 0.24, 0), Vector3.ZERO, Vector3(1.0, 1, 1.35))
	# body lying prone, head toward the camera side of the model (-Z)
	M.add_mesh(body, M.capsule(0.3, 1.05), k.mat(ivory), Vector3(0, 0.52, 0.1), Vector3(90, 0, 0))
	var head := k.node(body, Vector3(0, 0.78, -0.6))
	k.bob(head, 0.03, 1.0)
	M.add_mesh(head, M.sphere(0.38), k.mat(ivory), Vector3.ZERO, Vector3.ZERO, Vector3(1.05, 0.95, 1.0))
	M.add_mesh(head, M.sphere(0.12), k.mat(ivory), Vector3(0, 0.36, 0.05))
	for side in [-1.0, 1.0]:
		M.add_mesh(head, M.sphere(0.1), k.mat(ivory), Vector3(side * 0.22, 0.28, 0.1))
	k.eyes(head, Vector3(0, 0.04, -0.34), 0.13, 0.07, "sleepy")
	k.blush(head, Vector3(0, -0.07, -0.33), 0.2, 0.07)
	M.add_mesh(head, M.torus(0.03, 0.05, 16), M.glow(Color(0.35, 0.15, 0.15), 0.0), Vector3(0, -0.14, -0.35), Vector3(90, 0, 0), Vector3(1, 1, 0.6))
	# arms folded under the chin, legs kicked up behind
	for side in [-1.0, 1.0]:
		M.add_mesh(body, M.capsule(0.1, 0.5), k.mat(ivory), Vector3(side * 0.2, 0.5, -0.55), Vector3(90, side * 30, 0))
		var leg := k.node(body, Vector3(side * 0.13, 0.55, 0.6), Vector3(-60 - side * 10, 0, side * 8))
		M.add_mesh(leg, M.capsule(0.11, 0.55), k.mat(ivory), Vector3(0, 0.25, 0))
		M.add_mesh(leg, M.sphere(0.12), k.mat(ivory), Vector3(0, 0.55, 0.02), Vector3.ZERO, Vector3(1, 0.8, 1.3))
		k.bob(leg, 0.04, 2.0, side * 1.5)
	# the embroidered ball he plays with
	var ball := k.node(body, Vector3(0.5, 0.45, -0.75))
	M.add_mesh(ball, M.sphere(0.13), k.mat({"glaze": Color(0.9, 0.3, 0.3), "all": 1.0}))
	M.add_mesh(ball, M.torus(0.12, 0.14), M.brass(), Vector3.ZERO, Vector3(90, 0, 0))
	k.spin(ball, Vector3.UP, 60.0)
	k.muzzle(head, Vector3(0, 0.2, -0.4))
	var z := M.particles(Color(1.0, 0.95, 0.7, 0.9), 10, 2.0, 0.12, 0.35, Vector3(0.3, 1, 0), 15, Vector3.ZERO, 0.1)
	z.position = Vector3(0.3, 0.4, 0)
	head.add_child(z)
	k.root.set_meta("parts", {"body": body, "head": head, "ball": ball})
	k.root.set_meta("height", 1.55)
	k.root.set_meta("radius", 0.85)


# --- 虎枕 Tiger Pillow: a grumpy Cizhou tiger with a landscape painted on its back -----------------
static func _tiger_pillow(k: Kit) -> void:
	var ochre := Color(0.86, 0.62, 0.26)
	var black := Color(0.08, 0.06, 0.05)
	var fur := {"glaze": ochre, "glaze2": black, "pattern": 5, "all": 1.0, "body": ochre, "crack": 2.5}
	var body := k.node(k.root, Vector3.ZERO)
	k.bob(body, 0.025, 1.4)
	# lying body: an ovoid turned on its side
	var torso := k.node(body, Vector3(0, 0.55, 0.1), Vector3(90, 0, 0))
	M.add_mesh(torso, lathe(pv([[0.0, -0.8], [0.3, -0.72], [0.48, -0.45], [0.55, 0.0], [0.5, 0.45], [0.32, 0.75], [0.0, 0.82]]), 40), k.mat(fur), Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 0.85))
	# the pillow top: white slip painted with a black landscape (Cizhou style)
	M.add_mesh(body, M.cylinder(0.46, 0.46, 0.06, 40), k.mat({"glaze": black, "pattern": 4, "pscale": 3.5, "body": Color(0.95, 0.92, 0.84)}), Vector3(0, 1.0, 0.1), Vector3(-6, 0, 0), Vector3(1.0, 1, 1.6))
	M.add_mesh(body, M.torus(0.44, 0.49, 48), k.mat({"glaze": black, "all": 1.0}), Vector3(0, 1.02, 0.1), Vector3(-6, 0, 0), Vector3(1.0, 1, 1.6))
	var head := k.node(body, Vector3(0, 0.72, -0.8))
	k.bob(head, 0.03, 1.2, 0.4)
	M.add_mesh(head, M.sphere(0.44), k.mat(fur), Vector3.ZERO, Vector3.ZERO, Vector3(1.1, 0.92, 0.95))
	M.add_mesh(head, M.sphere(0.2), k.mat({"glaze": Color(0.96, 0.92, 0.82), "all": 1.0}), Vector3(0, -0.12, -0.34), Vector3.ZERO, Vector3(1.3, 0.8, 0.8))
	M.add_mesh(head, M.sphere(0.07), k.mat({"glaze": black, "all": 1.0}), Vector3(0, -0.04, -0.5))
	for side in [-1.0, 1.0]:
		M.add_mesh(head, M.sphere(0.14, 16, 8), k.mat(fur), Vector3(side * 0.32, 0.34, 0.02), Vector3.ZERO, Vector3(1, 1, 0.5))
		for w in 2:
			M.add_mesh(head, M.capsule(0.008, 0.35), M.glow(black, 0.0), Vector3(side * 0.3, -0.12 - w * 0.05, -0.38), Vector3(0, 0, 90 + side * (8 - w * 10)))
	M.add_mesh(head, M.prism(Vector3(0.24, 0.1, 0.03)), M.glow(black, 0.0), Vector3(0, 0.3, -0.4), Vector3(0, 0, 180))
	k.eyes(head, Vector3(0, 0.1, -0.38), 0.16, 0.08, "fierce")
	k.muzzle(head, Vector3(0, 0, -0.55))
	for pp in [Vector3(-0.32, 0.12, -0.6), Vector3(0.32, 0.12, -0.6), Vector3(-0.35, 0.12, 0.6), Vector3(0.35, 0.12, 0.6)]:
		M.add_mesh(body, M.sphere(0.16), k.mat(fur), pp, Vector3.ZERO, Vector3(1, 0.7, 1.3))
	var tail := k.node(body, Vector3(0.1, 0.5, 0.95), Vector3(0, 30, 0))
	k.bob(tail, 0.05, 2.5)
	for i in 4:
		M.add_mesh(tail, M.sphere(0.08 - i * 0.008), k.mat(fur), Vector3(sin(i * 0.8) * 0.2, i * 0.08, i * 0.13))
	var embers := M.particles(Color(1.0, 0.6, 0.25, 0.8), 14, 1.2, 0.1, 0.8, Vector3.UP, 40, Vector3(0, 0.3, 0), 0.5)
	embers.position = Vector3(0, 0.8, 0)
	body.add_child(embers)
	k.root.set_meta("parts", {"body": body, "head": head, "tail": tail})
	k.root.set_meta("height", 1.45)
	k.root.set_meta("radius", 1.0)


# --- 将军罐 General Jar: blue-and-white armour, lid helmet, painted moustache --------------------
static func _general_jar(k: Kit) -> void:
	var cobalt := Color(0.07, 0.17, 0.58)
	var bw := {"glaze": cobalt, "pattern": 4, "pscale": 3.2, "body": WHITE, "crack": 2.8}
	var body := k.node(k.root, Vector3.ZERO)
	k.bob(body, 0.03, 1.3)
	for side in [-1.0, 1.0]:
		M.add_mesh(body, M.cylinder(0.12, 0.14, 0.35, 16), k.mat(bw), Vector3(side * 0.22, 0.18, 0))
	var jar := k.node(body, Vector3(0, 0.3, 0))
	M.add_mesh(jar, lathe(pv([[0.0, 0.0], [0.38, 0.0], [0.42, 0.08], [0.72, 0.5], [0.82, 0.85], [0.7, 1.25], [0.42, 1.45], [0.36, 1.55], [0.4, 1.6], [0.0, 1.6]]), 56), k.mat(bw))
	# helmet lid with a finial and a red tassel
	var lid := k.node(jar, Vector3(0, 1.6, 0))
	k.bob(lid, 0.02, 2.0)
	M.add_mesh(lid, lathe(pv([[0.0, 0.0], [0.48, 0.0], [0.5, 0.05], [0.44, 0.22], [0.25, 0.38], [0.0, 0.42]]), 48), k.mat(bw))
	M.add_mesh(lid, M.sphere(0.1), k.mat({"glaze": cobalt, "all": 1.0}), Vector3(0, 0.5, 0))
	var tassel := M.particles(Color(0.95, 0.2, 0.15, 0.95), 18, 0.8, 0.14, 0.6, Vector3.UP, 25, Vector3(0, -0.6, 0), 0.05, false)
	tassel.position = Vector3(0, 0.58, 0)
	lid.add_child(tassel)
	# stern face and moustache on the shoulder
	k.eyes(jar, Vector3(0, 1.12, -0.7), 0.2, 0.09, "fierce")
	for side in [-1.0, 1.0]:
		M.add_mesh(jar, M.capsule(0.035, 0.32), M.glow(Color(0.05, 0.04, 0.08), 0.0), Vector3(side * 0.12, 0.92, -0.78), Vector3(0, 0, side * 70))
	# arms: round shield (a plate) and a halberd
	var shield_arm := k.node(jar, Vector3(-0.85, 0.8, -0.2), Vector3(0, 0, 20))
	M.add_mesh(shield_arm, M.capsule(0.1, 0.45), k.mat(bw), Vector3(0, -0.15, 0))
	var shield := k.node(shield_arm, Vector3(-0.1, -0.2, -0.3), Vector3(80, -20, 0))
	M.add_mesh(shield, lathe(pv([[0.0, 0.0], [0.4, 0.02], [0.45, 0.08], [0.0, 0.05]]), 40), k.mat({"glaze": cobalt, "pattern": 4, "pscale": 6.0}))
	k.bob(shield_arm, 0.04, 1.3, 0.5)
	var spear_arm := k.node(jar, Vector3(0.85, 0.8, -0.1), Vector3(0, 0, -20))
	M.add_mesh(spear_arm, M.capsule(0.1, 0.45), k.mat(bw), Vector3(0, -0.15, 0))
	var halberd := k.node(spear_arm, Vector3(0.05, -0.35, -0.1))
	M.add_mesh(halberd, M.cylinder(0.025, 0.025, 2.0), M.brass(Color(0.4, 0.25, 0.15), 0.5), Vector3(0, 0.6, 0))
	M.add_mesh(halberd, M.prism(Vector3(0.12, 0.35, 0.03)), M.brass(Color(0.9, 0.9, 0.95), 0.2), Vector3(0, 1.75, 0))
	M.add_mesh(halberd, M.prism(Vector3(0.3, 0.18, 0.02), 0.0), M.brass(Color(0.9, 0.9, 0.95), 0.2), Vector3(0.12, 1.5, 0), Vector3(0, 0, -90))
	k.bob(spear_arm, 0.04, 1.3, 1.5)
	k.muzzle(jar, Vector3(0, 1.1, -0.8))
	k.root.set_meta("parts", {"body": body, "jar": jar, "lid": lid, "shield_arm": shield_arm, "spear_arm": spear_arm})
	k.root.set_meta("height", 2.45)
	k.root.set_meta("radius", 1.0)


# --- 凤耳瓶 Phoenix Vase: Longquan celadon vase whose phoenix handles fight for it ----------------
static func _phoenix_vase(k: Kit) -> void:
	var celadon := Color(0.48, 0.68, 0.56)
	var glaze := {"glaze": celadon, "all": 1.0, "body": celadon, "crack": 3.0, "gloss": 0.1}
	var body := k.node(k.root, Vector3(0, 0.35, 0))
	k.bob(body, 0.12, 1.6)
	k.spin(body, Vector3.UP, 0.0)
	M.add_mesh(body, lathe(pv([[0.0, 0.0], [0.34, 0.0], [0.38, 0.06], [0.44, 0.12], [0.47, 0.75], [0.4, 0.95], [0.2, 1.08], [0.15, 1.2], [0.14, 1.85], [0.2, 1.98], [0.26, 2.02], [0.0, 2.02]]), 48), k.mat(glaze))
	k.eyes(body, Vector3(0, 0.6, -0.46), 0.16, 0.08, "fierce")
	# the two phoenix handles
	var phs: Array = []
	for side in [-1.0, 1.0]:
		var ph := k.node(body, Vector3(side * 0.2, 1.55, 0), Vector3(0, 0, side * -10))
		phs.append(ph)
		k.bob(ph, 0.05, 2.4, side)
		M.add_mesh(ph, M.capsule(0.05, 0.4), k.mat(glaze), Vector3(side * 0.12, -0.05, 0), Vector3(0, 0, side * 50))
		var head := k.node(ph, Vector3(side * 0.28, 0.12, -0.05))
		M.add_mesh(head, M.sphere(0.11), k.mat(glaze), Vector3.ZERO)
		M.add_mesh(head, M.prism(Vector3(0.06, 0.16, 0.06)), k.mat({"glaze": Color(0.95, 0.8, 0.4), "all": 1.0}), Vector3(side * 0.12, -0.02, -0.03), Vector3(0, 0, side * 90))
		for c in 3:
			M.add_mesh(head, M.prism(Vector3(0.04, 0.14, 0.03)), k.mat(glaze), Vector3(side * (-0.03 - c * 0.04), 0.12, 0), Vector3(0, 0, side * (20 + c * 20)))
		for e in [-1.0, 1.0]:
			M.add_mesh(head, M.sphere(0.025), M.glow(Color(0.9, 0.15, 0.1) if k.enemy else Color(0.05, 0.04, 0.06), 1.0 if k.enemy else 0.0), Vector3(side * 0.06, 0.03, e * 0.08))
	k.muzzle(body, Vector3(0, 1.55, -0.3))
	var wind := M.particles(Color(0.6, 1.0, 0.75, 0.6), 30, 1.2, 0.16, 1.5, Vector3.UP, 12, Vector3.ZERO, 0.6)
	wind.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	wind.emission_ring_axis = Vector3.UP
	wind.emission_ring_radius = 0.7
	wind.emission_ring_inner_radius = 0.55
	wind.emission_ring_height = 0.05
	wind.tangential_accel_min = 3.0
	wind.tangential_accel_max = 5.0
	wind.position = Vector3(0, -0.2, 0)
	body.add_child(wind)
	k.root.set_meta("parts", {"body": body, "phoenixes": phs})
	k.root.set_meta("height", 2.5)
	k.root.set_meta("radius", 0.7)


# --- 曜变盏 Yohen Bowl: a Jian tea bowl holding a whole starry sky --------------------------------
static func _yohen_bowl(k: Kit) -> void:
	var black := Color(0.05, 0.035, 0.035)
	var body := k.node(k.root, Vector3(0, 0.55, 0))
	k.bob(body, 0.14, 1.1)
	var tilt := k.node(body, Vector3.ZERO, Vector3(-38, 0, 0))
	var parts := vessel(pv([[0.0, 0.0], [0.22, 0.0], [0.25, 0.12], [0.3, 0.16], [0.55, 0.35], [0.74, 0.62], [0.72, 0.7], [0.78, 0.78]]), 0.05)
	M.add_mesh(tilt, parts[0], k.mat({"glaze": black, "glaze2": Color(0.5, 0.28, 0.12), "pattern": 8, "all": 1.0, "body": Color(0.3, 0.2, 0.15), "gloss": 0.08}))
	M.add_mesh(tilt, parts[1], k.mat({"glaze": black, "glaze2": Color(0.15, 0.25, 0.7), "pattern": 6, "pscale": 7.0, "all": 1.0, "body": black, "gloss": 0.05}))
	M.add_mesh(tilt, parts[2], M.brass(Color(0.85, 0.65, 0.35), 0.3))
	# the eye at the bottom of the bowl
	var iris := M.add_mesh(tilt, M.sphere(0.2, 24, 12), M.glow(Color(0.55, 0.35, 1.0), 3.0), Vector3(0, 0.12, 0), Vector3.ZERO, Vector3(1, 0.35, 1))
	M.add_mesh(tilt, M.sphere(0.09, 16, 8), M.glow(Color(0.9, 0.1, 0.1) if k.enemy else Color(0.02, 0.01, 0.05), 2.0 if k.enemy else 0.0), Vector3(0, 0.17, 0), Vector3.ZERO, Vector3(1, 0.4, 1))
	k.bob(iris, 0.015, 3.0)
	var stars := M.particles(Color(0.7, 0.8, 1.0, 0.9), 30, 1.8, 0.09, 0.5, Vector3.UP, 25, Vector3.ZERO, 0.45)
	stars.position = Vector3(0, 0.3, 0)
	tilt.add_child(stars)
	var orbit := k.node(body, Vector3(0, 0.3, 0))
	for i in 5:
		var a := TAU * i / 5.0
		M.add_mesh(orbit, M.sphere(0.06), M.glow(Color(0.5 + 0.1 * i, 0.4, 1.0), 4.0), Vector3(cos(a), 0.1 * sin(a * 2.0), sin(a)) * 1.0)
	k.spin(orbit, Vector3.UP, -70.0)
	k.muzzle(body, Vector3(0, 0.6, -0.4))
	k.root.set_meta("parts", {"body": body, "tilt": tilt})
	k.root.set_meta("height", 1.9)
	k.root.set_meta("radius", 0.85)


# --- The Unmended King: a towering broken vase whose cracks bleed red ------------------
static func _boss(k: Kit) -> void:
	k.core = Color(1.0, 0.15, 0.1)
	var body := k.node(k.root, Vector3.ZERO)
	k.bob(body, 0.06, 0.8)
	var mats: Array = []
	var profile := [[0.55, 0.3], [0.8, 0.8], [0.95, 1.3], [0.85, 1.8], [0.55, 2.25], [0.4, 2.6], [0.5, 2.9]]
	for i in profile.size():
		var m := k.p(0.0, 1.0, 2.2, Color(0.1, 0.08, 0.1))
		mats.append(m)
		# gaps: some rings are chipped away on one side
		var seg := M.add_mesh(body, M.sphere(profile[i][0], 28, 10), m, Vector3(0, profile[i][1], 0), Vector3(0, i * 37, 0), Vector3(1, 0.55, 1))
		if i in [2, 4]:
			seg.scale = Vector3(1, 0.55, 0.8)
	# cobalt dragon band painted around the belly
	M.add_mesh(body, M.torus(0.93, 1.0, 64), M.porcelain(Color(0.07, 0.17, 0.55), 0.0, k.core, 1.0, 4.0, 0.0), Vector3(0, 1.3, 0))
	# the mouth: a glowing red throat
	M.add_mesh(body, M.torus(0.38, 0.55, 48), k.p(0.0, 1.0, 3.0, Color(0.1, 0.08, 0.1)), Vector3(0, 3.05, 0))
	M.add_mesh(body, M.cylinder(0.38, 0.38, 0.05, 32), M.glow(k.core, 6.0), Vector3(0, 3.02, 0))
	var throat := M.particles(Color(1.0, 0.25, 0.15, 0.9), 40, 1.2, 0.35, 1.5, Vector3.UP, 20, Vector3(0, 0.5, 0), 0.3)
	throat.position = Vector3(0, 3.1, 0)
	body.add_child(throat)
	k.eyes(body, Vector3(0, 2.3, -0.5), 0.2, 0.09)
	var heart := OmniLight3D.new()
	heart.light_color = k.core
	heart.light_energy = 2.5
	heart.omni_range = 5.0
	heart.position = Vector3(0, 1.5, -1.2)
	body.add_child(heart)
	# orbiting shards it refuses to put back
	var orbits: Array = []
	for ring_i in 2:
		var orbit := k.node(body, Vector3(0, 1.2 + ring_i * 1.1, 0), Vector3(15 - ring_i * 30, 0, 10))
		orbits.append(orbit)
		for i in 7:
			var a := TAU * i / 7.0
			var shard := M.add_mesh(orbit, M.prism(Vector3(0.35, 0.5, 0.06)), k.p(0.0, 1.0, 4.0, Color(0.1, 0.08, 0.1)),
				Vector3(cos(a), 0.15 * sin(a * 3.0), sin(a)) * (1.6 + ring_i * 0.3), Vector3(randf() * 60, rad_to_deg(-a), randf() * 60))
			k.bob(shard, 0.12, 1.5 + i * 0.2, i)
		k.spin(orbit, Vector3.UP, 30.0 * (1 if ring_i == 0 else -1))
	for m in k.root.get_meta("porcelain"):
		m.set_shader_parameter("gold", Color(0.75, 0.08, 0.05))
		m.set_shader_parameter("damage", 0.35)
	k.muzzle(body, Vector3(0, 3.0, -0.3))
	k.root.set_meta("parts", {"body": body, "orbits": orbits})
	k.root.set_meta("height", 3.3)
	k.root.set_meta("radius", 1.2)


# --- Imported glTF creatures ---------------------------------------------------------
static func _from_gltf(k: Kit, scene: PackedScene, target_height: float) -> void:
	var pivot := k.node(k.root, Vector3.ZERO, Vector3(0, 180, 0))  # glTF faces +Z, we face -Z
	var inst := scene.instantiate() as Node3D
	pivot.add_child(inst)
	var meshes: Array = []
	_collect(inst, meshes)
	# bounds in `inst` space
	var box := AABB()
	var first := true
	for mi in meshes:
		var xf := _relative_xform(mi, inst)
		var b: AABB = xf * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var s := target_height / maxf(box.size.y, 0.001)
	inst.scale = Vector3.ONE * s
	var c := box.get_center()
	inst.position = Vector3(-c.x * s, -box.position.y * s, -c.z * s)
	# re-glaze: dip each mesh up to ~45% of its own height
	for mi in meshes:
		var ab: AABB = mi.get_aabb()
		var dip := ab.position.y + ab.size.y * 0.45
		# ~3 kintsugi cells per metre, expressed in this mesh's local units
		var local_to_world := s * _xform_scale(mi, inst)
		var m := k.p(dip, 0.0, 3.0 * local_to_world)
		m.set_shader_parameter("drip", 0.12 / maxf(local_to_world, 0.0001))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var ap := _find_player(inst)
	if ap:
		var map := {}
		var names := ap.get_animation_list()
		for role in ANIM_KEYS:
			for key in ANIM_KEYS[role]:
				for n in names:
					if not map.has(role) and String(n).to_lower().contains(key):
						map[role] = n
		if not map.has("idle") and names.size() > 0:
			map["idle"] = names[0]
		if map.has("idle"):
			ap.get_animation(map["idle"]).loop_mode = Animation.LOOP_LINEAR
		k.root.set_meta("anim_player", ap)
		k.root.set_meta("anims", map)
	k.muzzle(k.root, Vector3(0, target_height * 0.7, -0.5))
	k.root.set_meta("height", target_height)
	k.root.set_meta("radius", clampf(maxf(box.size.x, box.size.z) * s * 0.45, 0.6, 1.3))
	var aura := M.particles(k.core, 20, 1.6, 0.14, 0.5, Vector3.UP, 60, Vector3(0, 0.2, 0), 0.7)
	aura.position = Vector3(0, target_height * 0.4, 0)
	k.root.add_child(aura)


static func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D and n.mesh:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


static func _relative_xform(n: Node3D, ancestor: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur and cur != ancestor:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _xform_scale(n: Node3D, ancestor: Node3D) -> float:
	return _relative_xform(n, ancestor).basis.get_scale().y


static func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_player(c)
		if r:
			return r
	return null
