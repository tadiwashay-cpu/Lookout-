extends SceneTree
## Prints the Skeleton3D / AnimationPlayer paths inside character files.

func _process(_delta: float) -> bool:
	for path in ["x_bot", "y_bot", "npc_man", "civilians/civ_m_casual", "civilians/civ_f_casual", "civilians/civ_m_suit"]:
		var scene := load("res://assets/models/characters/%s.glb" % path) as PackedScene
		var root := scene.instantiate()
		for sk in root.find_children("*", "Skeleton3D", true, false):
			print("SKEL ", path, " -> ", root.get_path_to(sk), " bones=", (sk as Skeleton3D).get_bone_count())
		for ap in root.find_children("*", "AnimationPlayer", true, false):
			print("ANIM ", path, " -> ", root.get_path_to(ap), " clips=", (ap as AnimationPlayer).get_animation_list().size())
		root.free()
	return true
