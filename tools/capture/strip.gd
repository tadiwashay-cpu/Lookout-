extends Node3D
## Dev: film strips of clips on Nash (8 poses across a time window).
##   godot --path . res://tools/capture/strip.tscn -- OUT_DIR clip:from:to ...

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.33, 0.37)
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.9
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0)
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 3.2
	cam.position = Vector3(7.0, 1.0, 9.0)
	cam.look_at(Vector3(7.0, 1.0, 0.0))
	print("HAS ", Humanoid.library().get_animation_list().size())
	for k in range(1, args.size()):
		var p := args[k].split(":")
		var hs: Array = []
		for i in 8:
			var h := Humanoid.new()
			h.position = Vector3(i * 2.0, 0, 0)
			h.rotation.y = -PI * 0.5 + 0.5     # mostly side-on, facing right
			add_child(h)
			h.setup(Humanoid.NASH)
			if not h.has(StringName(p[0])):
				print("MISSING ", p[0])
			h.play(StringName(p[0]))
			h.anim.seek(lerpf(float(p[1]), float(p[2]), i / 7.0), true)
			h.anim.speed_scale = 0.0
			hs.append(h)
		for i in 5:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/strip_%s.png" % [out, p[0]])
		for h in hs:
			h.queue_free()
		await get_tree().process_frame
	get_tree().quit()
