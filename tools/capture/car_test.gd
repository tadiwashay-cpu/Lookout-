extends Node3D

var car: Car
var t := 0.0

func _ready() -> void:
	var ground := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(400, 1, 400)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = -0.5
	ground.add_child(col)
	add_child(ground)
	car = Car.new()
	car.car_id = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "sport"
	car.position = Vector3(0, 0.5, 0)
	car.ai_enabled = true
	add_child(car)

func _physics_process(delta: float) -> void:
	t += delta
	car.in_throttle = 1.0 if t > 1.0 and t < 6.0 else 0.0
	car.in_steer = 0.6 if t > 4.0 else 0.0
	car.in_brake = 1.0 if t > 6.0 else 0.0
	if int(t * 10) % 5 == 0 and fmod(t, 0.5) < delta:
		var contacts := []
		for w in car.find_children("*", "VehicleWheel3D", false, false):
			var vw := w as VehicleWheel3D
			contacts.append("%s:%s r=%.2f y=%.2f ef=%.0f" % [vw.name, vw.is_in_contact(), vw.wheel_radius, vw.position.y, vw.engine_force])
		print("t=%.1f pos=%s v=%.1f kmh sleeping=%s %s" % [t, car.global_position, car.speed_kmh(), car.sleeping, contacts])
	if t > 8.0:
		get_tree().quit()
