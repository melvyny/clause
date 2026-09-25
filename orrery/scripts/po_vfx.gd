extends Node3D
## Porcelain Orrery :: combat VFX -- bursts, projectiles, rings, pillars and
## floating combat text. All effects free themselves when finished.

const M = preload("po_mat.gd")


func _auto_free(node: Node, after: float) -> void:
	get_tree().create_timer(after).timeout.connect(func():
		if is_instance_valid(node):
			node.queue_free())


func burst(pos: Vector3, color: Color, amount: int = 40, speed: float = 6.0, size: float = 0.3,
		lifetime: float = 0.6, gravity: float = -6.0) -> void:
	var p := M.particles(color, amount, lifetime, size, speed, Vector3.UP, 180.0, Vector3(0, gravity, 0), 0.15)
	p.one_shot = true
	p.explosiveness = 0.95
	p.damping_min = 2.0
	p.damping_max = 4.0
	add_child(p)
	p.global_position = pos
	p.emitting = true
	_auto_free(p, lifetime + 0.5)


func sparks(pos: Vector3, color: Color) -> void:
	burst(pos, color, 30, 7.0, 0.18, 0.45, -9.0)
	burst(pos, Color(1, 1, 1, 0.9), 8, 3.0, 0.6, 0.18, 0.0)


func heal_fx(pos: Vector3) -> void:
	var p := M.particles(Color(0.4, 1.0, 0.5, 0.9), 30, 1.0, 0.22, 2.2, Vector3.UP, 15, Vector3.ZERO, 0.6)
	p.one_shot = true
	p.explosiveness = 0.3
	add_child(p)
	p.global_position = pos
	p.emitting = true
	_auto_free(p, 1.6)
	ring(pos, Color(0.4, 1.0, 0.5), 1.4, 0.6)


func buff_fx(pos: Vector3, color: Color) -> void:
	var p := M.particles(color, 18, 0.8, 0.25, 3.0, Vector3.UP, 8, Vector3.ZERO, 0.5)
	p.one_shot = true
	p.explosiveness = 0.5
	add_child(p)
	p.global_position = pos
	p.emitting = true
	_auto_free(p, 1.4)


func ring(pos: Vector3, color: Color, radius: float = 2.0, duration: float = 0.5) -> void:
	var mat := M.glow(color, 4.0, 0.9)
	var mi := M.add_mesh(self, M.torus(0.85, 1.0), mat)
	mi.global_position = pos + Vector3(0, 0.08, 0)
	mi.scale = Vector3(0.2, 1.0, 0.2)
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(mi, "scale", Vector3(radius, 1.0, radius), duration)
	t.parallel().tween_property(mat, "albedo_color:a", 0.0, duration)
	t.tween_callback(mi.queue_free)


func pillar(pos: Vector3, color: Color, height: float = 12.0, duration: float = 0.8) -> void:
	var mat := M.glow(color, 5.0, 0.7)
	var mi := M.add_mesh(self, M.cylinder(0.8, 0.8, height, 24), mat)
	mi.global_position = pos + Vector3(0, height * 0.5, 0)
	mi.scale = Vector3(0.05, 1, 0.05)
	var t := create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	t.tween_property(mi, "scale", Vector3(1.2, 1, 1.2), duration * 0.35)
	t.tween_property(mi, "scale", Vector3(0.01, 1, 0.01), duration * 0.65).set_ease(Tween.EASE_IN)
	t.parallel().tween_property(mat, "albedo_color:a", 0.0, duration * 0.65)
	t.tween_callback(mi.queue_free)
	flash(pos + Vector3(0, 2, 0), color, 10.0, duration)


func flash(pos: Vector3, color: Color, energy: float = 6.0, duration: float = 0.35) -> void:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = 9.0
	add_child(l)
	l.global_position = pos
	var t := create_tween()
	t.tween_property(l, "light_energy", 0.0, duration)
	t.tween_callback(l.queue_free)


func shockwave(pos: Vector3, color: Color) -> void:
	var mat := M.glow(color, 3.0, 0.6)
	var mi := M.add_mesh(self, M.sphere(1.0, 24, 12), mat)
	mi.global_position = pos
	mi.scale = Vector3.ONE * 0.2
	var t := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_property(mi, "scale", Vector3.ONE * 3.5, 0.45)
	t.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.45)
	t.tween_callback(mi.queue_free)


## Awaitable: flies a glowing orb with a particle trail from `from` to `to`.
func projectile(from: Vector3, to: Vector3, color: Color, duration: float = 0.35) -> void:
	var orb := Node3D.new()
	add_child(orb)
	orb.global_position = from
	M.add_mesh(orb, M.sphere(0.22), M.glow(color, 6.0))
	M.add_mesh(orb, M.sphere(0.4), M.glow(color, 2.0, 0.35))
	var trail := M.particles(color, 40, 0.35, 0.35, 0.3, Vector3.UP, 180, Vector3.ZERO, 0.12)
	trail.local_coords = false
	orb.add_child(trail)
	trail.emitting = true
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 2.0
	light.omni_range = 3.0
	orb.add_child(light)
	var mid := (from + to) * 0.5 + Vector3(0, 1.4, 0)
	var t := create_tween()
	t.tween_method(_move_orb.bind(orb, from, mid, to), 0.0, 1.0, duration)
	await t.finished
	trail.emitting = false
	for c in orb.get_children():
		if c is MeshInstance3D:
			c.visible = false
	light.visible = false
	_auto_free(orb, 0.5)


func _move_orb(w: float, orb: Node3D, from: Vector3, mid: Vector3, to: Vector3) -> void:
	if is_instance_valid(orb):
		orb.global_position = from.lerp(mid, w).lerp(mid.lerp(to, w), w)


## Floating combat text rising from `pos`.
func text(pos: Vector3, msg: String, color: Color, size: int = 64, rise: float = 1.4, duration: float = 1.1) -> void:
	var l := Label3D.new()
	l.font = M.ui_font()
	l.text = msg
	l.modulate = color
	l.outline_modulate = Color(0.05, 0.03, 0.02, 0.95)
	l.outline_size = 14
	l.font_size = size
	l.pixel_size = 0.006
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 10
	l.outline_render_priority = 9
	add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.2, 0.2))
	l.scale = Vector3.ONE * 0.4
	var t := create_tween()
	t.tween_property(l, "scale", Vector3.ONE * 1.15, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(l, "scale", Vector3.ONE, 0.08)
	t.parallel().tween_property(l, "global_position:y", l.global_position.y + rise, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(l, "modulate:a", 0.0, duration * 0.5).set_delay(duration * 0.5)
	t.parallel().tween_property(l, "outline_modulate:a", 0.0, duration * 0.5).set_delay(duration * 0.5)
	t.tween_callback(l.queue_free)
