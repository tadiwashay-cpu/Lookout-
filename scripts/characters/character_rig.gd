class_name CharacterRig
extends Node3D
## Visual character (X Bot, Y Bot or the low-poly NPC man) with the Mixamo
## clip set and a held weapon. Shared by the player, other players, bots,
## goons, cops and pedestrians. Forward is this node's -Z.
##
## Weapon holding: the gun's grip sits in the right palm, and it is turned
## so its support point lines up with the left palm. The fit is measured
## once from the two-handed aiming pose, then the gun is locked to the
## right hand, so it follows every animation (reload, grenade toss...).

const LOOPING: Array[StringName] = [
	&"idle", &"idle_unarmed", &"fight_idle", &"walk", &"run_unarmed", &"sprint", &"falling",
	&"walk_back", &"walk_back_unarmed", &"run", &"run_back",
	&"strafe_left", &"strafe_right", &"strafe_left_run", &"strafe_right_run",
	&"strafe_left_unarmed", &"strafe_right_unarmed", &"fire", &"block", &"boxing",
	&"pistol_idle", &"pistol_walk", &"shotgun_idle", &"shotgun_walk",
]
## Metres per second each locomotion clip covers at speed 1 (measured on import).
const GROUND_SPEED := {
	&"walk": 1.51, &"run_unarmed": 5.12, &"sprint": 7.76,
	&"walk_back": 1.01, &"walk_back_unarmed": 1.0, &"run": 2.9, &"run_back": 2.53,
	&"strafe_left": 1.26, &"strafe_right": 0.7, &"strafe_left_run": 2.59, &"strafe_right_run": 3.04,
	&"strafe_left_unarmed": 1.6, &"strafe_right_unarmed": 1.6,
	&"pistol_walk": 1.59, &"shotgun_walk": 1.55,
}
## Gun clip sets by weapon class.
const PISTOL_CLASSES := ["pistol"]
const LONG_GUN_CLASSES := ["rifle", "smg", "lmg", "sniper", "shotgun"]

## Weapon fit per character model, shared by every instance (hand-local).
static var _fit_cache: Dictionary = {}

var anim: AnimationPlayer
var skeleton: Skeleton3D
var weapon: Node3D
var weapon_id := ""
var weapon_class := "rifle"
## Unarmed: use the fighting stance instead of the relaxed idle (enemies near).
var fight_ready := false
var muzzle: Node3D
var armed := true:
	set(value):
		armed = value
		if weapon:
			weapon.visible = value and is_visible_in_tree()

var _model_key := ""
var _right_hand := -1
var _left_hand := -1
var _right_finger := -1
var _left_finger := -1
var _support_local := Vector3(0, 0, -0.4)
var _recoil := 0.0
var _materials: Array[StandardMaterial3D] = []


## character_id: "x_bot", "y_bot" or "npc".
func _ready() -> void:
	# Run after the AnimationPlayer has posed the skeleton (no 1-frame lag).
	process_priority = 100


func setup(character_id: String, height: float = 1.8) -> void:
	var path := GameSettings.NPC_SCENE
	if character_id != "npc":
		var info: Dictionary = GameSettings.CHARACTERS.get(character_id, GameSettings.CHARACTERS["x_bot"])
		path = info["scene"]
	_model_key = path
	var holder := Node3D.new()
	holder.name = "Holder"
	holder.rotation.y = PI   # Mixamo characters face +Z
	add_child(holder)
	var model := (load(path) as PackedScene).instantiate() as Node3D
	holder.add_child(model)
	_fit_height(model, height)

	var players := model.find_children("*", "AnimationPlayer", true, false)
	if not players.is_empty():
		anim = players[0] as AnimationPlayer
		for clip in LOOPING:
			if anim.has_animation(clip):
				anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if not skeletons.is_empty():
		skeleton = skeletons[0] as Skeleton3D
		for i in skeleton.get_bone_count():
			var bone := skeleton.get_bone_name(i)
			if bone.ends_with("RightHand"):
				_right_hand = i
			elif bone.ends_with("LeftHand"):
				_left_hand = i
			elif bone.ends_with("RightHandMiddle1"):
				_right_finger = i
			elif bone.ends_with("LeftHandMiddle1"):
				_left_finger = i
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		for s in instance.mesh.get_surface_count():
			var base := instance.mesh.surface_get_material(s) as StandardMaterial3D
			if base:
				var copy := base.duplicate() as StandardMaterial3D
				instance.set_surface_override_material(s, copy)
				_materials.append(copy)
	play(&"idle" if armed else &"idle_unarmed")


## Recolour (NPCs, goons, cops). First colour = first material, etc.
func tint(colors: Array) -> void:
	for i in _materials.size():
		_materials[i].albedo_color = colors[mini(i, colors.size() - 1)]


func set_weapon(id: String) -> void:
	if id == weapon_id and weapon:
		return
	if weapon:
		weapon.queue_free()
		weapon = null
		muzzle = null
	weapon_id = id
	if id == "":
		return
	var data := WeaponCatalog.get_data(id)
	weapon_class = data["class"]
	weapon = (load(data["path"]) as PackedScene).instantiate() as Node3D
	weapon.top_level = true
	add_child(weapon)
	muzzle = weapon.find_child("Muzzle", true, false) as Node3D
	var support := weapon.find_child("Support", true, false) as Node3D
	_support_local = support.position if support else Vector3(0, 0.05, -0.4)
	if _support_local.length() < 0.05:
		_support_local = Vector3(0, 0.02, -0.3)
	armed = armed


func kick(amount: float = 1.0) -> void:
	_recoil = minf(_recoil + 0.035 * amount, 0.08)


func _process(delta: float) -> void:
	_recoil = move_toward(_recoil, 0.0, delta * 0.6)
	_update_weapon()


func _palm(hand: int, finger: int) -> Vector3:
	var sk := skeleton.global_transform
	var wrist := sk * skeleton.get_bone_global_pose(hand).origin
	if finger >= 0:
		var knuckle := sk * skeleton.get_bone_global_pose(finger).origin
		return wrist.lerp(knuckle, 0.65)
	# No finger bones (NPC rig): push a little past the wrist along the hand.
	var hand_basis := (sk * skeleton.get_bone_global_pose(hand)).basis
	return wrist + hand_basis.y.normalized() * 0.07


func _update_weapon() -> void:
	if weapon == null:
		return
	weapon.visible = armed and is_visible_in_tree()
	if not weapon.visible:
		return
	var forward := -global_basis.z.normalized()
	if skeleton == null or _right_hand < 0 or _left_hand < 0:
		weapon.global_transform = Transform3D(Basis.looking_at(forward, Vector3.UP), global_position + Vector3(0, 1.3, 0) + forward * 0.3)
		return
	var hand := (skeleton.global_transform * skeleton.get_bone_global_pose(_right_hand)).orthonormalized()
	var key := "%s|%s" % [_model_key, weapon_id]
	if not _fit_cache.has(key) and anim and anim.current_animation in [&"idle", &"pistol_idle", &"shotgun_idle"] and anim.current_animation_position > 0.25:
		_fit_cache[key] = hand.affine_inverse() * _two_hand_pose()
	var target: Transform3D
	if _fit_cache.has(key):
		target = hand * (_fit_cache[key] as Transform3D)
	else:
		target = _two_hand_pose()
	target.basis = target.basis.orthonormalized()   # never inherit character scale
	if _recoil > 0.0:
		target.origin += target.basis.z * _recoil
	weapon.global_transform = target


## Grip in the right palm, support point aimed at the left palm.
func _two_hand_pose() -> Transform3D:
	var right := _palm(_right_hand, _right_finger)
	var left := _palm(_left_hand, _left_finger)
	var forward := -global_basis.z.normalized()
	var direction := left - right
	if direction.length() < 0.08 or direction.normalized().dot(forward) < 0.3:
		direction = forward
	direction = direction.normalized()
	var up := Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.95 else forward
	var aim := Basis.looking_at(direction, up)
	# The support point sits slightly above the barrel line — tilt to match.
	var tilt := atan2(_support_local.y, -_support_local.z)
	return Transform3D(aim * Basis(Vector3.RIGHT, -tilt), right)


func muzzle_position() -> Vector3:
	if muzzle and weapon and weapon.visible:
		return muzzle.global_position
	return global_position + Vector3(0, 1.35, 0) - global_basis.z * 0.8


func current_clip() -> StringName:
	return anim.current_animation if anim else &""


func has_clip(clip: StringName) -> bool:
	return anim != null and anim.has_animation(clip)


func clip_length(clip: StringName) -> float:
	return anim.get_animation(clip).length if has_clip(clip) else 0.5


func play(clip: StringName, speed: float = 1.0, blend: float = 0.15) -> bool:
	if anim == null or not anim.has_animation(clip):
		return false
	anim.speed_scale = speed
	if anim.current_animation != clip:
		anim.play(clip, blend)
	return true


## Restart a one-shot clip.
func replay(clip: StringName, speed: float = 1.0, blend: float = 0.05) -> bool:
	if anim == null or not anim.has_animation(clip):
		return false
	anim.speed_scale = speed
	anim.play(clip, blend)
	anim.seek(0.0, true)
	return true


func is_pistol() -> bool:
	return armed and weapon_class in PISTOL_CLASSES


## Clip names that depend on what you're holding.
func idle_clip() -> StringName:
	if not armed:
		return &"fight_idle" if fight_ready and has_clip(&"fight_idle") else &"idle_unarmed"
	if is_pistol() and has_clip(&"pistol_idle"):
		return &"pistol_idle"
	return &"idle"


func fire_clip() -> StringName:
	return &"pistol_fire" if is_pistol() and has_clip(&"pistol_fire") else &"fire"


func reload_clip() -> StringName:
	return &"pistol_reload" if is_pistol() and has_clip(&"pistol_reload") else &"reload"


func hit_clip() -> StringName:
	return &"hit" if armed else &"hit_unarmed"


## Pick idle / walk / run / sprint / backwards / strafe from velocity in the
## character's frame. Unarmed uses normal locomotion; the gun sets are only
## used while a weapon is out.
func play_locomotion(local_right: float, local_forward: float) -> void:
	var speed := Vector2(local_right, local_forward).length()
	if speed < 0.3:
		play(idle_clip(), 1.0, 0.2)
		return
	var clip: StringName
	var forwardish := absf(local_forward) >= absf(local_right) * 0.8
	if not armed:
		if forwardish and local_forward > 0.0:
			clip = &"walk" if speed < 2.6 else (&"run_unarmed" if speed < 6.0 else &"sprint")
		elif forwardish:
			clip = &"walk_back_unarmed" if speed < 2.4 else &"run_back"
		else:
			clip = StringName("strafe_%s_unarmed" % ("right" if local_right > 0.0 else "left"))
			if speed > 2.6:
				clip = StringName("strafe_%s_run" % ("right" if local_right > 0.0 else "left"))
	elif is_pistol():
		if forwardish and local_forward > 0.0:
			clip = &"pistol_walk" if speed < 2.6 else &"run_unarmed"
		elif forwardish:
			clip = &"walk_back" if speed < 2.4 else &"run_back"
		else:
			clip = StringName("strafe_%s%s" % ["right" if local_right > 0.0 else "left", "_run" if speed > 2.1 else ""])
	else:
		if forwardish and local_forward > 0.0:
			clip = &"shotgun_walk" if speed < 2.3 and has_clip(&"shotgun_walk") else &"run"
		elif forwardish:
			clip = &"run_back" if speed > 2.1 else &"walk_back"
		else:
			clip = StringName("strafe_%s%s" % ["right" if local_right > 0.0 else "left", "_run" if speed > 2.1 else ""])
	if not has_clip(clip):
		clip = &"walk"
	play(clip, clampf(speed / float(GROUND_SPEED.get(clip, 1.0)), 0.6, 1.8), 0.18)


func _fit_height(model: Node3D, height: float) -> void:
	var bounds := _bounds(model, Transform3D.IDENTITY)
	if bounds.size.y <= 0.001:
		return
	var s := height / bounds.size.y
	if s < 0.05 or s > 20.0:
		return
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
