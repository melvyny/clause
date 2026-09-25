extends RefCounted
## Goldmend :: signature moves for each Vessel Spirit.
## play() is awaited by the battle before damage lands, so every move ends on
## its impact frame; recoveries (a lid flying home, a ball bouncing back) run
## on afterwards without blocking. Moves animate the parts tagged by the model
## builder ("parts" meta). Returns false when a species/skill has no signature,
## and the battle falls back to the generic lunge / cast animations.

const M = preload("po_mat.gd")
const Data = preload("po_data.gd")


static func play(u: Node3D, sk: Dictionary, target: Vector3) -> bool:
	var parts: Dictionary = u.model.get_meta("parts", {})
	if parts.is_empty():
		return false
	var kind: String = sk.anim
	match u.species_id:
		"chickencup":
			if kind == "melee":
				await _chicken_peck(u, parts, target)
				return true
			if kind == "projectile":
				await _chicken_flap(u, parts)
				return true
			if kind == "ultimate":
				await _chicken_crow(u, parts)
				return true
		"rulotus":
			if kind == "projectile":
				await _bowl_pour(u, parts, target)
				return true
			if kind == "cast" or kind == "ultimate":
				await _bowl_spin(u, parts)
				return true
		"sancaihorse":
			if kind == "projectile":
				await _horse_stomp(u, parts)
				return true
			if kind == "cast":
				await _whirl(u, 2)
				return true
			if kind == "ultimate":
				await _horse_rear_charge(u, parts)
				return true
		"childpillow":
			if kind == "projectile":
				await _pillow_toss(u, parts, target)
				return true
			if kind == "cast" or kind == "ultimate":
				await _rock(u)
				return true
		"tigerpillow":
			if kind == "melee" or kind == "ultimate":
				await _tiger_pounce(u, parts, target, kind == "ultimate")
				return true
			if kind == "cast":
				await _tiger_roar(u, parts)
				return true
		"generaljar":
			if kind == "melee":
				await _lid_slam(u, parts, target)
				return true
			if kind == "cast":
				await _jar_formation(u, parts)
				return true
			if kind == "ultimate":
				await _lid_spin(u, parts)
				return true
		"phoenixvase":
			if kind == "melee" or kind == "ultimate":
				await _phoenix_dive(u, parts, target, kind == "ultimate")
				return true
		"yohenbowl":
			if kind == "projectile" or kind == "ultimate":
				await _bowl_tip(u, parts, kind == "ultimate")
				return true
			if kind == "cast":
				await _bowl_flip(u, parts)
				return true
	return false


# --- helpers -------------------------------------------------------------------------
static func _wait(u: Node, t: float) -> void:
	await u.get_tree().create_timer(t).timeout


## Arc the whole unit toward `target`, stopping `gap` short of it.
static func _leap(u: Node3D, target: Vector3, gap: float, height: float, time: float) -> void:
	var from: Vector3 = u.global_position
	var dir := target - from
	dir.y = 0
	var to := from + dir.normalized() * maxf(dir.length() - gap, 0.5)
	var t := u.create_tween()
	t.tween_method(func(w: float):
		u.global_position = from.lerp(to, w) + Vector3.UP * sin(w * PI) * height, 0.0, 1.0, time).set_trans(Tween.TRANS_SINE)
	await t.finished


## Moves a part to a world point along an arc and back (the return is not awaited).
static func _fling(u: Node3D, part: Node3D, to: Vector3, height: float, out_time: float, back_time: float, spin: float = 0.0) -> void:
	u.pause_bob(part, true)
	var home_local := part.position
	var from := part.global_position
	var t := u.create_tween()
	t.tween_method(func(w: float):
		if is_instance_valid(part):
			part.global_position = from.lerp(to, w) + Vector3.UP * sin(w * PI) * height
			part.rotation.y += spin * 0.05, 0.0, 1.0, out_time).set_trans(Tween.TRANS_SINE)
	await t.finished
	var back := u.create_tween()
	back.tween_interval(0.12)
	back.tween_property(part, "position", home_local, back_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	back.tween_callback(func():
		if is_instance_valid(u):
			u.pause_bob(part, false))


static func _burst(u: Node3D, pos: Vector3, color: Color, amount: int = 30, speed: float = 4.0) -> void:
	var p := M.particles(color, amount, 0.6, 0.22, speed, Vector3.UP, 180.0, Vector3(0, -4, 0), 0.2)
	p.one_shot = true
	p.explosiveness = 0.9
	u.get_parent().add_child(p)
	p.global_position = pos
	p.emitting = true
	u.get_tree().create_timer(1.2).timeout.connect(p.queue_free)


static func _dust_ring(u: Node3D, color: Color) -> void:
	var p := M.particles(color, 40, 0.7, 0.3, 3.5, Vector3.UP, 10.0, Vector3(0, -2, 0), 0.9)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = 1.0
	p.emission_ring_inner_radius = 0.8
	p.emission_ring_height = 0.05
	p.one_shot = true
	p.explosiveness = 0.95
	u.get_parent().add_child(p)
	p.global_position = u.global_position + Vector3(0, 0.1, 0)
	p.emitting = true
	u.get_tree().create_timer(1.2).timeout.connect(p.queue_free)


static func _whirl(u: Node3D, turns: int) -> void:
	var t := u.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(u.model, "rotation:y", u.model.rotation.y + TAU * turns, 0.35 * turns)
	t.tween_callback(func(): u.model.rotation.y = 0.0)
	await t.finished


static func _rock(u: Node3D) -> void:
	var t := u.create_tween().set_trans(Tween.TRANS_SINE)
	for i in 2:
		t.tween_property(u.model, "rotation_degrees:z", 14.0, 0.14)
		t.tween_property(u.model, "rotation_degrees:z", -14.0, 0.2)
	t.tween_property(u.model, "rotation_degrees:z", 0.0, 0.12)
	_burst(u, u.center_position() + Vector3.UP * 0.6, Color(1.0, 0.95, 0.7), 18, 1.5)
	await t.finished


# --- 鸡缸杯 -----------------------------------------------------------------------------
static func _chicken_peck(u: Node3D, parts: Dictionary, target: Vector3) -> void:
	await _leap(u, target, 1.4, 0.9, 0.3)
	var head: Node3D = parts.head
	for i in 3:
		var t := u.create_tween()
		t.tween_property(head, "rotation_degrees:x", -60.0, 0.05)
		t.tween_property(head, "rotation_degrees:x", 8.0, 0.07)
		await t.finished
	head.rotation_degrees.x = 0.0


static func _chicken_flap(u: Node3D, parts: Dictionary) -> void:
	var tail: Node3D = parts.tail
	var t := u.create_tween()
	t.tween_property(tail, "scale", Vector3.ONE * 1.4, 0.12)
	t.parallel().tween_property(u.model, "position:y", 0.4, 0.12)
	t.tween_property(tail, "scale", Vector3.ONE, 0.15)
	t.parallel().tween_property(u.model, "position:y", 0.0, 0.15)
	await t.finished


static func _chicken_crow(u: Node3D, parts: Dictionary) -> void:
	var head: Node3D = parts.head
	var tail: Node3D = parts.tail
	var t := u.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(head, "rotation_degrees:x", 45.0, 0.25)
	t.parallel().tween_property(tail, "scale", Vector3(1.6, 1.6, 1.6), 0.25)
	t.parallel().tween_property(u.model, "position:y", 0.8, 0.25)
	await t.finished
	_burst(u, head.global_position + Vector3.UP * 0.3, Color(1.0, 0.45, 0.15), 60, 6.0)
	await _wait(u, 0.35)
	var back := u.create_tween()
	back.tween_property(head, "rotation_degrees:x", 0.0, 0.2)
	back.parallel().tween_property(tail, "scale", Vector3.ONE, 0.2)
	back.parallel().tween_property(u.model, "position:y", 0.0, 0.2)


# --- 汝窑莲碗 -----------------------------------------------------------------------------
static func _bowl_pour(u: Node3D, parts: Dictionary, target: Vector3) -> void:
	var bowl: Node3D = parts.bowl
	var t := u.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(bowl, "rotation_degrees:x", -50.0, 0.22)
	await t.finished
	var water := M.particles(Color(0.45, 0.8, 1.0, 0.9), 50, 0.45, 0.25, 9.0, Vector3.ZERO, 6.0, Vector3(0, -6, 0), 0.15)
	water.one_shot = true
	water.explosiveness = 0.3
	u.get_parent().add_child(water)
	water.global_position = bowl.global_position + Vector3.UP * 0.6
	var dir := (target - water.global_position).normalized()
	water.direction = dir + Vector3.UP * 0.2
	water.emitting = true
	u.get_tree().create_timer(1.0).timeout.connect(water.queue_free)
	await _wait(u, 0.2)
	var back := u.create_tween()
	back.tween_property(bowl, "rotation_degrees:x", 0.0, 0.3)


static func _bowl_spin(u: Node3D, parts: Dictionary) -> void:
	var water: Node3D = parts.water
	var t := u.create_tween()
	t.tween_property(u.model, "rotation:y", TAU, 0.5).set_trans(Tween.TRANS_SINE)
	t.parallel().tween_property(water, "scale", Vector3(1.3, 1, 1.3), 0.25)
	t.tween_property(water, "scale", Vector3.ONE, 0.2)
	t.tween_callback(func(): u.model.rotation.y = 0.0)
	_burst(u, water.global_position + Vector3.UP * 0.2, Color(0.5, 0.85, 1.0), 40, 3.0)
	await t.finished


# --- 三彩马 -------------------------------------------------------------------------------
static func _horse_stomp(u: Node3D, parts: Dictionary) -> void:
	var body: Node3D = parts.body
	var t := u.create_tween().set_trans(Tween.TRANS_QUAD)
	t.tween_property(body, "rotation_degrees:x", 32.0, 0.22).set_ease(Tween.EASE_OUT)
	t.tween_property(body, "rotation_degrees:x", -6.0, 0.1).set_ease(Tween.EASE_IN)
	await t.finished
	_dust_ring(u, Color(0.9, 0.75, 0.4, 0.8))
	var back := u.create_tween()
	back.tween_property(body, "rotation_degrees:x", 0.0, 0.15)


static func _horse_rear_charge(u: Node3D, parts: Dictionary) -> void:
	await _horse_stomp(u, parts)
	await _whirl(u, 1)


# --- 孩儿枕 -------------------------------------------------------------------------------
static func _pillow_toss(u: Node3D, parts: Dictionary, target: Vector3) -> void:
	var head: Node3D = parts.head
	var nod := u.create_tween()
	nod.tween_property(head, "rotation_degrees:x", -20.0, 0.12)
	nod.tween_property(head, "rotation_degrees:x", 0.0, 0.15)
	await _fling(u, parts.ball, target + Vector3.UP * 1.0, 2.2, 0.45, 0.45, 6.0)


# --- 虎枕 ---------------------------------------------------------------------------------
static func _tiger_pounce(u: Node3D, parts: Dictionary, target: Vector3, big: bool) -> void:
	var s0: Vector3 = u.model.scale
	var crouch := u.create_tween()
	crouch.tween_property(u.model, "scale", s0 * Vector3(1.12, 0.78, 1.12), 0.16)
	await crouch.finished
	var stretch := u.create_tween()
	stretch.tween_property(u.model, "scale", s0 * Vector3(0.92, 1.12, 1.05), 0.1)
	await _leap(u, target, 1.5, 1.8 if big else 1.2, 0.32)
	var head: Node3D = parts.head
	var swipe := u.create_tween()
	swipe.tween_property(head, "rotation_degrees:z", 25.0, 0.06)
	swipe.tween_property(head, "rotation_degrees:z", -20.0, 0.08)
	swipe.tween_property(head, "rotation_degrees:z", 0.0, 0.1)
	swipe.parallel().tween_property(u.model, "scale", s0, 0.12)
	await swipe.finished


static func _tiger_roar(u: Node3D, parts: Dictionary) -> void:
	var head: Node3D = parts.head
	var t := u.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(head, "rotation_degrees:x", 25.0, 0.18)
	t.parallel().tween_property(head, "scale", Vector3.ONE * 1.25, 0.18)
	await t.finished
	_dust_ring(u, Color(1.0, 0.7, 0.3, 0.8))
	await _wait(u, 0.25)
	var back := u.create_tween()
	back.tween_property(head, "rotation_degrees:x", 0.0, 0.2)
	back.parallel().tween_property(head, "scale", Vector3.ONE, 0.2)


# --- 将军罐 -------------------------------------------------------------------------------
static func _lid_slam(u: Node3D, parts: Dictionary, target: Vector3) -> void:
	var lid: Node3D = parts.lid
	var jar: Node3D = parts.jar
	u.pause_bob(lid, true)
	var home_local := lid.position
	var lift := u.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	lift.tween_property(lid, "position:y", home_local.y + 1.0, 0.18)
	lift.parallel().tween_property(jar, "rotation_degrees:x", -12.0, 0.18)
	await lift.finished
	var from := lid.global_position
	var above := target + Vector3.UP * 2.6
	var fly := u.create_tween()
	fly.tween_method(func(w: float):
		lid.global_position = from.lerp(above, w) + Vector3.UP * sin(w * PI) * 0.8
		lid.rotation.y = w * TAU, 0.0, 1.0, 0.28).set_trans(Tween.TRANS_SINE)
	await fly.finished
	var slam := u.create_tween().set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	slam.tween_property(lid, "global_position", target + Vector3.UP * 1.1, 0.12)
	await slam.finished
	_burst(u, target + Vector3.UP * 0.9, Color(0.4, 0.6, 1.0), 40, 5.0)
	var back := u.create_tween()
	back.tween_interval(0.15)
	back.tween_property(lid, "position", home_local, 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	back.parallel().tween_property(lid, "rotation:y", 0.0, 0.35)
	back.parallel().tween_property(jar, "rotation_degrees:x", 0.0, 0.3)
	back.tween_callback(func():
		if is_instance_valid(u):
			u.pause_bob(lid, false))


static func _jar_formation(u: Node3D, parts: Dictionary) -> void:
	var shield: Node3D = parts.shield_arm
	var spear: Node3D = parts.spear_arm
	u.pause_bob(shield, true)
	u.pause_bob(spear, true)
	var t := u.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(shield, "rotation_degrees:z", 70.0, 0.22)
	t.parallel().tween_property(spear, "rotation_degrees:z", -70.0, 0.22)
	await t.finished
	_dust_ring(u, Color(0.4, 0.6, 1.0, 0.8))
	await _wait(u, 0.3)
	var back := u.create_tween()
	back.tween_property(shield, "rotation_degrees:z", 20.0, 0.25)
	back.parallel().tween_property(spear, "rotation_degrees:z", -20.0, 0.25)
	back.tween_callback(func():
		if is_instance_valid(u):
			u.pause_bob(shield, false)
			u.pause_bob(spear, false))


static func _lid_spin(u: Node3D, parts: Dictionary) -> void:
	var lid: Node3D = parts.lid
	u.pause_bob(lid, true)
	var home_local := lid.position
	var t := u.create_tween()
	t.tween_property(lid, "position:y", home_local.y + 1.6, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(lid, "rotation:y", TAU * 2.0, 0.6)
	t.tween_property(lid, "position:y", home_local.y, 0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	t.tween_callback(func():
		lid.rotation.y = 0.0
		u.pause_bob(lid, false))
	await t.finished
	_dust_ring(u, Color(0.4, 0.6, 1.0, 0.9))


# --- 凤耳瓶 -------------------------------------------------------------------------------
static func _phoenix_dive(u: Node3D, parts: Dictionary, target: Vector3, big: bool) -> void:
	var phs: Array = parts.phoenixes
	var tilt := u.create_tween()
	tilt.tween_property(parts.body, "rotation_degrees:x", -15.0, 0.15)
	for i in phs.size():
		var side := -1.0 if i == 0 else 1.0
		var ph: Node3D = phs[i]
		var aim := target + Vector3.UP * 1.0 + u.global_basis.x * side * 0.25
		# stagger: the second phoenix leaves a moment later
		if i == 1:
			await _wait(u, 0.08)
		_fling(u, ph, aim, 1.6 if big else 1.0, 0.3, 0.4, 0.0)
	await _wait(u, 0.32)
	_burst(u, target + Vector3.UP * 1.0, Color(0.55, 1.0, 0.7), 36, 4.0)
	var back := u.create_tween()
	back.tween_property(parts.body, "rotation_degrees:x", 0.0, 0.3)


# --- 曜变盏 -------------------------------------------------------------------------------
static func _bowl_tip(u: Node3D, parts: Dictionary, big: bool) -> void:
	var tilt: Node3D = parts.tilt
	var start := tilt.rotation_degrees.x
	var t := u.create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(tilt, "rotation_degrees:x", start - (45.0 if big else 30.0), 0.22)
	await t.finished
	_burst(u, tilt.global_position + Vector3.UP * 0.3, Color(0.7, 0.55, 1.0), 50 if big else 26, 3.5)
	await _wait(u, 0.1)
	var back := u.create_tween()
	back.tween_property(tilt, "rotation_degrees:x", start, 0.3)


static func _bowl_flip(u: Node3D, parts: Dictionary) -> void:
	var tilt: Node3D = parts.tilt
	var t := u.create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(tilt, "rotation:y", TAU, 0.55)
	t.tween_callback(func(): tilt.rotation.y = 0.0)
	_burst(u, tilt.global_position, Color(0.6, 0.4, 1.0), 40, 3.0)
	await t.finished
