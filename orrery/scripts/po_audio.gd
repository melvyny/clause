extends Node
## Porcelain Orrery :: procedural synth SFX (ceramic clinks, glassy bells).
## All sounds are synthesised into AudioStreamWAV buffers at startup -- no
## audio files, no bus changes (plays on the default Master bus).

const RATE := 22050

var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var muted := false


func _ready() -> void:
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_build_all()


func play(sfx: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if muted or not _streams.has(sfx):
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sfx]
	p.volume_db = volume_db - 4.0
	p.pitch_scale = pitch * randf_range(0.96, 1.04)
	p.play()


func element_sfx(element: int) -> String:
	return ["fire", "water", "wind", "light", "dark"][element]


# --- Synthesis ---------------------------------------------------------------------
func _to_stream(s: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	return w


func _buf(dur: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(dur * RATE))
	return s


static func _env(t: float, attack: float, decay: float) -> float:
	if t < attack:
		return t / attack
	return exp(-(t - attack) * decay)


## Adds a sine/square/saw sweep f0->f1 into buffer `s` starting at `start`.
func _tone(s: PackedFloat32Array, start: float, dur: float, f0: float, f1: float, amp: float,
		decay: float, wave: String = "sine", attack: float = 0.005) -> void:
	var n := int(dur * RATE)
	var off := int(start * RATE)
	var phase := 0.0
	for i in n:
		if off + i >= s.size():
			break
		var t := float(i) / RATE
		var f := lerpf(f0, f1, t / dur)
		phase += f / RATE
		var x := 0.0
		match wave:
			"sine":
				x = sin(TAU * phase)
			"square":
				x = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
				x *= 0.5
			"saw":
				x = (fmod(phase, 1.0) * 2.0 - 1.0) * 0.6
		s[off + i] += x * amp * _env(t, attack, decay)


## Low-passed noise; cutoff sweeps c0->c1 (Hz).
func _noise(s: PackedFloat32Array, start: float, dur: float, c0: float, c1: float, amp: float,
		decay: float, attack: float = 0.003) -> void:
	var n := int(dur * RATE)
	var off := int(start * RATE)
	var y := 0.0
	for i in n:
		if off + i >= s.size():
			break
		var t := float(i) / RATE
		var fc := lerpf(c0, c1, t / dur)
		var a := 1.0 - exp(-TAU * fc / RATE)
		y += a * (randf_range(-1.0, 1.0) - y)
		s[off + i] += y * amp * _env(t, attack, decay)


func _build_all() -> void:
	var s: PackedFloat32Array

	s = _buf(0.3)
	_tone(s, 0, 0.3, 160, 45, 0.9, 14)
	_noise(s, 0, 0.12, 5000, 800, 0.6, 30)
	_tone(s, 0, 0.3, 2350, 2340, 0.16, 16)
	_tone(s, 0, 0.3, 3710, 3700, 0.1, 20)
	_streams["hit"] = _to_stream(s)

	s = _buf(0.55)
	_tone(s, 0, 0.5, 220, 35, 1.0, 8)
	_noise(s, 0, 0.25, 9000, 1500, 0.9, 16)
	_tone(s, 0.0, 0.2, 1800, 900, 0.2, 20, "square")
	_tone(s, 0.0, 0.5, 2900, 2880, 0.22, 8)
	_tone(s, 0.02, 0.5, 4350, 4330, 0.14, 10)
	_streams["crit"] = _to_stream(s)

	s = _buf(0.6)
	_noise(s, 0, 0.6, 600, 4500, 0.9, 5, 0.05)
	_tone(s, 0, 0.5, 90, 60, 0.5, 6, "saw")
	_streams["fire"] = _to_stream(s)

	s = _buf(0.55)
	for k in 5:
		_tone(s, k * 0.08, 0.14, 380 + k * 90, 900 + k * 120, 0.45, 18)
	_noise(s, 0, 0.5, 1200, 300, 0.3, 6)
	_streams["water"] = _to_stream(s)

	s = _buf(0.7)
	_noise(s, 0, 0.7, 300, 2500, 0.9, 3.5, 0.2)
	_noise(s, 0.1, 0.5, 2500, 400, 0.4, 5, 0.1)
	_streams["wind"] = _to_stream(s)

	s = _buf(0.9)
	for f in [880.0, 1320.0, 1760.0, 2637.0]:
		_tone(s, 0, 0.9, f, f, 0.22, 4)
	_streams["light"] = _to_stream(s)

	s = _buf(0.7)
	_tone(s, 0, 0.7, 70, 55, 0.6, 3.5, "saw", 0.05)
	_tone(s, 0, 0.7, 73.5, 52, 0.6, 3.5, "saw", 0.05)
	_noise(s, 0, 0.6, 400, 150, 0.4, 4, 0.05)
	_streams["dark"] = _to_stream(s)

	s = _buf(0.3)
	_tone(s, 0, 0.12, 660, 660, 0.35, 18)
	_tone(s, 0.1, 0.2, 990, 990, 0.35, 14)
	_streams["turn"] = _to_stream(s)

	s = _buf(0.7)
	var notes := [523.25, 659.25, 783.99, 1046.5]
	for k in notes.size():
		_tone(s, k * 0.08, 0.4, notes[k], notes[k], 0.3, 7)
	_streams["heal"] = _to_stream(s)

	s = _buf(0.35)
	_tone(s, 0, 0.35, 300, 1000, 0.45, 6)
	_tone(s, 0, 0.35, 450, 1500, 0.2, 6)
	_streams["buff"] = _to_stream(s)

	s = _buf(0.35)
	_tone(s, 0, 0.35, 600, 180, 0.35, 6, "square")
	_streams["debuff"] = _to_stream(s)

	s = _buf(0.06)
	_tone(s, 0, 0.06, 1400, 1100, 0.35, 60)
	_streams["ui"] = _to_stream(s)

	s = _buf(1.4)
	_tone(s, 0, 1.4, 90, 28, 1.0, 2.5)
	_noise(s, 0, 1.0, 6000, 300, 0.8, 3.5)
	_tone(s, 0.15, 1.1, 400, 2400, 0.18, 2.5)
	_streams["ultimate"] = _to_stream(s)

	s = _buf(0.7)
	_tone(s, 0, 0.7, 320, 60, 0.6, 4, "saw")
	_noise(s, 0, 0.5, 2000, 200, 0.4, 5)
	_streams["death"] = _to_stream(s)

	s = _buf(0.35)
	_noise(s, 0, 0.35, 2500, 5000, 0.35, 10, 0.03)
	_streams["miss"] = _to_stream(s)

	# --- signature-move sounds ---
	s = _buf(0.08)
	_tone(s, 0, 0.08, 2600, 1800, 0.35, 50)
	_noise(s, 0, 0.04, 8000, 3000, 0.3, 80)
	_streams["peck"] = _to_stream(s)

	s = _buf(0.6)
	_noise(s, 0, 0.6, 1800, 600, 0.6, 5, 0.03)
	for k in 6:
		_tone(s, 0.05 + k * 0.06, 0.12, 500 + randf() * 600, 900 + randf() * 900, 0.18, 22)
	_streams["splash"] = _to_stream(s)

	s = _buf(0.45)
	_tone(s, 0, 0.45, 110, 38, 1.0, 7)
	_noise(s, 0, 0.2, 900, 150, 0.6, 14)
	_streams["stomp"] = _to_stream(s)

	s = _buf(0.4)
	_noise(s, 0, 0.4, 600, 4000, 0.55, 6, 0.12)
	_streams["whoosh"] = _to_stream(s)

	s = _buf(0.8)
	_tone(s, 0, 0.8, 140, 70, 0.6, 3.5, "saw", 0.05)
	_tone(s, 0, 0.8, 147, 72, 0.5, 3.5, "saw", 0.05)
	_noise(s, 0, 0.7, 1200, 300, 0.55, 3.5, 0.06)
	_streams["roar"] = _to_stream(s)

	# ceramic lid clank: inharmonic partials of a thick porcelain body
	s = _buf(0.7)
	for f in [620.0, 1045.0, 1690.0, 2480.0]:
		_tone(s, 0, 0.7, f, f * 0.998, 0.22, 6.5)
	_tone(s, 0, 0.3, 90, 50, 0.7, 12)
	_noise(s, 0, 0.08, 7000, 2000, 0.5, 40)
	_streams["clang"] = _to_stream(s)

	s = _buf(0.35)
	_tone(s, 0, 0.35, 2800, 1500, 0.3, 7, "square")
	_tone(s, 0.02, 0.3, 3400, 2100, 0.15, 8)
	_streams["screech"] = _to_stream(s)

	s = _buf(0.9)
	for i in 10:
		var f := randf_range(1800.0, 4200.0)
		_tone(s, i * 0.06, 0.4, f, f, 0.12, 9)
	_streams["twinkle"] = _to_stream(s)

	s = _buf(0.9)
	_tone(s, 0, 0.18, 700, 1300, 0.35, 1.5, "saw")
	_tone(s, 0.16, 0.6, 1300, 900, 0.35, 3.0, "saw")
	_tone(s, 0.16, 0.6, 1950, 1350, 0.12, 3.0)
	_streams["crow"] = _to_stream(s)

	s = _buf(0.3)
	_tone(s, 0, 0.3, 1100, 1100, 0.18, 12)
	_tone(s, 0, 0.3, 1650, 1650, 0.12, 12)
	_streams["pop"] = _to_stream(s)

	# porcelain shattering: a cascade of tiny ceramic clinks
	s = _buf(1.1)
	_noise(s, 0, 0.3, 9000, 2000, 0.6, 12)
	for i in 22:
		var f := randf_range(2200.0, 6200.0)
		_tone(s, randf_range(0.0, 0.7), 0.3, f, f * 0.995, randf_range(0.08, 0.2), randf_range(14.0, 30.0))
	_streams["shatter"] = _to_stream(s)

	# Element Fission reaction: bright bell cluster over a sub drop
	s = _buf(1.2)
	_tone(s, 0, 1.0, 110, 40, 0.7, 3.5)
	for f in [784.0, 1175.0, 1568.0, 2349.0]:
		_tone(s, 0.03, 1.1, f, f, 0.18, 3.5)
		_tone(s, 0.03, 1.1, f * 1.005, f * 1.005, 0.12, 3.5)
	_noise(s, 0, 0.4, 7000, 1500, 0.4, 8)
	_streams["reaction"] = _to_stream(s)

	s = _buf(1.6)
	var up := [523.25, 659.25, 783.99, 1046.5, 1318.5]
	for k in up.size():
		_tone(s, k * 0.12, 0.9, up[k], up[k], 0.28, 3.0, "square")
		_tone(s, k * 0.12, 0.9, up[k] * 0.5, up[k] * 0.5, 0.2, 3.0)
	_streams["victory"] = _to_stream(s)

	s = _buf(1.6)
	var down := [392.0, 329.6, 261.6, 196.0]
	for k in down.size():
		_tone(s, k * 0.25, 0.6, down[k], down[k] * 0.98, 0.3, 3.0, "saw")
	_streams["defeat"] = _to_stream(s)
