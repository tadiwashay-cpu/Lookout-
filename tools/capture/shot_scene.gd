extends SceneTree
## Dev: open any scene, wait, save a screenshot.
##   godot --path . --rendering-driver opengl3 --script res://tools/capture/shot_scene.gd -- SCENE OUT.png [frames]

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	change_scene_to_file(args[0])
	var frames := int(args[2]) if args.size() > 2 else 20
	for i in frames:
		await process_frame
	root.get_texture().get_image().save_png(args[1])
	print("SHOT_SAVED")
	quit()
