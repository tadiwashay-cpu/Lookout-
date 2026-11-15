class_name Traffic
extends Node3D
## Free-roam traffic: ordinary cars cruising the grand loop (city, harbour,
## coast highway, suburbs, forest) in both directions, keeping to their
## lane. They only exist near you, brake for whatever is in front of them,
## honk and pull up when hit. They are moved along the road rather than
## simulated (no wheel physics), so a street full of them costs almost
## nothing on a phone.

const LANE := 3.3                 # metres right of the centre line
const NEAR := 95.0                # never appear closer than this
const FAR := 330.0                # disappear beyond this

var world: Node3D
var loop: Array[Vector3] = []
var cars: Array[TrafficCar] = []
var max_cars := 8
var _tick := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	var roads: Roads = world.get("roads")
	loop = roads.route(Layout.RACE_LOOP)
	max_cars = [4, 6, 8, 10][clampi(Game.quality, 0, 3)]


func _physics_process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or loop.size() < 8:
		return
	_tick = 0.5
	var player: Player = world.get("player")
	if player == null:
		return
	var focus := player.global_position
	for i in range(cars.size() - 1, -1, -1):
		var c := cars[i]
		if not is_instance_valid(c) or c.global_position.distance_to(focus) > FAR:
			if is_instance_valid(c):
				c.queue_free()
			cars.remove_at(i)
	if cars.size() >= max_cars or focus.y < -100.0:
		return
	# The stretch of the loop nearest to you; nothing spawns if it's far.
	var near_i := 0
	var near_d := INF
	for i in range(0, loop.size(), 2):
		var d := loop[i].distance_squared_to(focus)
		if d < near_d:
			near_d = d
			near_i = i
	if near_d > 280.0 * 280.0:
		return
	for attempt in 3:
		var at := posmod(near_i + _rng.randi_range(14, 36) * (1 if _rng.randf() < 0.5 else -1), loop.size())
		var p := loop[at]
		if p.distance_to(focus) < NEAR:
			continue
		var clear := true
		for c in cars:
			if c.global_position.distance_to(p) < 30.0:
				clear = false
		if not clear:
			continue
		var car := TrafficCar.new()
		car.traffic = self
		car.s = float(at)
		car.dir = 1 if _rng.randf() < 0.5 else -1
		car.car_id = CarCatalog.STREET_CARS[_rng.randi() % CarCatalog.STREET_CARS.size()]
		car.paint = CarCatalog.PAINTS[_rng.randi() % CarCatalog.PAINTS.size()]
		car.cruise = _rng.randf_range(11.0, 16.0)
		world.add_child(car)
		car.place()
		cars.append(car)
		break


## Point and forward direction at fractional index `s`, in lane.
func sample(s: float, dir: int) -> Array:
	var n := loop.size()
	var i := posmod(int(floor(s)), n)
	var j := (i + 1) % n
	var a := loop[i]
	var b := loop[j]
	var fwd := (b - a)
	if fwd.length() < 0.01:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized() * float(dir)
	var p := a.lerp(b, s - floor(s))
	var flat := Vector3(fwd.x, 0, fwd.z).normalized()
	return [p + flat.cross(Vector3.UP) * LANE, fwd, a.distance_to(b)]


class TrafficCar:
	extends AnimatableBody3D
	var traffic: Traffic
	var car_id := "sedan"
	var paint := Color.WHITE
	var s := 0.0                  # position on the loop (fractional index)
	var dir := 1
	var cruise := 13.0
	var speed := 0.0
	var _halt := 0.0              # seconds left pulled up after a hit
	var _wrecked := false
	var _honk := 0.0
	var _fwd := Vector3.FORWARD
	var _look_tick := randf() * 0.15
	var _is_blocked := false

	func _ready() -> void:
		add_to_group(&"traffic")
		collision_layer = Game.L_CARS
		collision_mask = 0
		sync_to_physics = false
		var holder := Node3D.new()
		holder.rotation.y = PI          # the pack faces -Z
		add_child(holder)
		var model := (load(CarCatalog.data(car_id)["model"]) as PackedScene).instantiate() as Node3D
		holder.add_child(model)
		var body_mesh: MeshInstance3D = null
		for node in model.find_children("*", "MeshInstance3D", true, false):
			var mi := node as MeshInstance3D
			mi.visibility_range_end = 260.0
			if not mi.name.begins_with("Wheel_") and (body_mesh == null or mi.name == "Body"):
				body_mesh = mi
		if body_mesh:
			var box := body_mesh.get_aabb()
			var xf := _rel(body_mesh)
			var shape := BoxShape3D.new()
			var size := (xf.basis.get_scale() * box.size).abs()
			shape.size = Vector3(size.x * 0.9, size.y * 0.8, size.z * 0.95)
			var col := CollisionShape3D.new()
			col.shape = shape
			add_child(col)
			col.position = xf * box.get_center()
			Car.paint_mesh(body_mesh, paint)
		speed = cruise

	func _rel(node: Node3D) -> Transform3D:
		var xf := node.transform
		var p := node.get_parent()
		while p and p != self:
			if p is Node3D:
				xf = (p as Node3D).transform * xf
			p = p.get_parent()
		return xf

	func place() -> void:
		var smp := traffic.sample(s, dir)
		_fwd = smp[1]
		global_transform = Transform3D(Basis.looking_at(-_fwd, Vector3.UP), smp[0])
		reset_physics_interpolation()

	func _physics_process(delta: float) -> void:
		_halt = maxf(_halt - delta, 0.0)
		_honk = maxf(_honk - delta, 0.0)
		var want := 0.0 if (_halt > 0.0 or _wrecked) else cruise
		_look_tick -= delta
		if _look_tick <= 0.0:            # look ahead ~7 times a second, not 60
			_look_tick = 0.15
			_is_blocked = want > 0.0 and _blocked()
		if want > 0.0 and _is_blocked:
			want = 0.0
			if speed < 1.0 and _honk <= 0.0:
				_honk = randf_range(3.0, 6.0)
				Sfx.play("horn", global_position, -6.0, randf_range(0.9, 1.1))
		speed = move_toward(speed, want, delta * (14.0 if want < speed else 5.0))
		if speed < 0.02:
			return
		var smp := traffic.sample(s, dir)
		s += float(dir) * speed * delta / maxf(float(smp[2]), 0.5)
		s = fposmod(s, float(traffic.loop.size()))
		smp = traffic.sample(s, dir)
		# Turn through bends and junctions instead of snapping.
		_fwd = _fwd.slerp(smp[1], clampf(delta * 5.0, 0.0, 1.0)).normalized()
		global_transform = Transform3D(Basis.looking_at(-_fwd, Vector3.UP), smp[0])

	## Something in our lane just ahead (Nash, a driven car, other traffic)?
	func _blocked() -> bool:
		var reach := 7.0 + speed * 0.9
		for group: StringName in [&"player", &"cars", &"traffic"]:
			for node in get_tree().get_nodes_in_group(group):
				var n := node as Node3D
				if n == self or (n is Player and (n as Player).in_car):
					continue
				var off := n.global_position - global_position
				if absf(off.y) > 4.0:
					continue
				var ahead := off.dot(_fwd)
				if ahead < 1.0 or ahead > reach:
					continue
				if absf(off.dot(_fwd.cross(Vector3.UP))) < 2.2:
					return true
		return false

	## Called by a Car that ran into us.
	func traffic_hit(_by: Car, dv: float) -> void:
		if dv < 2.0:
			return
		_halt = 5.0
		speed = 0.0
		if _honk <= 0.0:
			_honk = 2.0
			Sfx.play("horn", global_position, -3.0)
		if dv > 12.0 and not _wrecked:
			_wrecked = true
			Fx.plume(self, Vector3(0, 0.9, 1.6), false)
