extends Node3D
## Dev tool: every character model side by side, same clip & time, rendered
## in-engine (this is what the game shows, not a Blender approximation).
##   godot --path . --rendering-driver opengl3 res://tools/capture/lineup.tscn -- OUT_DIR CLIP TIME

const MODELS := ["x_bot", "y_bot", "npc", "civ_m_casual", "civ_m_suit", "civ_f_casual", "civ_f_formal", "civ_m_swat"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "/tmp"
	var clips: PackedStringArray = (args[1] if args.size() > 1 else "idle_unarmed").split(",")
	var t: float = float(args[2]) if args.size() > 2 else 0.4
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.5, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.34, 0.37)
	env.environment.ambient_light_color = Color(0.6, 0.62, 0.66)
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40, 10)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40.0
	for clip in clips:
		var rigs: Array[CharacterRig] = []
		for i in MODELS.size():
			var holder := Node3D.new()
			holder.position = Vector3((i - MODELS.size() / 2.0) * 1.3, 0, 0)
			add_child(holder)
			var rig := CharacterRig.new()
			rig.armed = clip.begins_with("pistol") or clip.begins_with("shotgun")
			holder.add_child(rig)
			rig.setup(MODELS[i], 1.68 if MODELS[i].begins_with("civ_f") else 1.8)
			if clip.begins_with("pistol"):
				rig.set_weapon("glock17")
			elif clip.begins_with("shotgun"):
				rig.set_weapon("m4a1")
			rig.rotation.y = PI   # face the camera
			if rig.anim and rig.anim.has_animation(clip):
				rig.anim.play(clip)
				rig.anim.seek(t, true)
				rig.anim.speed_scale = 0.0
			rigs.append(rig)
		for k in 10:
			await get_tree().physics_frame
		cam.position = Vector3(0, 1.0, 7.5)
		cam.look_at(Vector3(0, 0.9, 0))
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/lineup_%s.png" % [out_dir, clip])
		print("LINEUP ", clip)
		for r in rigs:
			r.get_parent().queue_free()
		await get_tree().process_frame
	get_tree().quit()
