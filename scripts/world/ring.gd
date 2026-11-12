class_name Ring
extends Node3D
## The Clean Hands ring in the harbour yard: raised canvas, corner posts,
## three ropes a side (they hold you in), floodlights and a crowd.

const HALF := 5.5
const FLOOR := 1.1

var crowd: Array[Humanoid] = []


func build() -> void:
	var body := StaticBody3D.new()
	body.collision_layer = Game.L_WORLD
	add_child(body)
	var canvas := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = Vector3(HALF * 2 + 1.0, FLOOR, HALF * 2 + 1.0)
	canvas.mesh = b
	var m := Mats.pbr("anti_slip_concrete", 3.0, Color(0.55, 0.12, 0.1))
	canvas.material_override = m
	canvas.position = Vector3.UP * FLOOR * 0.5
	add_child(canvas)
	Mats.box_collider(body, canvas.position, b.size)
	# Steps up on one side.
	for i in 3:
		Mats.box_collider(body, Vector3(0, FLOOR * (i + 1) / 4.0 * 0.5, HALF + 1.5 + (2 - i) * 0.5), Vector3(2.0, FLOOR * (i + 1) / 4.0, 0.5))
	var post_mat := Mats.flat(Color(0.75, 0.75, 0.78), 0.3, 0.8)
	var rope_mat := Mats.flat(Color(0.8, 0.08, 0.06), 0.6)
	for cx in [-1.0, 1.0]:
		for cz in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.12
			cyl.bottom_radius = 0.12
			cyl.height = 1.6
			post.mesh = cyl
			post.material_override = post_mat
			post.position = Vector3(cx * HALF, FLOOR + 0.8, cz * HALF)
			add_child(post)
	for k in 3:
		var y := FLOOR + 0.45 + k * 0.42
		for side in [[Vector3(0, y, -HALF), Vector3(HALF * 2, 0.06, 0.06)], [Vector3(0, y, HALF), Vector3(HALF * 2, 0.06, 0.06)],
				[Vector3(-HALF, y, 0), Vector3(0.06, 0.06, HALF * 2)], [Vector3(HALF, y, 0), Vector3(0.06, 0.06, HALF * 2)]]:
			var rope := MeshInstance3D.new()
			var rb := BoxMesh.new()
			rb.size = side[1]
			rope.mesh = rb
			rope.material_override = rope_mat
			rope.position = side[0]
			add_child(rope)
	# Invisible walls at the ropes.
	for wall in [[Vector3(0, FLOOR + 1.5, -HALF - 0.2), Vector3(HALF * 2, 3.0, 0.3)], [Vector3(0, FLOOR + 1.5, HALF + 0.2), Vector3(HALF * 2, 3.0, 0.3)],
			[Vector3(-HALF - 0.2, FLOOR + 1.5, 0), Vector3(0.3, 3.0, HALF * 2)], [Vector3(HALF + 0.2, FLOOR + 1.5, 0), Vector3(0.3, 3.0, HALF * 2)]]:
		var wb := StaticBody3D.new()
		wb.collision_layer = Game.L_BARRIER
		add_child(wb)
		Mats.box_collider(wb, wall[0], wall[1])
	# Floodlights on poles.
	for a in 4:
		var ang := a * TAU / 4.0 + PI / 4.0
		var p := Vector3(cos(ang), 0, sin(ang)) * (HALF + 7.0)
		var pole := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.25, 9.0, 0.25)
		pole.mesh = pb
		pole.material_override = Mats.flat(Color(0.15, 0.15, 0.16), 0.4, 0.8)
		pole.position = p + Vector3.UP * 4.5
		add_child(pole)
		var l := SpotLight3D.new()
		l.position = p + Vector3.UP * 9.0
		add_child(l)
		l.look_at(global_position + Vector3.UP * FLOOR, Vector3.UP)
		l.spot_range = 30.0
		l.spot_angle = 35.0
		l.light_energy = 4.0
		l.shadow_enabled = Game.quality >= 2
	# The crowd.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var clips := [&"Dance", &"Yes", &"Idle_Talking", &"Idle_FoldArms", &"Punch_Enter", &"Idle_No"]
	for i in 18:
		var ang := i * TAU / 18.0 + rng.randf_range(-0.1, 0.1)
		var r := HALF + rng.randf_range(3.0, 5.5)
		var h := Humanoid.new()
		add_child(h)
		h.position = Vector3(cos(ang) * r, 0, sin(ang) * r)
		h.rotation.y = atan2(-h.position.x, -h.position.z)
		h.setup(Humanoid.random_npc(rng), rng.randf_range(1.65, 1.85))
		h.play(clips[rng.randi() % clips.size()], 0.0, rng.randf_range(0.85, 1.15))
		crowd.append(h)


func cheer() -> void:
	for h in crowd:
		h.one_shot(&"Yes" if randf() < 0.5 else &"Dance", 1.0)
	Sfx.play("crowd", global_position + Vector3.UP * 2.0, 0.0)


## Corner `i` (0..7) inside the ropes, world space.
func corner(i: int) -> Vector3:
	var ang := i * TAU / 8.0 + PI / 8.0
	return global_position + Vector3(cos(ang) * (HALF - 1.4), FLOOR + 0.2, sin(ang) * (HALF - 1.4))
