extends Node
## Dev: world screenshots at given spots.
##   godot --path . res://tools/capture/look.tscn -- OUT_DIR name:x:z:h:dx:dz ...

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	Game.match_config = {"mode": Game.Mode.CLEAN_HANDS, "networked": false, "bots": 0, "minutes": 9, "seed": 1}
	var world: Node3D = (load(Game.WORLD_SCENE) as PackedScene).instantiate()
	add_child(world)
	world.get("hud").visible = false
	var cam := Camera3D.new()
	cam.far = 3000.0
	world.add_child(cam)
	cam.make_current()
	for k in range(1, args.size()):
		var p := args[k].split(":")
		var x := float(p[1])
		var z := float(p[2])
		var h := float(p[3])
		var g := Terrain.height_at(x, z)
		var from := Vector3(x + float(p[4]), g + h, z + float(p[5]))
		cam.look_at_from_position(from, Vector3(x, g, z), Vector3.UP)
		for i in 10:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/look_%s.png" % [out, p[0]])
	get_tree().quit()
