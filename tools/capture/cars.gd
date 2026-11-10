extends Node3D
## Dev tool: real game cars on a test plane, side views + wheel contact numbers.
##   godot --path . --rendering-driver opengl3 res://tools/capture/cars.tscn -- OUT_DIR id,id,...

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir: String = args[0] if args.size() > 0 else "/tmp"
	var ids: PackedStringArray = (args[1] if args.size() > 1 else "sport").split(",")
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.8, 0.6, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.6, 0.66)
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.75)
	add_child(env)
	var ground := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -0.5
	ground.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	mesh.mesh = plane
	ground.add_child(mesh)
	add_child(ground)
	var cars: Array[DrivableCar] = []
	for i in ids.size():
		var car := preload("res://scenes/vehicles/car.tscn").instantiate() as DrivableCar
		car.vehicle_id = ids[i]
		car.paint = VehicleCatalog.get_data(ids[i]).get("paint", Color(0, 0, 0, 0))
		car.position = Vector3(i * 6.0, 0.6, 0)
		add_child(car)
		cars.append(car)
	for k in 120:
		await get_tree().physics_frame
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 35.0
	for car in cars:
		var line := "CAR %s" % car.vehicle_id
		for w in car.find_children("Wheel_*", "VehicleWheel3D", true, false):
			var wheel := w as VehicleWheel3D
			line += " %s=%.3f" % [wheel.name, wheel.global_position.y - wheel.wheel_radius]
		print(line)
		cam.global_position = car.global_position + car.global_basis.x * 7.5 + Vector3.UP * 0.8
		cam.look_at(car.global_position + Vector3.UP * 0.6)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/car_%s.png" % [out_dir, car.vehicle_id])
		cam.global_position = car.global_position + car.global_basis.z * 5.0 + car.global_basis.x * 4.0 + Vector3.UP * 1.6
		cam.look_at(car.global_position + Vector3.UP * 0.5)
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/car_%s_front.png" % [out_dir, car.vehicle_id])
	get_tree().quit()
