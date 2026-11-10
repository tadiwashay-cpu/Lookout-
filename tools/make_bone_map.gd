extends SceneTree
## Builds the Mixamo -> Godot humanoid bone map used when importing every
## character (all our rigs use mixamorig:* names).
##   godot --headless --path . --script res://tools/make_bone_map.gd

const MIXAMO := {
	"Hips": "Hips", "Spine": "Spine", "Chest": "Spine1", "UpperChest": "Spine2",
	"Neck": "Neck", "Head": "Head",
	"LeftShoulder": "LeftShoulder", "LeftUpperArm": "LeftArm", "LeftLowerArm": "LeftForeArm", "LeftHand": "LeftHand",
	"RightShoulder": "RightShoulder", "RightUpperArm": "RightArm", "RightLowerArm": "RightForeArm", "RightHand": "RightHand",
	"LeftUpperLeg": "LeftUpLeg", "LeftLowerLeg": "LeftLeg", "LeftFoot": "LeftFoot", "LeftToes": "LeftToeBase",
	"RightUpperLeg": "RightUpLeg", "RightLowerLeg": "RightLeg", "RightFoot": "RightFoot", "RightToes": "RightToeBase",
}
const FINGERS := {"Thumb": ["Metacarpal", "Proximal", "Distal"], "Index": ["Proximal", "Intermediate", "Distal"],
	"Middle": ["Proximal", "Intermediate", "Distal"], "Ring": ["Proximal", "Intermediate", "Distal"],
	"Little": ["Proximal", "Intermediate", "Distal"]}


func _initialize() -> void:
	var map := BoneMap.new()
	map.profile = SkeletonProfileHumanoid.new()
	var names := MIXAMO.duplicate()
	for side in ["Left", "Right"]:
		for finger: String in FINGERS:
			var mix_finger := "Pinky" if finger == "Little" else finger
			for k in 3:
				names["%s%s%s" % [side, finger, FINGERS[finger][k]]] = "%sHand%s%d" % [side, mix_finger, k + 1]
	var missing := []
	for i in map.profile.bone_size:
		var profile_bone := map.profile.get_bone_name(i)
		if names.has(profile_bone):
			map.set_skeleton_bone_name(profile_bone, StringName("mixamorig_" + names[profile_bone]))
		else:
			missing.append(profile_bone)
	var err := ResourceSaver.save(map, "res://assets/models/characters/retarget/mixamo_humanoid.tres")
	print("BONEMAP saved err=", err, " unmapped profile bones: ", missing)
	quit()
