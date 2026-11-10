extends Node
## Sound effects. A small pool of 3D players (phones choke on hundreds of
## audio nodes), streams cached on first use.
##   Audio.play("gun_rifle", position)        one-shot in 3D
##   Audio.play_ui("click")                   2D, no position
##   Audio.loop(node, "engine_loop")          looping player parented to node

const DIR := "res://assets/audio/sfx/"
const POOL := 12

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer3D] = []
var _next := 0
var _ui: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL:
		var p := AudioStreamPlayer3D.new()
		p.bus = &"Master"
		p.unit_size = 8.0
		p.max_distance = 120.0
		p.attenuation_filter_cutoff_hz = 6000.0
		add_child(p)
		_players.append(p)
	_ui = AudioStreamPlayer.new()
	add_child(_ui)


func stream(name: String) -> AudioStream:
	if not _streams.has(name):
		var path := DIR + name + ".wav"
		if not ResourceLoader.exists(path):
			path = DIR + name + ".ogg"
		_streams[name] = load(path) if ResourceLoader.exists(path) else null
	return _streams[name]


## `variants` > 1 picks name_1..name_N at random (e.g. screams).
func play(name: String, at: Vector3, volume_db: float = 0.0, pitch_jitter: float = 0.08, variants: int = 0) -> void:
	if variants > 0:
		name = "%s_%d" % [name, randi_range(1, variants)]
	var s := stream(name)
	if s == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = s
	p.global_position = at
	p.volume_db = volume_db + linear_to_db(GameSettings.sfx_volume * GameSettings.master_volume)
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func play_ui(name: String) -> void:
	var s := stream(name)
	if s:
		_ui.stream = s
		_ui.volume_db = linear_to_db(GameSettings.sfx_volume * GameSettings.master_volume)
		_ui.play()


func loop(parent: Node3D, name: String, volume_db: float = 0.0) -> AudioStreamPlayer3D:
	var s := stream(name)
	if s == null:
		return null
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		var wav := s as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.unit_size = 10.0
	p.max_distance = 150.0
	p.volume_db = volume_db + linear_to_db(GameSettings.sfx_volume * GameSettings.master_volume)
	parent.add_child(p)
	p.play()
	return p
