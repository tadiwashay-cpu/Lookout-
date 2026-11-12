extends Node
## Sound effects synthesised at start-up (no audio files to ship): punches,
## impacts, whooshes, the power surge, explosions, beeps and an engine loop.

const RATE := 22050

var streams: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	streams["punch"] = _impact(0.12, 900.0, 0.9)
	streams["heavy"] = _impact(0.22, 420.0, 1.0)
	streams["block"] = _impact(0.1, 2400.0, 0.5)
	streams["whoosh"] = _whoosh(0.22)
	streams["surge"] = _surge(0.9)
	streams["explosion"] = _explosion(1.6)
	streams["crash"] = _impact(0.35, 300.0, 1.0)
	streams["beep"] = _tone(0.18, 880.0)
	streams["go"] = _tone(0.5, 1320.0)
	streams["engine"] = _engine()
	streams["skid"] = _noise_loop(0.6, 0.25)
	streams["bell"] = _bell(1.4)
	streams["crowd"] = _noise_loop(1.5, 0.12)


## One-shot sound, 3D at `pos` if given.
func play(sound: String, pos: Variant = null, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	if not streams.has(sound):
		return
	var tree := get_tree()
	if tree == null or tree.current_scene == null:
		return
	var player: Node
	if pos is Vector3:
		var p3 := AudioStreamPlayer3D.new()
		p3.max_distance = 120.0
		p3.unit_size = 6.0
		tree.current_scene.add_child(p3)
		p3.global_position = pos
		player = p3
	else:
		player = AudioStreamPlayer.new()
		tree.current_scene.add_child(player)
	player.set("stream", streams[sound])
	player.set("volume_db", volume_db)
	player.set("pitch_scale", pitch * _rng.randf_range(0.94, 1.06))
	player.call("play")
	player.connect("finished", player.queue_free)


# ---------------------------------------------------------------- synths

func _wav(samples: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = samples.size()
	return w


func _impact(length: float, body_hz: float, gain: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		var env := exp(-t * 28.0 / length * 0.12)
		low += (_rng.randf_range(-1, 1) - low) * 0.25
		var thump := sin(TAU * body_hz * t * (1.0 - t * 2.0)) * exp(-t * 30.0)
		s[i] = (low * 0.8 + thump) * env * gain
	return _wav(s)


func _whoosh(length: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var f := 0.0
	for i in n:
		var t := float(i) / n
		f += (_rng.randf_range(-1, 1) - f) * lerpf(0.05, 0.4, t)
		s[i] = f * sin(PI * t) * 0.8
	return _wav(s)


func _surge(length: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		phase += TAU * lerpf(60.0, 30.0, t / length) / RATE
		var boom := sin(phase) * exp(-t * 3.0)
		var crackle := _rng.randf_range(-1, 1) * exp(-t * 9.0) * 0.6
		s[i] = (boom + crackle) * 0.9
	return _wav(s)


func _explosion(length: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var low := 0.0
	for i in n:
		var t := float(i) / RATE
		low += (_rng.randf_range(-1, 1) - low) * 0.06
		s[i] = (low * 3.0 + _rng.randf_range(-1, 1) * exp(-t * 12.0) * 0.5) * exp(-t * 2.2)
	return _wav(s)


func _tone(length: float, hz: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = sin(TAU * hz * t) * 0.5 * minf(1.0, (length - t) * 20.0)
	return _wav(s)


func _bell(length: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (sin(TAU * 660.0 * t) + 0.5 * sin(TAU * 1584.0 * t)) * exp(-t * 2.5) * 0.4
	return _wav(s)


## Two cylinder-ish pulses per cycle at 50 Hz: pitch_scale turns it into revs.
func _engine() -> AudioStreamWAV:
	var n := RATE / 5
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var x := fmod(t * 50.0, 1.0)
		s[i] = (pow(1.0 - x, 3.0) - 0.25) * 0.55 + sin(TAU * 100.0 * t) * 0.15
	return _wav(s, true)


func _noise_loop(length: float, gain: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	var f := 0.0
	for i in n:
		f += (_rng.randf_range(-1, 1) - f) * 0.3
		s[i] = f * gain * 3.0
	return _wav(s, true)
