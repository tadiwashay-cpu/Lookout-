class_name Services
extends RefCounted
## Buildings you can walk into. Each has a door on the street and a
## furnished, lit interior (built underground, out of sight) with staff
## going about their work: the mechanic under a car on the lift, the cook,
## the nurse at the desk, regulars at the tables, fans turning.

const DEPTH := -400.0

## kind -> {title, color}
const KINDS := {
	"repair": {"title": "AUTO REPAIR", "color": Color(1.0, 0.55, 0.1)},
	"clinic": {"title": "CITY CLINIC", "color": Color(0.3, 0.85, 0.75)},
	"diner": {"title": "HARBOR DINER", "color": Color(1.0, 0.85, 0.3)},
	"gym": {"title": "IRON GYM", "color": Color(0.85, 0.3, 0.3)},
	"bank": {"title": "FIRST HARBOR BANK", "color": Color(0.9, 0.85, 0.6)},
}

var w: Node3D
var doors: Dictionary = {}       # kind -> door position (street)
var _slot := 0


func _init(world: Node3D) -> void:
	w = world


## Pick real city buildings for each service and furnish them.
func build(city: City) -> void:
	var wanted := ["repair", "clinic", "diner", "gym", "bank"]
	var near := {"repair": Vector2(-140, 60), "clinic": Vector2(100, 60), "diner": Vector2(220, -60), "gym": Vector2(-20, 180), "bank": Vector2(40, -180)}
	var used: Array = []
	for kind: String in wanted:
		var best: Dictionary = {}
		var best_d := INF
		for b in city.buildings:
			if used.has(b) or float(b["height"]) < 8.0:
				continue
			var d := (b["rect"] as Rect2).get_center().distance_to(near[kind])
			if d < best_d:
				best_d = d
				best = b
		if best.is_empty():
			continue
		used.append(best)
		_place(kind, best)


func _place(kind: String, b: Dictionary) -> void:
	var door: Vector3 = b["door"]
	var face: Vector3 = b["face"]
	var info: Dictionary = KINDS[kind]
	doors[kind] = door
	# Street side: sign, lit doorway, awning.
	var yaw := atan2(face.x, face.z)
	var sign := Label3D.new()
	sign.text = info["title"]
	sign.font_size = 96
	sign.outline_size = 16
	sign.modulate = info["color"]
	sign.pixel_size = 0.012
	sign.position = door + Vector3.UP * 5.2 - face * 1.1
	sign.rotation.y = yaw
	w.add_child(sign)
	var frame := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(3.2, 3.4, 0.3)
	frame.mesh = fb
	frame.material_override = Mats.glow((info["color"] as Color).darkened(0.3), 1.2)
	frame.position = door + Vector3.UP * 1.7 - face * 1.25
	frame.rotation.y = yaw
	w.add_child(frame)
	if kind == "repair":
		var shutter := MeshInstance3D.new()
		shutter.mesh = Mats.prop("rollershutter_door")["mesh"]
		shutter.position = door - face * 1.15 + face.cross(Vector3.UP) * 5.0
		shutter.rotation.y = yaw
		w.add_child(shutter)
	var room := _interior(kind, info)
	var inside: Vector3 = room.get_meta(&"entry")
	var exit_spot: Vector3 = room.get_meta(&"exit")
	Door.make(w, door, "Enter " + str(info["title"]).capitalize(), func(p: Player) -> void: Door.travel(p, inside, PI))
	Door.make(room, exit_spot, "Leave", func(p: Player) -> void: Door.travel(p, door + face * 2.0, yaw))


func _interior(kind: String, info: Dictionary) -> Node3D:
	var room := Node3D.new()
	room.name = kind.capitalize() + "Interior"
	w.add_child(room)
	var o := Vector3(_slot * 60.0, DEPTH, 0)
	_slot += 1
	var size := Vector3(22, 6, 18)
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	room.add_child(body)
	var floor_tex: String = {"repair": "anti_slip_concrete", "clinic": "checkered_pavement_tiles", "diner": "checkered_pavement_tiles", "gym": "anti_slip_concrete", "bank": "checkered_pavement_tiles"}[kind]
	var wall_tex: String = {"repair": "concrete_block_wall", "clinic": "grey_plaster", "diner": "brick_4", "gym": "concrete_block_wall", "bank": "grey_plaster"}[kind]
	_slab(room, body, o + Vector3(0, -0.2, 0), Vector3(size.x, 0.4, size.z), Mats.pbr(floor_tex, 2.0))
	_slab(room, body, o + Vector3(0, size.y, 0), Vector3(size.x, 0.4, size.z), Mats.pbr("grey_plaster", 3.0, Color(0.9, 0.9, 0.9)))
	for wall in [[Vector3(0, size.y * 0.5, -size.z * 0.5), Vector3(size.x, size.y, 0.4)], [Vector3(0, size.y * 0.5, size.z * 0.5), Vector3(size.x, size.y, 0.4)],
			[Vector3(-size.x * 0.5, size.y * 0.5, 0), Vector3(0.4, size.y, size.z)], [Vector3(size.x * 0.5, size.y * 0.5, 0), Vector3(0.4, size.y, size.z)]]:
		_slab(room, body, o + wall[0], wall[1], Mats.pbr(wall_tex, 3.0))
	# Lights (warm, a little flicker in the workshop).
	for x in [-6.0, 0.0, 6.0]:
		var lamp := OmniLight3D.new()
		lamp.position = o + Vector3(x, size.y - 0.8, 0)
		lamp.omni_range = 12.0
		lamp.light_energy = 1.6
		lamp.light_color = Color(1.0, 0.92, 0.8)
		room.add_child(lamp)
		_prop(room, "hanging_industrial_lamp", o + Vector3(x, size.y - 1.4, 0), 0.0)
	var title := Label3D.new()
	title.text = info["title"]
	title.font_size = 80
	title.modulate = info["color"]
	title.position = o + Vector3(0, 4.2, -size.z * 0.5 + 0.3)
	room.add_child(title)
	room.set_meta(&"entry", o + Vector3(0, 0.3, size.z * 0.5 - 2.5))
	room.set_meta(&"exit", o + Vector3(0, 0.0, size.z * 0.5 - 1.0))
	match kind:
		"repair":
			_repair_bay(room, body, o)
		"clinic":
			_clinic(room, o)
		"diner":
			_diner(room, o)
		"gym":
			_gym(room, o)
		"bank":
			_bank(room, o)
	return room


func _slab(room: Node3D, body: StaticBody3D, center: Vector3, size: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = center
	room.add_child(mi)
	Mats.box_collider(body, center, size)


func _prop(room: Node3D, name: String, pos: Vector3, yaw: float, scale: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Mats.prop(name)["mesh"]
	mi.position = pos
	mi.rotation.y = yaw
	mi.scale = Vector3.ONE * scale
	room.add_child(mi)
	return mi


func _staff(room: Node3D, pos: Vector3, yaw: float, clip: StringName, model: String = "") -> Humanoid:
	var h := Humanoid.new()
	room.add_child(h)
	h.position = pos
	h.rotation.y = yaw
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	h.setup(model if model != "" else Humanoid.random_npc(rng), 1.75)
	h.play(clip)
	return h


func _fan(room: Node3D, pos: Vector3) -> void:
	var fan := _prop(room, "ceiling_fan", pos, 0.0)
	var tw := fan.create_tween().set_loops()
	tw.tween_property(fan, "rotation:y", TAU, 1.2).from(0.0)


# ------------------------------------------------------------------ rooms

func _repair_bay(room: Node3D, body: StaticBody3D, o: Vector3) -> void:
	# A car up on the lift going up and down, the mechanic working under it.
	var lift := Node3D.new()
	lift.position = o + Vector3(-4, 0, -2)
	room.add_child(lift)
	var model := (load("res://assets/vehicles/sedan.glb") as PackedScene).instantiate() as Node3D
	model.rotation.y = PI * 0.5
	lift.add_child(model)
	var tw := lift.create_tween().set_loops()
	tw.tween_property(lift, "position:y", o.y + 1.6, 4.0).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(5.0)
	tw.tween_property(lift, "position:y", o.y, 4.0).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(3.0)
	for x in [-6.2, -1.8]:
		_slab(room, body, o + Vector3(x, 1.2, -2), Vector3(0.4, 2.4, 0.4), Mats.flat(Color(0.8, 0.6, 0.1), 0.5, 0.5))
	_staff(room, o + Vector3(-4, 0, 0.2), PI, &"Fixing_Kneeling")
	_staff(room, o + Vector3(5, 0, -5.5), 0.3, &"Idle_TalkingPhone")
	_prop(room, "metal_tool_chest", o + Vector3(6, 0, -7.5), 0.0)
	_prop(room, "drill_press_01", o + Vector3(8.5, 0, -7.5), 0.0)
	_prop(room, "steel_frame_shelves_01", o + Vector3(-9.5, 0, -7.5), 0.0)
	_prop(room, "industrial_storage_cart", o + Vector3(2.5, 0, -6), 0.4)
	_prop(room, "barrel_01", o + Vector3(9.5, 0, 6), 0.0)
	_prop(room, "wetfloorsign_01", o + Vector3(1, 0, 4), 0.6)
	Counter.make(room, o + Vector3(5, 0, 2), "Talk to the mechanic", "repair")


func _clinic(room: Node3D, o: Vector3) -> void:
	_prop(room, "metal_office_desk", o + Vector3(0, 0, -4), 0.0)
	_staff(room, o + Vector3(0, 0, -5.4), 0.0, &"Idle_Talking")
	for i in 4:
		_prop(room, "bar_chair_round_01", o + Vector3(-8 + i * 1.6, 0, 5), PI)
	_staff(room, o + Vector3(-6.4, 0, 5.2), PI, &"Sitting_Idle")
	_prop(room, "shelf_01", o + Vector3(9.5, 0, -6), -PI * 0.5)
	_fan(room, o + Vector3(0, 5.6, 2))
	Counter.make(room, o + Vector3(0, 0, -2.4), "See the doctor", "clinic")


func _diner(room: Node3D, o: Vector3) -> void:
	_prop(room, "coffeecart_01", o + Vector3(-7, 0, -6), 0.0)
	_prop(room, "cashregister_01", o + Vector3(0, 1.0, -5.6), 0.0)
	_prop(room, "metal_office_desk", o + Vector3(0, 0, -5.5), 0.0)
	_staff(room, o + Vector3(1.5, 0, -7), 0.0, &"Interact")
	for i in 3:
		var p := o + Vector3(-6 + i * 6, 0, 2)
		_prop(room, "woodentable_02", p, 0.0, 1.4)
		_prop(room, "bar_chair_round_01", p + Vector3(1.0, 0, 0), -PI * 0.5)
		_prop(room, "bar_chair_round_01", p + Vector3(-1.0, 0, 0), PI * 0.5)
	_staff(room, o + Vector3(-5.0, 0, 2), -PI * 0.5, &"Sitting_Talking")
	_staff(room, o + Vector3(7.0, 0, 2), PI * 0.5, &"Sitting_Idle")
	_prop(room, "sofa_01", o + Vector3(9, 0, 6), -PI * 0.5)
	_fan(room, o + Vector3(-4, 5.6, 2))
	_fan(room, o + Vector3(4, 5.6, 2))
	Counter.make(room, o + Vector3(0, 0, -3.8), "Order food", "diner")


func _gym(room: Node3D, o: Vector3) -> void:
	_staff(room, o + Vector3(-4, 0, -2), 0.6, &"Punch_Jab")
	_staff(room, o + Vector3(4, 0, -2), -0.6, &"Melee_Hook")
	_staff(room, o + Vector3(0, 0, -6), 0.0, &"Idle_FoldArms")
	_prop(room, "barrel_01", o + Vector3(-9, 0, -7), 0.0)
	Counter.make(room, o + Vector3(0, 0, -4.4), "Talk to the coach", "gym")


func _bank(room: Node3D, o: Vector3) -> void:
	_prop(room, "metal_office_desk", o + Vector3(-3, 0, -4), 0.0)
	_prop(room, "metal_office_desk", o + Vector3(3, 0, -4), 0.0)
	_staff(room, o + Vector3(-3, 0, -5.4), 0.0, &"Idle_Talking")
	_staff(room, o + Vector3(3, 0, -5.4), 0.0, &"Idle_TalkingPhone")
	_staff(room, o + Vector3(8, 0, 4), -PI * 0.5, &"Idle_FoldArms")
	Counter.make(room, o + Vector3(0, 0, -2.4), "Talk to the teller", "bank")
