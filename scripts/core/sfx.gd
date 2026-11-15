extends Node
## Sound effects. Impacts, explosions, crashes, the bell and the engine are
## recorded CC0 sounds from assets/sounds (several takes each, picked at
## random so repeated hits never sound identical); whooshes, the surge,
## beeps, tyres and the crowd are synthesised at start-up.

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
	streams["cash"] = _chime([1318.5, 1760.0], 0.09)
	streams["click"] = _tone(0.04, 1400.0)
	streams["horn"] = _horn(0.45)
	streams["land"] = _impact(0.1, 160.0, 0.6)
	streams["scrape"] = _impact(0.16, 1800.0, 0.5)
	_load_recorded()


## Recorded takes replace the synthesised stand-ins where a file exists:
## assets/sounds/<name>.wav or <name>_1.wav, <name>_2.wav...
func _load_recorded() -> void:
	for sound: String in ["punch", "heavy", "block", "explosion", "crash", "scrape", "bell", "door", "click", "land"]:
		var takes: Array = []
		var single := "res://assets/sounds/%s.wav" % sound
		if ResourceLoader.exists(single):
			takes.append(load(single))
		for i in range(1, 8):
			var path := "res://assets/sounds/%s_%d.wav" % [sound, i]
			if not ResourceLoader.exists(path):
				break
			takes.append(load(path))
		if not takes.is_empty():
			streams[sound] = takes
	var loop := "res://assets/sounds/engine_loop.wav"
	if ResourceLoader.exists(loop):
		var src := load(loop) as AudioStreamWAV
		if src:
			var w := src.duplicate() as AudioStreamWAV
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = int(w.get_length() * w.mix_rate)
			streams["engine"] = w


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
	var stream = streams[sound]
	if stream is Array:
		stream = stream[_rng.randi() % (stream as Array).size()]
	player.set("stream", stream)
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


func _chime(notes: Array, each: float) -> AudioStreamWAV:
	var n := int(each * notes.size() * RATE + 0.25 * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for k in notes.size():
		var start := int(k * each * RATE)
		for i in range(start, n):
			var t := float(i - start) / RATE
			s[i] += sin(TAU * float(notes[k]) * t) * exp(-t * 14.0) * 0.4
	return _wav(s)


func _horn(length: float) -> AudioStreamWAV:
	var n := int(length * RATE)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var env := minf(minf(t * 60.0, 1.0), (length - t) * 30.0)
		s[i] = (signf(sin(TAU * 392.0 * t)) * 0.18 + signf(sin(TAU * 494.0 * t)) * 0.18 + sin(TAU * 196.0 * t) * 0.2) * env
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
