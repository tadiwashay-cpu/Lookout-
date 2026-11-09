class_name CharacterRig
extends Node3D
## Visual character: X Bot or Y Bot with the Mixamo clip set, plus the rifle.
## Used by the local player and by other players' avatars, so everyone
## animates the same way. Forward is this node's -Z.

const RIFLE_SCENE := preload("res://assets/models/weapons/m4a1.glb")

const LOOPING: Array[StringName] = [
	&"idle", &"walk", &"walk_back", &"run", &"run_back",
	&"strafe_left", &"strafe_right", &"strafe_left_run", &"strafe_right_run",
]
## Metres per second each locomotion clip covers at speed 1 (measured on import).
const GROUND_SPEED := {
	&"walk": 0.92, &"walk_back": 1.01, &"run": 2.9, &"run_back": 2.53,
	&"strafe_left": 1.26, &"strafe_right": 0.7, &"strafe_left_run": 2.59, &"strafe_right_run": 3.04,
}

var anim: AnimationPlayer
var skeleton: Skeleton3D
var rifle: Node3D
var muzzle: Node3D
var armed := true:
	set(value):
		armed = value
		if rifle:
			rifle.visible = value and visible

var _right_hand := -1
var _left_hand := -1


func setup(character_id: String, height: float = 1.8) -> void:
	var info: Dictionary = GameSettings.CHARACTERS.get(character_id, GameSettings.CHARACTERS["x_bot"])
	var scene := load(info["scene"]) as PackedScene
	var holder := Node3D.new()
	holder.name = "Holder"
	holder.rotation.y = PI   # Mixamo characters face +Z
	add_child(holder)
	var model := scene.instantiate() as Node3D
	holder.add_child(model)
	_fit_height(model, height)

	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		anim = players[0] as AnimationPlayer
		for clip in LOOPING:
			if anim.has_animation(clip):
				anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		play(&"idle")
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		skeleton = skeletons[0] as Skeleton3D
		for i in skeleton.get_bone_count():
			var bone := skeleton.get_bone_name(i)
			if bone.ends_with("RightHand"):
				_right_hand = i
			elif bone.ends_with("LeftHand"):
				_left_hand = i

	rifle = RIFLE_SCENE.instantiate() as Node3D
	rifle.top_level = true
	add_child(rifle)
	muzzle = rifle.find_child("Muzzle", true, false) as Node3D
	armed = armed


func _process(_delta: float) -> void:
	_update_rifle()


## Rifle grip in the right hand, barrel pointing at the left (support) hand.
## Falls back to "straight ahead" when the hands are doing something else.
func _update_rifle() -> void:
	if rifle == null:
		return
	rifle.visible = armed and is_visible_in_tree()
	if not rifle.visible:
		return
	var forward := -global_basis.z.normalized()
	if skeleton == null or _right_hand < 0 or _left_hand < 0:
		rifle.global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), global_position + Vector3(0, 1.3, 0) + forward * 0.3)
		return
	var sk := skeleton.global_transform
	var right := sk * skeleton.get_bone_global_pose(_right_hand).origin
	var left := sk * skeleton.get_bone_global_pose(_left_hand).origin
	var direction := left - right
	if direction.length() < 0.08 or direction.normalized().dot(forward) < 0.3:
		direction = forward
	direction = direction.normalized()
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.95 else forward
	rifle.global_transform = Transform3D(Basis.looking_at(direction, up), right)


func muzzle_position() -> Vector3:
	if muzzle:
		return muzzle.global_position
	return global_position + Vector3(0, 1.35, 0) - global_basis.z * 0.8


func current_clip() -> StringName:
	return anim.current_animation if anim else &""


func play(clip: StringName, speed: float = 1.0, blend: float = 0.15) -> bool:
	if anim == null or not anim.has_animation(clip):
		return false
	anim.speed_scale = speed
	if anim.current_animation != clip:
		anim.play(clip, blend)
	return true


## Restart a one-shot clip (e.g. each rifle shot).
func replay(clip: StringName, speed: float = 1.0) -> void:
	if anim and anim.has_animation(clip):
		anim.speed_scale = speed
		anim.play(clip, 0.05)
		anim.seek(0.0, true)


## Pick walk / run / backwards / strafe from velocity in the character's frame.
func play_locomotion(local_right: float, local_forward: float) -> void:
	var speed := Vector2(local_right, local_forward).length()
	if speed < 0.3:
		play(&"idle")
		return
	var running := speed > 2.1
	var clip: StringName
	if absf(local_forward) >= absf(local_right):
		if local_forward > 0.0:
			clip = &"run" if running else &"walk"
		else:
			clip = &"run_back" if running else &"walk_back"
	else:
		if local_right > 0.0:
			clip = &"strafe_right_run" if running else &"strafe_right"
		else:
			clip = &"strafe_left_run" if running else &"strafe_left"
	play(clip, clampf(speed / float(GROUND_SPEED.get(clip, 1.0)), 0.6, 1.9))


func _fit_height(model: Node3D, height: float) -> void:
	var bounds := _bounds(model, Transform3D.IDENTITY)
	if bounds.size.y <= 0.001:
		return
	var s := height / bounds.size.y
	if s < 0.2 or s > 5.0:
		return   # already in metres (or something odd) — leave it alone
	model.scale *= s
	model.position = Vector3(-bounds.get_center().x * s, -bounds.position.y * s, -bounds.get_center().z * s)


func _bounds(node: Node, parent_xform: Transform3D) -> AABB:
	var xform := parent_xform
	if node is Node3D:
		xform = parent_xform * (node as Node3D).transform
	var result := AABB()
	var has_result := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh:
		result = xform * (node as MeshInstance3D).mesh.get_aabb()
		has_result = true
	for child in node.get_children():
		var child_bounds := _bounds(child, xform)
		if child_bounds.size == Vector3.ZERO:
			continue
		result = child_bounds if not has_result else result.merge(child_bounds)
		has_result = true
	return result
