extends Node
## Dev: loads the world in a mode and saves screenshots.
##   godot --path . res://tools/capture/shots.tscn -- OUT_DIR MODE(0 free,1 clean hands,2 race) [frames]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var mode := int(args[1])
	var frames := int(args[2]) if args.size() > 2 else 240
	Game.match_config = {"mode": mode, "networked": false, "minutes": 3, "bots": 3 if mode == 1 else 5, "laps": 1, "difficulty": 0.6, "car": "sport", "seed": 5}
	var t0 := Time.get_ticks_msec()
	var world: Node3D = (load(Game.WORLD_SCENE) as PackedScene).instantiate()
	add_child(world)
	print("BUILD_MS ", Time.get_ticks_msec() - t0)
	var vp := get_viewport()
	await _frames(frames / 2)
	vp.get_texture().get_image().save_png("%s/m%d_play_a.png" % [out, mode])
	await _frames(frames / 2)
	vp.get_texture().get_image().save_png("%s/m%d_play_b.png" % [out, mode])
	var p: Player = world.get("player")
	print("PLAYER ", p.global_position, " car=", p.car != null, " hp=", p.health, " fps=", Engine.get_frames_per_second())
	if mode == 0:
		var cam := Camera3D.new()
		cam.far = 3000.0
		world.add_child(cam)
		cam.make_current()
		world.get("hud").visible = false
		var views := [["city", Vector3(-380, 160, 330), Vector3(40, 0, -60)], ["street", Vector3(30, 5, 60), Vector3(30, 4, -100)],
			["harbour", Vector3(560, 60, 330), Vector3(560, 0, 0)], ["ring", Layout.RING_CENTER + Vector3(10, 7, 12), Layout.RING_CENTER + Vector3.UP * 1.5],
			["suburb", Vector3(-560, 50, 120), Vector3(-760, 0, -40)], ["forest", Vector3(-280, 70, 560), Vector3(-560, 20, 820)],
			["mountain", Vector3(380, 120, -560), Vector3(-100, 120, -1000)], ["pass", Vector3(240, Terrain.height_at(240, -860) + 6, -830), Vector3(-110, Terrain.height_at(-110, -905) + 2, -905)]]
		for v in views:
			cam.look_at_from_position(v[1], v[2], Vector3.UP)
			await _frames(8)
			vp.get_texture().get_image().save_png("%s/view_%s.png" % [out, v[0]])
		var services: Services = world.get("services")
		var i := 0
		for kind in services.doors:
			var o := Vector3(i * 60.0, Services.DEPTH, 0)
			cam.look_at_from_position(o + Vector3(7, 3.5, 7), o + Vector3(-2, 1, -3), Vector3.UP)
			await _frames(8)
			vp.get_texture().get_image().save_png("%s/inside_%s.png" % [out, kind])
			i += 1
			if i >= 3:
				break
		world.set("time_of_day", 0.02)
		world.call("_apply_time")
		world.call("_place_lamps")
		cam.look_at_from_position(Vector3(30, 9, 70), Vector3(30, 3, -100), Vector3.UP)
		await _frames(8)
		vp.get_texture().get_image().save_png("%s/view_night.png" % out)
	print("SHOTS_DONE")
	get_tree().quit()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
