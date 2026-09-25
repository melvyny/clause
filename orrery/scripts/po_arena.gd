extends Node3D
## Porcelain Orrery :: the battlefield.
## A kintsugi-marble dais floating inside a giant brass armillary sphere, with
## the five element planets orbiting it, drifting porcelain shards, and a
## nebula sky. Only creates nodes under itself; the WorldEnvironment is local
## to this scene and does not touch project rendering settings.

const M = preload("po_mat.gd")
const Data = preload("po_data.gd")
const SKY_SHADER := preload("../shaders/po_nebula_sky.gdshader")

var _spinners: Array = []   # [node, axis, deg/s]
var _planets: Array = []    # [pivot, planet_mesh_instance, element]
var _time := 0.0


func _ready() -> void:
	_environment()
	_dais()
	_armillary()
	_planets_ring()
	_drift()


func _process(delta: float) -> void:
	_time += delta
	for e in _spinners:
		e[0].rotate_object_local(e[1], deg_to_rad(e[2]) * delta)


## Makes the element planet pulse when a reaction involving it fires.
func pulse_element(element: int) -> void:
	for p in _planets:
		if p[2] == element:
			var mi: MeshInstance3D = p[1]
			var t := create_tween()
			t.tween_property(mi, "scale", Vector3.ONE * 1.8, 0.15).set_trans(Tween.TRANS_BACK)
			t.tween_property(mi, "scale", Vector3.ONE, 0.5)


func _environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = SKY_SHADER
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.3
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.fog_enabled = true
	env.fog_light_color = Color(0.2, 0.14, 0.35)
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.1
	env.adjustment_contrast = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.light_color = Color(1.0, 0.9, 0.8)
	key.light_energy = 1.25
	key.rotation_degrees = Vector3(-52, 35, 0)
	key.shadow_enabled = true
	key.directional_shadow_max_distance = 60.0
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.55, 0.45, 1.0)
	rim.light_energy = 0.7
	rim.rotation_degrees = Vector3(-20, 200, 0)
	add_child(rim)


func _dais() -> void:
	var marble := M.porcelain(Color(0.08, 0.09, 0.2), 0.0, Color(0.9, 0.7, 1.0), 1.0, 0.28, 0.0, Color(0.1, 0.1, 0.2))
	marble.set_shader_parameter("crack_width", 0.018)
	M.add_mesh(self, M.cylinder(12.0, 12.0, 0.8, 96), marble, Vector3(0, -0.4, 0))
	var under := M.porcelain(Color(0.08, 0.08, 0.17), 0.0, Color(0.9, 0.7, 1.0), 1.0, 0.5, 0.0, Color(0.1, 0.1, 0.2))
	M.add_mesh(self, M.cylinder(11.6, 1.2, 8.0, 48), under, Vector3(0, -4.8, 0))
	M.add_mesh(self, M.cylinder(1.2, 0.05, 3.0, 24), under, Vector3(0, -10.3, 0))
	var brass := M.brass()
	M.add_mesh(self, M.torus(11.85, 12.25, 128), brass, Vector3(0, 0.0, 0))
	for r in [3.0, 7.0, 10.4]:
		M.add_mesh(self, M.torus(r - 0.06, r + 0.06, 96), brass, Vector3(0, 0.01, 0))
	# engraved orbit lines and tick marks (glowing)
	var tick := M.glow(Color(1.0, 0.8, 0.45), 2.0)
	for i in 48:
		var a := TAU * i / 48.0
		var long := i % 4 == 0
		M.add_mesh(self, M.cylinder(0.03, 0.03, 0.02, 6), tick,
			Vector3(cos(a), 0.0, sin(a)) * (11.4 if long else 11.6) + Vector3(0, 0.02, 0), Vector3(90, rad_to_deg(-a) + 90, 0),
			Vector3(1, 12.0 if long else 6.0, 1))
	# central compass rose that slowly turns
	var rose := Node3D.new()
	rose.position = Vector3(0, 0.03, 0)
	add_child(rose)
	for i in 8:
		var a := TAU * i / 8.0
		var length := 2.6 if i % 2 == 0 else 1.6
		M.add_mesh(rose, M.prism(Vector3(0.5, length, 0.02)), M.glow(Color(0.95, 0.75, 0.45), 1.6 if i % 2 == 0 else 0.8),
			Vector3(cos(a), 0, sin(a)) * length * 0.5, Vector3(-90, rad_to_deg(-a) - 90, 0))
	M.add_mesh(rose, M.torus(0.5, 0.62), brass)
	_spinners.append([rose, Vector3.UP, 4.0])
	# team sigils
	for z in [4.6, -4.6]:
		var sig := Node3D.new()
		sig.position = Vector3(0, 0.02, z)
		add_child(sig)
		var col := Color(0.4, 0.8, 1.0) if z > 0 else Color(1.0, 0.35, 0.4)
		M.add_mesh(sig, M.torus(6.4, 6.5, 96), M.glow(col, 1.5, 0.7), Vector3.ZERO, Vector3.ZERO, Vector3(1, 1, 0.3))
	# brass lamp posts around the rim
	for i in 10:
		var a := TAU * (i + 0.5) / 10.0
		var post := Node3D.new()
		post.position = Vector3(cos(a), 0, sin(a)) * 11.3
		add_child(post)
		M.add_mesh(post, M.cylinder(0.08, 0.14, 2.4, 10), brass, Vector3(0, 1.2, 0))
		M.add_mesh(post, M.torus(0.2, 0.26), brass, Vector3(0, 2.5, 0))
		var el := i % 5
		M.add_mesh(post, M.sphere(0.2), M.glow(Data.ELEMENT_COLORS[el], 4.0), Vector3(0, 2.5, 0))
		var l := OmniLight3D.new()
		l.light_color = Data.ELEMENT_COLORS[el]
		l.light_energy = 0.9
		l.omni_range = 5.0
		l.position = Vector3(0, 2.5, 0)
		post.add_child(l)


func _armillary() -> void:
	var brass := M.brass(Color(0.85, 0.62, 0.3), 0.35)
	var rings := [[34.0, Vector3(70, 0, 20), 3.0], [37.0, Vector3(-60, 30, 0), -2.2], [40.0, Vector3(10, 0, 80), 1.5]]
	for r in rings:
		var pivot := Node3D.new()
		pivot.rotation_degrees = r[1]
		pivot.position = Vector3(0, -2, -6)
		add_child(pivot)
		M.add_mesh(pivot, M.torus(r[0] - 0.35, r[0] + 0.35, 160), brass)
		for i in 24:
			var a := TAU * i / 24.0
			M.add_mesh(pivot, M.sphere(0.5, 8, 4), M.glow(Color(1.0, 0.8, 0.45), 2.5), Vector3(cos(a), 0, sin(a)) * r[0])
		_spinners.append([pivot, Vector3.UP, r[2]])


func _planets_ring() -> void:
	var glazes := preload("po_monster_builder.gd").GLAZES
	for i in 5:
		var pivot := Node3D.new()
		pivot.rotation_degrees = Vector3(randf_range(-12, 12), TAU * i / 5.0 * 57.3, 0)
		add_child(pivot)
		var dist := 20.0 + i * 3.0
		var holder := Node3D.new()
		holder.position = Vector3(dist, 3.0 + i * 1.3, 0)
		pivot.add_child(holder)
		var mat := M.porcelain(glazes[i], 0.2, Data.ELEMENT_COLORS[i], 0.0, 1.2, 0.0)
		var planet := M.add_mesh(holder, M.sphere(1.2 + (i % 3) * 0.4, 32, 16), mat)
		M.add_mesh(holder, M.torus(2.1, 2.25, 64), M.glow(Data.ELEMENT_COLORS[i], 2.0, 0.8), Vector3.ZERO, Vector3(70, 0, 15))
		_spinners.append([pivot, Vector3.UP, 3.0 + i * 0.7])
		_spinners.append([holder, Vector3.UP, 20.0])
		_planets.append([pivot, planet, i])


func _drift() -> void:
	# porcelain shards drifting upward around the arena
	var shard := PrismMesh.new()
	shard.size = Vector3(0.25, 0.35, 0.04)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.94, 0.9)
	mat.roughness = 0.15
	shard.material = mat
	var p := CPUParticles3D.new()
	p.mesh = shard
	p.amount = 90
	p.lifetime = 14.0
	p.preprocess = 14.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(30, 2, 30)
	p.position = Vector3(0, -8, 0)
	p.direction = Vector3.UP
	p.spread = 10.0
	p.gravity = Vector3.ZERO
	p.initial_velocity_min = 0.8
	p.initial_velocity_max = 1.8
	p.angular_velocity_min = -60.0
	p.angular_velocity_max = 60.0
	p.particle_flag_rotate_y = true
	p.scale_amount_min = 0.5
	p.scale_amount_max = 2.0
	add_child(p)
	# gold dust motes
	var dust := M.particles(Color(1.0, 0.8, 0.45, 0.8), 120, 8.0, 0.12, 0.3, Vector3.UP, 180, Vector3.ZERO, 16.0)
	dust.preprocess = 8.0
	dust.position = Vector3(0, 3, 0)
	add_child(dust)
