extends Node
## Dev: the real flow (menu -> loading screen -> world) with screenshots.
##   godot --path . res://tools/capture/flow.tscn -- OUT_DIR MODE

class Runner:
	extends Node
	var out := ""
	var mode := 0

	func shot(name: String) -> void:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
		print("shot ", name)

	func wait(seconds: float) -> void:
		await get_tree().create_timer(seconds, true, false, true).timeout

	func _ready() -> void:
		await wait(0.5)
		await shot("menu")
		var menu := get_tree().current_scene
		menu.call("_report")
		await wait(0.2)
		await shot("report")
		Game.start_match({"mode": mode, "networked": false, "minutes": 3, "bots": 3, "laps": 1, "difficulty": 0.6, "car": "sport", "seed": 5})
		await get_tree().process_frame
		await get_tree().process_frame
		await shot("loading_a")
		var world: Node = null
		for i in 2000:
			await get_tree().process_frame
			world = get_tree().current_scene
			if world and world.get("built") == true and not Game.loading_active():
				break
			if i == 6:
				await shot("loading_b")
		print("world built, frame ", Engine.get_process_frames())
		await wait(1.5)
		await shot("world")
		var hud: Hud = world.get("hud")
		var player: Player = world.get("player")
		hud.popup("KNOCKOUT!  +1")
		Game.add_money(500)
		Fx.confetti(world, player.global_position + player.global_basis.z * 2.0 + Vector3.UP * 1.5, 80)
		await wait(0.45)
		await shot("popup")
		hud.open_map()
		await wait(0.4)
		await shot("map")
		hud.close_map()
		if mode == 0:
			# Stand by the loop and watch the traffic go by.
			var traffic: Traffic = world.get_node("Traffic")
			player.global_position = traffic.loop[20] + Vector3(9, 0.5, 0)
			for k in 3:
				await wait(4.0)
				print("traffic cars: ", traffic.cars.size())
				var nearest: Node3D = null
				for c in traffic.cars:
					if nearest == null or c.global_position.distance_to(player.global_position) < nearest.global_position.distance_to(player.global_position):
						nearest = c
				if nearest:
					var f: Vector3 = nearest.get("_fwd")
					player.global_position = nearest.global_position + f * (22.0 - k * 6.0) + f.cross(Vector3.UP) * 5.0 + Vector3.UP * 0.5
					player.cam.set("_pivot_set", false)
					await wait(0.25)
					var d := nearest.global_position - player.global_position
					player.cam.yaw = atan2(-d.x, -d.z)
					print("nearest ", nearest.global_position.snapped(Vector3.ONE * 0.1), " dist ", snappedf(d.length(), 0.1), " speed ", snappedf(nearest.get("speed"), 0.1))
				await wait(0.3)
				await shot("traffic%d" % k)
		await wait(1.0)
		Game.back_to_menu()
		await wait(0.6)
		get_tree().current_scene.call("_report")
		await wait(0.2)
		await shot("report_after")
		get_tree().quit()


func _ready() -> void:
	var r := Runner.new()
	var args := OS.get_cmdline_user_args()
	r.out = args[0]
	r.mode = int(args[1]) if args.size() > 1 else 0
	get_tree().root.add_child.call_deferred(r)
	get_tree().change_scene_to_file.call_deferred(Game.MENU_SCENE)
