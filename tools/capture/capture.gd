extends Node
## Dev tool: loads the story world off-screen-ish and saves close-up
## screenshots so we can check ground contact, poses and visuals.
##   godot --path . --rendering-driver opengl3 res://tools/capture/capture.tscn -- OUT_DIR
## Not part of the game (excluded from exports).

var out_dir := "/tmp"
var world: World


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	Session.mode = Session.MODE_STORY
	world = load(Session.WORLD_SCENE).instantiate() as World
	add_child(world)
	await _frames(30)
	if world.day_night:
		world.day_night.time_of_day = 0.5
		world.day_night.call(&"_apply")
	await _frames(90)   # let animations and physics settle
	_measure()
	var cam := Camera3D.new()
	cam.fov = 50.0
	add_child(cam)
	cam.make_current()
	var p := world.player
	# 1. Player feet, side view, low.
	await _shot(cam, p.global_position + p.global_basis.x * 2.2 + Vector3.UP * 0.5, p.global_position + Vector3.UP * 0.4, "player_feet")
	# 2. Player full body.
	await _shot(cam, p.global_position + Vector3(2.5, 1.4, 3.5), p.global_position + Vector3.UP * 0.9, "player_body")
	# 3. Nearest parked car, side view at wheel height.
	var car: DrivableCar = null
	var best := INF
	for node in get_tree().get_nodes_in_group(&"vehicles"):
		var c := node as DrivableCar
		var d := c.global_position.distance_to(p.global_position)
		if d < best:
			best = d
			car = c
	if car:
		await _shot(cam, car.global_position + car.global_basis.x * 4.5 + Vector3.UP * 0.35, car.global_position + Vector3.UP * 0.3, "car_side")
		await _shot(cam, car.global_position + car.global_basis.x * 2.0 + car.global_basis.z * 1.4 + Vector3.UP * 0.25, car.global_position + car.global_basis.z * 1.4 + Vector3.UP * 0.2, "car_wheel")
	# 4. Nearest pedestrian.
	var ped: Node3D = null
	best = INF
	for node in get_tree().get_nodes_in_group(&"civilians"):
		var n := node as Node3D
		var d := n.global_position.distance_to(p.global_position)
		if d < best:
			best = d
			ped = n
	if ped:
		await _shot(cam, ped.global_position + Vector3(2.0, 0.6, 2.0), ped.global_position + Vector3.UP * 0.6, "pedestrian")
	# 5. Wide street view (overall look).
	await _shot(cam, p.global_position + Vector3(0, 6, 14), p.global_position + Vector3(0, 1, -10), "street")
	# 6. Night drive: close chase + hood views from the real car cameras.
	if car:
		world.day_night.time_of_day = 0.0
		world.day_night.call(&"_apply")
		car.enter(p)
		for view in [DrivableCar.CamView.CLOSE, DrivableCar.CamView.HOOD]:
			DrivableCar.cam_view = view
			await _frames(30)
			get_viewport().get_texture().get_image().save_png("%s/drive_%s.png" % [out_dir, DrivableCar.CamView.keys()[view].to_lower()])
			print("SHOT drive ", view)
	print("CAPTURE_DONE")
	get_tree().quit()


func _ground_y(at: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(at + Vector3.UP * 3.0, at + Vector3.DOWN * 5.0, 1)
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	return (hit["position"] as Vector3).y if not hit.is_empty() else NAN


## Numbers instead of eyeballing: tyre bottom vs road, feet vs ground.
func _measure() -> void:
	var cars := get_tree().get_nodes_in_group(&"vehicles")
	var n := 0
	for node in cars:
		var car := node as DrivableCar
		if n >= 6:
			break
		n += 1
		var line := "CAR %s" % car.vehicle_id
		for w in car.find_children("Wheel_*", "VehicleWheel3D", true, false):
			var wheel := w as VehicleWheel3D
			var g := _ground_y(wheel.global_position)
			var mesh := wheel.get_child(0) as MeshInstance3D
			var vis_bottom := INF
			if mesh:
				var aabb := mesh.global_transform * mesh.get_aabb()
				vis_bottom = aabb.position.y
			line += "  %s phys=%.3f vis=%.3f contact=%s" % [wheel.name, wheel.global_position.y - wheel.wheel_radius - g, vis_bottom - g, wheel.is_in_contact()]
		print(line)
	var people: Array = [world.player] + get_tree().get_nodes_in_group(&"civilians").slice(0, 5)
	for node in people:
		var body := node as Node3D
		var rig := body.find_children("*", "CharacterRig", true, false)
		if rig.is_empty():
			continue
		var r := rig[0] as CharacterRig
		if r.skeleton == null:
			continue
		var g := _ground_y(body.global_position)
		var low := INF
		for i in r.skeleton.get_bone_count():
			var bn := r.skeleton.get_bone_name(i)
			if bn.ends_with("ToeBase") or bn.ends_with("Toes") or bn.ends_with("Foot"):
				low = minf(low, (r.skeleton.global_transform * r.skeleton.get_bone_global_pose(i).origin).y)
		var model := (r.get_child(0) as Node3D).get_child(0) as Node3D
		print("   model_y=%.3f base=%.3f lift=%.3f scale=%.3f feet=%d grounded=%s" % [model.position.y, r._model_base_y, r._lift, model.scale.y, r._feet.size(), r.grounded])
		print("PERSON %s/%s lowest_foot_bone=%.3f body_y=%.3f anim=%s" % [body.name, r._model_key.get_file(), low - g, body.global_position.y - g, r.anim.current_animation if r.anim else "?"])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(cam: Camera3D, from: Vector3, at: Vector3, name: String) -> void:
	cam.global_position = from
	cam.look_at(at, Vector3.UP)
	await _frames(6)
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out_dir, name])
	print("SHOT ", name, " ", from)
