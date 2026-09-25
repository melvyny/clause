extends RefCounted
## Porcelain Orrery :: procedural materials, meshes and particle helpers.
## Everything is generated at runtime (noise-based normal maps, radial glow
## sprites) so the prototype ships without any imported asset files.

const PORCELAIN_SHADER := preload("../shaders/po_porcelain.gdshader")
const OUTLINE_SHADER := preload("../shaders/po_outline.gdshader")

static var _outline_cache := {}
static var _glow_tex: Texture2D
static var _particle_mats := {}
static var _font: Font


## System font with CJK fallbacks (Windows / macOS / Linux) -- no bundled font file.
static func ui_font() -> Font:
	if _font:
		return _font
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "PingFang SC", "Hiragino Sans GB",
		"Noto Sans CJK SC", "Source Han Sans SC", "WenQuanYi Zen Hei", "Droid Sans Fallback", "sans-serif"])
	f.font_weight = 600
	_font = f
	return f


static func outline(thickness: float = 0.014) -> ShaderMaterial:
	if _outline_cache.has(thickness):
		return _outline_cache[thickness]
	var o := ShaderMaterial.new()
	o.shader = OUTLINE_SHADER
	o.set_shader_parameter("thickness", thickness)
	_outline_cache[thickness] = o
	return o


## Glazed porcelain with kintsugi seams (see po_porcelain.gdshader).
## `dip` is the mesh-local height the glaze reaches; `glaze_all` fully glazes.
static func porcelain(glaze: Color, dip: float = 0.0, core: Color = Color(1.0, 0.6, 0.25),
		glaze_all: float = 0.0, crack_scale: float = 3.2, outline_px: float = 0.014,
		body: Color = Color(0.95, 0.94, 0.9)) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = PORCELAIN_SHADER
	m.set_shader_parameter("porcelain", body)
	m.set_shader_parameter("glaze", glaze)
	m.set_shader_parameter("dip_level", dip)
	m.set_shader_parameter("glaze_all", glaze_all)
	m.set_shader_parameter("core_color", core)
	m.set_shader_parameter("crack_scale", crack_scale)
	m.set_shader_parameter("rim_color", core.lerp(Color(0.8, 0.85, 1.0), 0.5))
	if outline_px > 0.0:
		m.next_pass = outline(outline_px)
	return m


## Polished brass / gold metal.
static func brass(color: Color = Color(0.95, 0.72, 0.35), roughness: float = 0.28) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = 1.0
	m.roughness = roughness
	return m


## Unshaded glowing material (runes, crystals, eyes).
static func glow(color: Color, energy: float = 3.0, alpha: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(color.r, color.g, color.b, alpha)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	if alpha < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func glow_texture() -> Texture2D:
	if _glow_tex:
		return _glow_tex
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.6))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_glow_tex = t
	return t


## Additive soft-glow billboard material used by all particles.
static func particle_material(additive: bool = true) -> StandardMaterial3D:
	if _particle_mats.has(additive):
		return _particle_mats[additive]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = glow_texture()
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	_particle_mats[additive] = m
	return m


## Generic CPU particle emitter with a colour fade.
static func particles(color: Color, amount: int = 24, lifetime: float = 1.0, size: float = 0.2,
		velocity: float = 1.0, direction: Vector3 = Vector3.UP, spread: float = 30.0,
		gravity: Vector3 = Vector3.ZERO, emit_radius: float = 0.2, additive: bool = true) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	quad.material = particle_material(additive)
	p.mesh = quad
	p.amount = amount
	p.lifetime = lifetime
	p.direction = direction
	p.spread = spread
	p.gravity = gravity
	p.initial_velocity_min = velocity * 0.6
	p.initial_velocity_max = velocity
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = emit_radius
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color.r, color.g, color.b, 0.0))
	p.color_ramp = ramp
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1, 0.1))
	p.scale_amount_curve = curve
	return p


## Adds a mesh instance to `parent` in one line.
static func add_mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO,
		rot_deg: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func sphere(radius: float, radial: int = 24, rings: int = 12) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	s.radial_segments = radial
	s.rings = rings
	return s


static func capsule(radius: float, height: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = radius
	c.height = maxf(height, radius * 2.0)
	return c


static func cylinder(top: float, bottom: float, height: float, sides: int = 20) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = sides
	return c


static func torus(inner: float, outer: float, rings: int = 48) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = rings
	t.ring_segments = 12
	return t


static func prism(size: Vector3, left: float = 0.5) -> PrismMesh:
	var p := PrismMesh.new()
	p.size = size
	p.left_to_right = left
	return p
