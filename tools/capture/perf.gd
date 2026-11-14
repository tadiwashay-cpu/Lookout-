extends Node
## Dev: rendering and CPU cost at a few places (draw calls, triangles,
## objects, script/physics time).
##   godot --path . res://tools/capture/perf.tscn -- OUT_DIR MODE

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var mode := int(args[1]) if args.size() > 1 else 0
	Game.match_config = {"mode": mode, "networked": false, "minutes": 9, "bots": 3 if mode == 1 else 5, "laps": 1, "car": "sport", "seed": 5}
	var t0 := Time.get_ticks_msec()
	var world: Node3D = (load(Game.WORLD_SCENE) as PackedScene).instantiate()
	add_child(world)
	print("PERF build_ms=", Time.get_ticks_msec() - t0)
	var p: Player = world.get("player")
	var spots := {"start": null}
	if mode == 0:
		spots = {"street": Vector3(30, 2.3, 10), "downtown": Vector3(40, 2.3, -120), "forest": Vector3(-450, Terrain.height_at(-450, 820) + 1.0, 820),
			"harbour": Vector3(540, 2.3, 100), "suburb": Vector3(-700, Terrain.height_at(-700, 60) + 1.0, 60), "pass": Vector3(240, Terrain.height_at(240, -860) + 1, -860)}
	for name in spots:
		if spots[name] != null:
			p.global_position = spots[name]
		for i in 90:
			await get_tree().process_frame
		var draw := 0.0
		var prims := 0.0
		var objs := 0.0
		var proc := 0.0
		var phys := 0.0
		var n := 30
		for i in n:
			await get_tree().process_frame
			draw += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
			prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
			proc += Performance.get_monitor(Performance.TIME_PROCESS)
			phys += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
		var awake := 0
		var cars := 0
		for c in get_tree().get_nodes_in_group(&"cars"):
			cars += 1
			if not (c as RigidBody3D).sleeping:
				awake += 1
		print("PERF cars=%d awake=%d fighters=%d" % [cars, awake, get_tree().get_nodes_in_group(&"fighters").size()])
		print("PERF %-9s draws=%5d tris=%8d objs=%5d process_ms=%.2f physics_ms=%.2f nodes=%d" % [name, draw / n, prims / n, objs / n, proc / n * 1000.0, phys / n * 1000.0, Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		if DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png("%s/perf_%s.png" % [out, name])
	print("PERF mem_static_mb=", int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0), " vram_mb=", int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0))
	get_tree().quit()
