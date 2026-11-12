extends Node3D
## Dev: Nash and a few NPCs playing the same clips side by side.
##   godot --path . res://tools/capture/anim_test.tscn -- OUT_DIR clip1,clip2 TIME

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var clips := args[1].split(",")
	var t := float(args[2]) if args.size() > 2 else 0.4
	var lib := Humanoid.library()
	print("CLIPS ", lib.get_animation_list().size(), " ", lib.get_animation_list())
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.35, 0.38, 0.42)
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var floor_mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(20, 8)
	floor_mi.mesh = pm
	add_child(floor_mi)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0, 1.1, 6.5)
	cam.look_at(Vector3(0, 0.9, 0))
	var models := [Humanoid.NASH, Humanoid.NPC_DIR + "civ_m_casual.glb", Humanoid.NPC_DIR + "civ_f_casual.glb"]
	for clip in clips:
		var hs: Array[Humanoid] = []
		for i in models.size():
			var h := Humanoid.new()
			h.position = Vector3((i - 1) * 1.8, 0, 0)
			add_child(h)
			h.setup(models[i], 1.8 if i < 2 else 1.68)
			h.rotation.y = 0.0
			h.play(StringName(clip))
			h.anim.seek(t, true)
			h.anim.speed_scale = 0.0
			hs.append(h)
		for k in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/anim_%s.png" % [out, clip])
		for h in hs:
			h.queue_free()
		await get_tree().process_frame
	get_tree().quit()
