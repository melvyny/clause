extends Camera3D
## Porcelain Orrery :: cinematic battle camera.
## Modes: slow orbital overview, over-the-shoulder skill selection, target
## focus for crits / ultimates, and victory orbit. Includes trauma shake.

enum Mode { OVERVIEW, MANUAL, ORBIT_POINT }

var mode := Mode.OVERVIEW
var target_pos := Vector3(0, 9, 15)
var look_target := Vector3(0, 1, 0)
var cur_look := Vector3(0, 1, 0)
var speed := 3.0
var trauma := 0.0
var _time := 0.0
var _orbit_center := Vector3.ZERO
var _orbit_radius := 6.0
var _orbit_height := 3.0


func _ready() -> void:
	fov = 50.0
	near = 0.1
	far = 600.0
	global_position = Vector3(0, 30, 40)
	cur_look = look_target


func _process(delta: float) -> void:
	_time += delta
	match mode:
		Mode.OVERVIEW:
			var a := 0.22 * sin(_time * 0.12)
			target_pos = Vector3(sin(a) * 16.5, 9.5, cos(a) * 16.5)
			look_target = Vector3(0, 0.6, -0.5)
		Mode.ORBIT_POINT:
			var a2 := _time * 0.35
			target_pos = _orbit_center + Vector3(sin(a2) * _orbit_radius, _orbit_height, cos(a2) * _orbit_radius)
			look_target = _orbit_center + Vector3(0, 1.0, 0)
	var w := 1.0 - exp(-speed * delta)
	global_position = global_position.lerp(target_pos, w)
	cur_look = cur_look.lerp(look_target, w)
	if global_position.distance_to(cur_look) > 0.01:
		look_at(cur_look, Vector3.UP)
	trauma = maxf(trauma - delta * 1.6, 0.0)
	var t2 := trauma * trauma
	h_offset = (randf() * 2.0 - 1.0) * 0.35 * t2
	v_offset = (randf() * 2.0 - 1.0) * 0.35 * t2


func overview(p_speed: float = 2.5) -> void:
	mode = Mode.OVERVIEW
	speed = p_speed


func shake(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


func set_view(pos: Vector3, look: Vector3, p_speed: float = 3.0, snap: bool = false) -> void:
	mode = Mode.MANUAL
	target_pos = pos
	look_target = look
	speed = p_speed
	if snap:
		global_position = pos
		cur_look = look


## Behind and above the caster, looking at the opposing side.
func over_shoulder(caster_pos: Vector3, focus: Vector3) -> void:
	var dir := caster_pos - focus
	dir.y = 0
	dir = dir.normalized()
	var right := dir.cross(Vector3.UP).normalized()
	set_view(caster_pos + dir * 7.5 + Vector3.UP * 5.0 - right * caster_pos.x * 0.35, focus.lerp(caster_pos, 0.3) + Vector3.UP * 0.6, 3.2)


## Dramatic close-up on a point (ultimate caster or crit target).
func focus_on(point: Vector3, from_dir: Vector3, dist: float = 4.5, height: float = 1.6, p_speed: float = 6.0) -> void:
	var d := from_dir
	d.y = 0
	if d.length() < 0.01:
		d = Vector3.BACK
	d = d.normalized()
	var side := d.cross(Vector3.UP).normalized() * 1.2
	set_view(point + d * dist + Vector3.UP * height + side, point + Vector3.UP * 0.9, p_speed)


func orbit_point(center: Vector3, radius: float = 8.0, height: float = 3.5) -> void:
	mode = Mode.ORBIT_POINT
	_orbit_center = center
	_orbit_radius = radius
	_orbit_height = height
	speed = 1.8
