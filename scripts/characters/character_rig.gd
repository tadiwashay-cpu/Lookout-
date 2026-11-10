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
	&"strafe_left_unarmed", &"strafe_right_unarmed", &"fire", &"block", &"stunned",
	&"pistol_idle", &"pistol_walk", &"shotgun_idle", &"shotgun_walk",
]
## Metres per second each locomotion clip covers at speed 1 (measured on import).
## Foot speed of each loop (m/s at 1.8 m tall) so feet don't slide.
## RPG pack values measured on its root-motion clips, scaled from its 2.35 m rig.
const GROUND_SPEED := {
	&"walk": 1.35, &"walk_back_unarmed": 2.36, &"run_unarmed": 4.78, &"run_back": 4.1, &"sprint": 7.7,
	&"strafe_left_unarmed": 2.29, &"strafe_right_unarmed": 2.21, &"strafe_left_run": 4.17, &"strafe_right_run": 4.16,
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
## True first person: the body stays visible (you see your arms and gun),
## only the head is collapsed so it doesn't block the camera.
var first_person := false
## Keep feet on the ground: lift the model if an animation pushes the feet
## below the floor (different rigs/clips sit slightly differently).
var ground_feet := true
var _head := -1
var _head_hidden := false
var _feet: Array[int] = []
var _foot_rest_y := 0.0
var _model_base_y := 0.0
var _lift := 0.0
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


## Shared clip libraries for the civilian groups (loaded once, reused by
## every civilian of that group: much less memory than a copy per model).
static var _shared_clips: Dictionary = {}


static func _civilian_clips(group: String) -> AnimationLibrary:
	if _shared_clips.has(group):
		return _shared_clips[group]
	var scene := load(GameSettings.CIVILIAN_DIR + group + "_casual.glb") as PackedScene
	var library: AnimationLibrary = null
	if scene:
		var carrier := scene.instantiate()
		var player := carrier.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if player and player.has_animation_library(&""):
			library = player.get_animation_library(&"")
		carrier.free()
	_shared_clips[group] = library
	return library


func setup(character_id: String, height: float = 1.8) -> void:
	var path := GameSettings.NPC_SCENE
	if character_id.begins_with("civ_"):
		path = GameSettings.CIVILIAN_DIR + character_id + ".glb"
	elif character_id != "npc":
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
	if players.is_empty() and character_id.begins_with("civ_"):
		# Mesh-only civilian: borrow its group's clips.
		var library := _civilian_clips(character_id.substr(0, 5))
		if library:
			var player := AnimationPlayer.new()
			player.name = "AnimationPlayer"
			model.add_child(player)
			player.add_animation_library(&"", library)
			players.append(player)
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
			elif bone.ends_with("Head") and not bone.ends_with("HeadTop_End"):
				_head = i
			elif bone.ends_with("LeftFoot") or bone.ends_with("RightFoot"):
				_feet.append(i)
			elif bone.ends_with("LeftHandMiddle1"):
				_left_finger = i
	if skeleton and not _feet.is_empty():
		_foot_rest_y = INF
		for foot in _feet:
			_foot_rest_y = minf(_foot_rest_y, skeleton.get_bone_global_rest(foot).origin.y)
	_model_base_y = model.position.y
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var instance := mesh as MeshInstance3D
		for s in instance.mesh.get_surface_count():
			var base := instance.mesh.surface_get_material(s) as StandardMaterial3D
			if base and character_id == "npc":   # only tinted models need their own copies
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
	_finish_gun(weapon)
	weapon.top_level = true
	weapon.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF   # placed from the smoothed hand
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
	if skeleton:
		if _head >= 0 and (first_person or _head_hidden):
			skeleton.set_bone_pose_scale(_head, Vector3.ONE * 0.001 if first_person else Vector3.ONE)
			_head_hidden = first_person
		if ground_feet and not _feet.is_empty():
			_keep_feet_on_ground(delta)
	_update_weapon()


func _keep_feet_on_ground(delta: float) -> void:
	var lowest := INF
	for foot in _feet:
		lowest = minf(lowest, skeleton.get_bone_global_pose(foot).origin.y)
	# Skeleton space -> how far below its rest height the lowest ankle is.
	# Positive = feet sank below the floor (lift), negative = feet float
	# (pull down). Big negatives are jumps/kicks: leave those alone.
	var sink := (_foot_rest_y - lowest) * skeleton.global_basis.get_scale().y
	var want := clampf(sink, -0.18, 0.3) if sink > -0.25 else 0.0
	_lift = lerpf(_lift, want, clampf(delta * 12.0, 0.0, 1.0))
	var holder := get_child(0) as Node3D
	if holder and holder.get_child_count() > 0:
		(holder.get_child(0) as Node3D).position.y = _model_base_y + _lift


## The gun pack has no textures (flat 0.8 grey). Give the parts real finishes:
## black metal, gunmetal, polymer, and a wood stock on wooden-furniture guns.
static var _gun_mats: Array[StandardMaterial3D] = []


func _finish_gun(root: Node) -> void:
	if _gun_mats.is_empty():
		for spec in [[Color(0.035, 0.035, 0.038), 0.9, 0.35], [Color(0.16, 0.165, 0.17), 0.85, 0.3],
				[Color(0.07, 0.07, 0.065), 0.0, 0.7], [Color(0.3, 0.17, 0.08), 0.0, 0.6]]:
			var m := StandardMaterial3D.new()
			m.albedo_color = spec[0]
			m.metallic = spec[1]
			m.roughness = spec[2]
			_gun_mats.append(m)
	var wood := weapon_id in ["ak47"]
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for s in mesh.mesh.get_surface_count():
			var base := mesh.mesh.surface_get_material(s) as BaseMaterial3D
			if base and base.albedo_texture == null and base.albedo_color.r > 0.7 and base.albedo_color.g > 0.7:
				var pick := s % 3
				if wood and s == 1:
					pick = 3
				mesh.set_surface_override_material(s, _gun_mats[pick])


func _palm(hand: int, finger: int) -> Vector3:
	var sk := skeleton.get_global_transform_interpolated()
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
	var hand := (skeleton.get_global_transform_interpolated() * skeleton.get_bone_global_pose(_right_hand)).orthonormalized()
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
	return &"shotgun_idle" if has_clip(&"shotgun_idle") else &"idle"   # long guns: shooter aim set


## Shooter pack: pistols fire with the revolver shot; long guns hold the aim
## pose and the recoil comes from kick().
func fire_clip() -> StringName:
	if is_pistol() and has_clip(&"pistol_fire"):
		return &"pistol_fire"
	return &"fire" if has_clip(&"fire") else idle_clip()


func reload_clip() -> StringName:
	if has_clip(&"reload"):
		return &"reload" if not is_pistol() else &"pistol_reload"
	return &"pistol_reload" if has_clip(&"pistol_reload") else idle_clip()


func hit_clip() -> StringName:
	return &"hit" if armed and has_clip(&"hit") else &"hit_unarmed"


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
	else:
		# Gun out: the shooter pack's aim-walk going forward, the RPG
		# strafes/back-steps otherwise (the shooter pack has no strafes).
		var aim_walk := &"pistol_walk" if is_pistol() else &"shotgun_walk"
		if forwardish and local_forward > 0.0:
			clip = aim_walk if speed < 2.6 and has_clip(aim_walk) else &"run_unarmed"
		elif forwardish:
			clip = &"walk_back_unarmed" if speed < 2.4 else &"run_back"
		else:
			clip = StringName("strafe_%s_%s" % ["right" if local_right > 0.0 else "left", "run" if speed > 2.6 else "unarmed"])
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
