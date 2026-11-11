extends Node
## Dev: orthographic top views of the world with city colliders (red) and
## road centrelines (yellow) drawn on top.
##   godot --path . --rendering-driver opengl3 res://tools/capture/topdown.tscn -- OUT_DIR

func _ready() -> void:
	var out_dir: String = OS.get_cmdline_user_args()[0]
	Session.mode = Session.MODE_STORY
	var world := load(Session.WORLD_SCENE).instantiate() as World
	add_child(world)
	for i in 40:
		await get_tree().process_frame
	world.day_night.time_of_day = 0.5
	world.day_night.call(&"_apply")
	world._env.fog_enabled = false
	world._env.volumetric_fog_enabled = false
	world.hud.visible = false
	world.touch.visible = false
	for node in world.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		g.visibility_range_end = 0.0
		if g.global_position.y > 100.0 or g.name.to_lower().contains("cloud"):
			g.visible = false
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.far = 2000.0
	add_child(cam)
	cam.make_current()
	world.player.camera().far = 3000.0
	var overlay := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	overlay.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	overlay.material_override = mat
	add_child(overlay)
	var views := [["city", Vector3(0, 95, 0), 620.0, false], ["north", Vector3(-150, 95, -330), 520.0, false]]
	for i in 500:   # let traffic spawn and drive
		await get_tree().process_frame
	for v: Array in views:
		im.clear_surfaces()
		if v[3] and world.imported_city:
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ImportedCity.DATA))
			for c: Array in data["colliders"]:
				var col := Color(1, 0, 0) if float(c[4]) > 1.0 else Color(1, 0, 1)
				var x0 := float(c[0]) - float(c[3]) * 0.5
				var x1 := float(c[0]) + float(c[3]) * 0.5
				var z0 := float(c[2]) - float(c[5]) * 0.5
				var z1 := float(c[2]) + float(c[5]) * 0.5
				for seg: Array in [[x0, z0, x1, z0], [x1, z0, x1, z1], [x1, z1, x0, z1], [x0, z1, x0, z0]]:
					im.surface_set_color(col); im.surface_add_vertex(Vector3(seg[0], 60, seg[1]))
					im.surface_set_color(col); im.surface_add_vertex(Vector3(seg[2], 60, seg[3]))
			for r: Array in world.imported_city.roads:
				im.surface_set_color(Color(1, 1, 0)); im.surface_add_vertex(Vector3(r[0].x, 60, r[0].y))
				im.surface_set_color(Color(1, 1, 0)); im.surface_add_vertex(Vector3(r[1].x, 60, r[1].y))
			im.surface_end()
		cam.size = v[2]
		cam.global_position = v[1]
		cam.rotation = Vector3(-PI * 0.5, 0, 0)
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/top_%s.png" % [out_dir, v[0]])
	im.clear_surfaces()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 60.0
	var hq := world.hq_spawn
	var rp: Vector3 = world.imported_city.places["repair"]["pos"]
	var persp := [["link", Vector3(-330, 45, -90), Vector3(-290, 0, -160)], ["link_low", Vector3(-235, 3, -150), Vector3(-300, 1, -150)],
		["hq", hq + Vector3(10, 7, 14), hq + Vector3.UP * 2.0], ["bank", world.bank_position + Vector3(12, 7, 14), world.bank_position + Vector3.UP * 3.0],
		["repair", rp + Vector3(10, 6, 12), rp + Vector3.UP * 2.0], ["deck", Vector3(-60, 16, -150), Vector3(40, 11, -149)],
		["street_a", Vector3(60, 5, -48), Vector3(160, 4, -48)], ["night", Vector3(35, 12, 20), Vector3(100, 4, -60)]]
	print("TRAFFIC nodes=", world.imported_city.traffic_nodes, " links=", world.imported_city.traffic_links)
	print("PLACES ", world.map_places)
	print("CARS ", get_tree().get_nodes_in_group(&"vehicles").size(), " lamps=", world.imported_city.lamps.size())
	for v: Array in persp:
		if v[0] == "night":
			world.day_night.time_of_day = 0.0
			world.day_night.call(&"_apply")
		cam.look_at_from_position(v[1], v[2], Vector3.UP)
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/p_%s.png" % [out_dir, v[0]])
	# The player at night under the street lights, then the full map.
	world.player.camera().make_current()
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/p_player_night.png" % out_dir)
	world.day_night.time_of_day = 0.5
	world.day_night.call(&"_apply")
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/p_player_day.png" % out_dir)
	world.hud.visible = true
	world.hud.toggle_full_map()
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("%s/p_fullmap.png" % out_dir)
	world.hud.toggle_full_map()
	await get_tree().create_timer(0.5).timeout
	world.hud.toggle_full_map()
	world.hud.visible = false
	world.player.respawn_at_quiet(Vector3(-400, world.ground_height(-400, -1400) + 1.0, -1400), 0.0)
	for i in 400:
		await get_tree().process_frame
	var herd := get_tree().root.find_children("*", "Animal", true, false)
	print("ANIMALS ", herd.size())
	if not herd.is_empty():
		var a := herd[0] as Node3D
		cam.make_current()
		cam.look_at_from_position(a.global_position + Vector3(5, 2.5, 6), a.global_position + Vector3.UP * 0.8, Vector3.UP)
		for i in 5:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/p_animal.png" % out_dir)
	var traffic := world.get_node_or_null("Traffic")
	print("TRAFFIC_CARS ", (traffic.get("_cars") as Array).size() if traffic else -1)
	get_tree().quit()
