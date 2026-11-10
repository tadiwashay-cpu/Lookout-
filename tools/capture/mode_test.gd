extends Node
## Dev: run a multiplayer mode in solo practice for a while, screenshot it.
##   godot --path . --rendering-driver opengl3 res://tools/capture/mode_test.tscn -- OUT_DIR MODE [frames]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0]
	var mode := int(args[1])
	var frames := int(args[2]) if args.size() > 2 else 400
	Session.mode = mode
	Session.networked = false
	Session.match_seed = 12345
	Session.teams = {1: "robbers"} if mode == Session.MODE_HEIST else {}
	var world := load(Session.WORLD_SCENE).instantiate() as World
	add_child(world)
	for i in frames:
		await get_tree().process_frame
		if i == frames / 2:
			get_viewport().get_texture().get_image().save_png("%s/mode_%d_a.png" % [out_dir, mode])
	get_viewport().get_texture().get_image().save_png("%s/mode_%d_b.png" % [out_dir, mode])
	print("MODE_DONE ", mode, " player=", world.player.global_position, " alive=", world.player.is_alive())
	get_tree().quit()
