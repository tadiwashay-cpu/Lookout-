extends SceneTree
## Dev: global rest + posed rotation of key bones, men vs women (retargeted).

var _step := 0
var _items := []


func _process(_d: float) -> bool:
	if _step == 0:
		for path in ["civilians/civ_m_casual", "civilians/civ_f_casual", "x_bot"]:
			var root := (load("res://assets/models/characters/%s.glb" % path) as PackedScene).instantiate()
			get_root().add_child(root)
			var player := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
			for lib in player.get_animation_library_list():
				player.remove_animation_library(lib)
			player.add_animation_library(&"", CharacterRig.shared_clips())
			player.play(&"punch_2")
			player.seek(0.4, true)
			player.pause()
			_items.append([path, root])
	elif _step == 3:
		for item in _items:
			var sk := (item[1] as Node).find_child("GeneralSkeleton", true, false) as Skeleton3D
			var line: String = str(item[0]).get_file()
			for bn in ["Hips", "LeftUpperLeg", "RightUpperLeg"]:
				var i := sk.find_bone(bn)
				var rest := sk.get_bone_global_rest(i).basis.get_euler()
				var pose := sk.get_bone_global_pose(i).basis
				var down := pose * Vector3.DOWN
				line += "  %s rest=%s legdir=%s" % [bn, (rest * 57.3).snapped(Vector3.ONE), (pose.get_euler() * 57.3).snapped(Vector3.ONE)]
			print(line, "  ms=", sk.motion_scale)
		return true
	_step += 1
	return false
