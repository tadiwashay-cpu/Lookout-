class_name Humanoid
extends Node3D
## A character model playing the shared animation library. Every humanoid in
## the game (Nash, NPCs, fighters) is retargeted to Godot's humanoid profile
## at import, so the Quaternius Universal Animation Library clips (both
## packs, ~90 clips) play on all of them.

const NASH := "res://assets/characters/nash.glb"
const NPC_DIR := "res://assets/characters/npc/"
const NPCS := ["civ_m_casual", "civ_m_casual2", "civ_m_suit", "civ_m_worker", "civ_m_punk", "civ_m_beach",
	"civ_m_farmer", "civ_m_adventurer", "civ_f_casual", "civ_f_formal", "civ_f_suit", "civ_f_worker", "civ_f_punk", "civ_f_adventurer"]
const LIBRARIES := ["res://assets/animations/ual1.glb", "res://assets/animations/ual2.glb"]

static var _library: AnimationLibrary

var anim: AnimationPlayer
var skeleton: Skeleton3D
var model: Node3D
var current := &""
var _one_shot := false


## Every clip from both packs in one library, with track paths that work on
## any retargeted character ("%GeneralSkeleton:Bone").
static func library() -> AnimationLibrary:
	if _library:
		return _library
	_library = AnimationLibrary.new()
	for path: String in LIBRARIES:
		var scene := (load(path) as PackedScene).instantiate()
		var player := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player:
			for lib_name in player.get_animation_library_list():
				var lib := player.get_animation_library(lib_name)
				for clip_name in lib.get_animation_list():
					var src := lib.get_animation(clip_name)
					var a := src.duplicate(true) as Animation
					for t in range(a.get_track_count() - 1, -1, -1):
						var p := str(a.track_get_path(t))
						var i := p.find("GeneralSkeleton:")
						if i < 0:
							a.remove_track(t)
							continue
						var bone := p.substr(i + 16)
						# In-place: drop root motion and the hips' sideways drift.
						if bone == "Root":
							a.remove_track(t)
							continue
						a.track_set_path(t, NodePath("%GeneralSkeleton:" + bone))
					if str(clip_name).ends_with("_Loop") or str(clip_name) in ["Sword_Idle", "Driving_Loop"]:
						a.loop_mode = Animation.LOOP_LINEAR
					if not _library.has_animation(clip_name):
						_library.add_animation(clip_name, a)
		scene.free()
	return _library


func setup(model_path: String, height: float = 1.8) -> void:
	model = (load(model_path) as PackedScene).instantiate() as Node3D
	add_child(model)
	skeleton = model.find_child("GeneralSkeleton", true, false) as Skeleton3D
	for old in model.find_children("*", "AnimationPlayer", true, false):
		old.queue_free()
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	model.add_child(anim)
	anim.root_node = anim.get_path_to(model)
	anim.add_animation_library(&"", library())
	anim.playback_default_blend_time = 0.18
	anim.animation_finished.connect(func(_n: StringName) -> void: _one_shot = false)
	# Size to `height` from the head bone (model files differ in scale).
	if skeleton:
		var head := skeleton.find_bone("Head")
		if head >= 0:
			var top := (skeleton.global_transform * skeleton.get_bone_global_rest(head).origin).y - global_position.y
			if top > 0.1:
				model.scale *= (height * 0.88) / top
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).visibility_range_end = 180.0


static func random_npc(rng: RandomNumberGenerator) -> String:
	return NPC_DIR + NPCS[rng.randi() % NPCS.size()] + ".glb"


func has(clip: StringName) -> bool:
	return anim != null and anim.has_animation(clip)


## Loop or hold a clip (ignored while a one-shot is still playing unless forced).
func play(clip: StringName, blend: float = -1.0, speed: float = 1.0, force: bool = false) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	if _one_shot and not force:
		return
	if current == clip and anim.is_playing():
		anim.speed_scale = speed
		return
	current = clip
	anim.play(clip, blend)
	anim.speed_scale = speed


## Play once; locomotion calls are ignored until it finishes.
func one_shot(clip: StringName, speed: float = 1.0, blend: float = 0.08) -> float:
	if anim == null or not anim.has_animation(clip):
		return 0.0
	_one_shot = true
	current = clip
	anim.play(clip, blend)
	anim.speed_scale = speed
	return anim.get_animation(clip).length / maxf(speed, 0.01)


func busy() -> bool:
	return _one_shot


func cancel_one_shot() -> void:
	_one_shot = false


func bone_position(bone: String) -> Vector3:
	if skeleton == null:
		return global_position + Vector3.UP
	var i := skeleton.find_bone(bone)
	if i < 0:
		return global_position + Vector3.UP
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
