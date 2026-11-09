class_name WorldCity
extends RefCounted
## Brooklyn-style city: brownstone rows (west), brick tenements and
## warehouses (centre/east, DUMBO-like by the water), stepped towers
## downtown (north-east), a park, the bank, the police precinct and the
## crew's HQ warehouse. Everything goes through the MeshBatcher.

const BLOCKS_X := 6
const BLOCKS_Z := 7
const BLOCK_W := 72.0
const BLOCK_D := 48.0
const STREET := 14.0
const PITCH_X := BLOCK_W + STREET
const PITCH_Z := BLOCK_D + STREET
const HALF_X := (BLOCKS_X * PITCH_X + STREET) * 0.5   # 265
const HALF_Z := (BLOCKS_Z * PITCH_Z + STREET) * 0.5   # 224
const SIDEWALK := 3.5

const HQ_BLOCK := Vector2i(1, 6)
const BANK_BLOCK := Vector2i(3, 3)
const PRECINCT_BLOCK := Vector2i(2, 5)
const PARK_BLOCK := Vector2i(3, 5)

var w: World
var b: MeshBatcher
var rng: RandomNumberGenerator


func _init(world: World) -> void:
	w = world
	b = world.batcher
	rng = world.rng


static func block_center(ix: int, iz: int) -> Vector3:
	return Vector3(-HALF_X + STREET + BLOCK_W * 0.5 + ix * PITCH_X, 0.0, -HALF_Z + STREET + BLOCK_D * 0.5 + iz * PITCH_Z)


static func street_x(i: int) -> float:
	return -HALF_X + STREET * 0.5 + i * PITCH_X


static func street_z(i: int) -> float:
	return -HALF_Z + STREET * 0.5 + i * PITCH_Z


func build() -> void:
	for ix in BLOCKS_X:
		for iz in BLOCKS_Z:
			var c := block_center(ix, iz)
			b.box(Vector3(BLOCK_W, 0.12, BLOCK_D), c + Vector3(0, 0.06, 0), "sidewalk")
			var cell := Vector2i(ix, iz)
			if cell == HQ_BLOCK:
				_hq(c)
			elif cell == BANK_BLOCK:
				_bank(c)
			elif cell == PRECINCT_BLOCK:
				_precinct(c)
			elif cell == PARK_BLOCK:
				_park(c)
			elif ix >= 4 and iz <= 1:
				_downtown(c)
			elif ix <= 1:
				_brownstones(c)
			elif ix == BLOCKS_X - 1:
				_warehouses(c)
			else:
				_tenements(c)
			_street_furniture(c, ix <= 1)
	_street_lines()
	_register_map()


# ------------------------------------------------------------- block types

func _brownstones(c: Vector3) -> void:
	var styles := ["brownstone", "brick_red", "limestone", "brownstone", "painted"]
	for side: float in [-1.0, 1.0]:
		var face_z := c.z + side * (BLOCK_D * 0.5 - SIDEWALK)
		var depth := 14.0
		var x := c.x - BLOCK_W * 0.5 + 2.0
		while x < c.x + BLOCK_W * 0.5 - 6.0:
			var width := 6.5
			var height := rng.randf_range(12.5, 15.0)
			var style: String = styles[rng.randi() % styles.size()]
			var center := Vector3(x + width * 0.5, height * 0.5, face_z - side * depth * 0.5)
			b.box(Vector3(width - 0.05, height, depth), center, style)
			b.box(Vector3(width, 0.7, depth + 0.5), Vector3(center.x, height - 0.2, center.z), "trim", false)   # cornice
			# Stoop: steps up to the parlour floor, on the sidewalk.
			b.box(Vector3(2.0, 1.5, 2.6), Vector3(center.x + 1.5, 0.75, face_z + side * 1.3), "stone")
			x += width
		w.add_region_point("city", Vector3(c.x, 0.2, face_z + side * 6.0))


func _tenements(c: Vector3) -> void:
	if rng.randf() < 0.2:
		_warehouse_building(c, Vector3(BLOCK_W - 8.0, rng.randf_range(16.0, 24.0), BLOCK_D - 8.0))
		return
	var styles := ["brick_red", "brick_dark", "brownstone", "limestone"]
	for side: float in [-1.0, 1.0]:
		var face_z := c.z + side * (BLOCK_D * 0.5 - SIDEWALK)
		var x := c.x - BLOCK_W * 0.5 + 2.0
		while x < c.x + BLOCK_W * 0.5 - 8.0:
			var width := minf(rng.randf_range(10.0, 22.0), c.x + BLOCK_W * 0.5 - 2.0 - x)
			var floors := rng.randi_range(5, 8)
			var height := 4.0 + floors * 3.2
			var depth := rng.randf_range(15.0, 19.0)
			var style: String = styles[rng.randi() % styles.size()]
			var center := Vector3(x + width * 0.5, height * 0.5, face_z - side * depth * 0.5)
			b.box(Vector3(width - 0.1, height, depth), center, style)
			b.box(Vector3(width, 0.6, depth + 0.4), Vector3(center.x, height - 0.1, center.z), "trim", false)
			if rng.randf() < 0.35:
				_water_tank(Vector3(center.x, height, center.z))
			x += width
	w.add_region_point("city", c + Vector3(0, 0.2, BLOCK_D * 0.5 + STREET * 0.5))


func _warehouses(c: Vector3) -> void:
	_warehouse_building(c + Vector3(0, 0, -BLOCK_D * 0.22), Vector3(BLOCK_W - 8.0, rng.randf_range(14.0, 22.0), BLOCK_D * 0.45))
	_warehouse_building(c + Vector3(0, 0, BLOCK_D * 0.25), Vector3(BLOCK_W - 8.0, rng.randf_range(10.0, 18.0), BLOCK_D * 0.4))


func _warehouse_building(center: Vector3, size: Vector3) -> void:
	b.box(size, Vector3(center.x, size.y * 0.5, center.z), "brick_dark")
	b.box(Vector3(size.x + 0.4, 0.8, size.z + 0.4), Vector3(center.x, size.y, center.z), "trim", false)
	if rng.randf() < 0.5:
		_water_tank(Vector3(center.x + rng.randf_range(-8, 8), size.y, center.z))


func _downtown(c: Vector3) -> void:
	var count := 1 if rng.randf() < 0.5 else 2
	for i in count:
		var fx := BLOCK_W * (0.8 if count == 1 else 0.42)
		var fz := BLOCK_D * 0.75
		var offset_x := 0.0 if count == 1 else (i - 0.5) * BLOCK_W * 0.5
		var height := rng.randf_range(60.0, 145.0)
		var style := "glass_tower" if rng.randf() < 0.6 else "stone_tower"
		var base := Vector3(c.x + offset_x, 0.0, c.z)
		# Setbacks: three stacked, shrinking volumes (classic NYC zoning silhouette).
		var y := 0.0
		var stages := [0.45, 0.35, 0.2]
		var scale := 1.0
		for stage: float in stages:
			var h := height * stage
			b.box(Vector3(fx * scale, h, fz * scale), base + Vector3(0, y + h * 0.5, 0), style)
			y += h
			scale *= 0.78
		b.box(Vector3(2.0, 12.0, 2.0), base + Vector3(0, y + 6.0, 0), "metal", false)   # mast
	w.add_region_point("city", c + Vector3(0, 0.2, BLOCK_D * 0.5 + STREET * 0.5))


func _bank(c: Vector3) -> void:
	var size := Vector3(50.0, 16.0, 26.0)
	var front_z := c.z + BLOCK_D * 0.5 - SIDEWALK - 6.0
	var center := Vector3(c.x, size.y * 0.5 + 1.2, front_z - size.z * 0.5)
	b.box(Vector3(size.x + 6.0, 1.2, size.z + 10.0), Vector3(c.x, 0.6, center.z + 2.0), "stone")   # plinth & steps
	b.box(size, center, "limestone")
	for i in 8:
		var x := c.x - 21.0 + i * 6.0
		b.box(Vector3(1.4, 12.5, 1.4), Vector3(x, 1.2 + 6.25, front_z + 2.5), "stone")
	var pediment := PrismMesh.new()
	pediment.size = Vector3(48.0, 5.0, 6.0)
	b.mesh(pediment, Transform3D(Basis(), Vector3(c.x, 1.2 + 12.5 + 2.5, front_z + 2.5)), "stone")
	w.add_label("FIRST HARBOR BANK", Vector3(c.x, 15.0, front_z + 5.6), 96, Color(0.9, 0.85, 0.7))
	w.bank_position = Vector3(c.x, 1.4, front_z + 7.0)


func _precinct(c: Vector3) -> void:
	var front_z := c.z - BLOCK_D * 0.5 + SIDEWALK
	var center := Vector3(c.x - 8.0, 7.0, front_z + 11.0)
	b.box(Vector3(40.0, 14.0, 20.0), center, "brick_red")
	b.box(Vector3(40.4, 0.7, 20.4), center + Vector3(0, 6.8, 0), "trim", false)
	w.add_label("84TH PRECINCT", Vector3(center.x, 11.5, front_z - 0.2), 80, Color(0.75, 0.85, 1.0))
	w.precinct_position = Vector3(c.x, 0.3, front_z - STREET * 0.5)


func _park(c: Vector3) -> void:
	b.box(Vector3(BLOCK_W - 4.0, 0.14, BLOCK_D - 4.0), c + Vector3(0, 0.13, 0), "grass", false)
	b.box(Vector3(BLOCK_W - 4.0, 0.15, 3.0), c + Vector3(0, 0.14, 0), "path", false)
	b.box(Vector3(3.0, 0.15, BLOCK_D - 4.0), c + Vector3(0, 0.14, 0), "path", false)
	for i in 22:
		var p := c + Vector3(rng.randf_range(-32, 32), 0, rng.randf_range(-20, 20))
		if absf(p.x - c.x) < 3.0 or absf(p.z - c.z) < 3.0:
			continue
		w.add_tree(p, rng.randf_range(0.8, 1.3), false)
	w.add_region_point("city", c + Vector3(5, 0.3, 5))


## The crew's base: a converted warehouse you can walk into. Story starts here.
func _hq(c: Vector3) -> void:
	var size := Vector3(44.0, 11.0, 32.0)
	var center := Vector3(c.x, 0.0, c.z)
	var t := 0.5
	var door := 9.0
	var north := center.z - size.z * 0.5
	# Walls (door gap facing the north street) + roof.
	var side_w := (size.x - door) * 0.5
	b.box(Vector3(side_w, size.y, t), Vector3(center.x - size.x * 0.5 + side_w * 0.5, size.y * 0.5, north), "brick_dark")
	b.box(Vector3(side_w, size.y, t), Vector3(center.x + size.x * 0.5 - side_w * 0.5, size.y * 0.5, north), "brick_dark")
	b.box(Vector3(door, size.y - 5.0, t), Vector3(center.x, size.y - (size.y - 5.0) * 0.5, north), "brick_dark")
	b.box(Vector3(size.x, size.y, t), Vector3(center.x, size.y * 0.5, center.z + size.z * 0.5), "brick_dark")
	b.box(Vector3(t, size.y, size.z), Vector3(center.x - size.x * 0.5, size.y * 0.5, center.z), "brick_dark")
	b.box(Vector3(t, size.y, size.z), Vector3(center.x + size.x * 0.5, size.y * 0.5, center.z), "brick_dark")
	b.box(Vector3(size.x + 1.0, 0.6, size.z + 1.0), Vector3(center.x, size.y + 0.3, center.z), "roof")
	b.box(Vector3(size.x - 1.0, 0.1, size.z - 1.0), Vector3(center.x, 0.17, center.z), "concrete", false)
	# Inside: briefing table, lockers, workbench.
	b.box(Vector3(6.0, 0.9, 3.0), center + Vector3(-8, 0.45, 6), "metal")
	b.box(Vector3(10.0, 2.2, 0.8), center + Vector3(-15, 1.1, 14.5), "metal")
	b.box(Vector3(5.0, 1.0, 1.6), center + Vector3(14, 0.5, 14), "trim")
	var lamp := OmniLight3D.new()
	lamp.position = center + Vector3(-6, 8.0, 4)
	lamp.light_color = Color(1.0, 0.82, 0.6)
	lamp.light_energy = 2.2
	lamp.omni_range = 26.0
	w.add_child(lamp)
	w.add_label("THE LOOKOUT", center + Vector3(0, size.y - 1.5, -size.z * 0.5 - 0.4), 110, Color(0.95, 0.75, 0.4))
	w.hq_spawn = center + Vector3(-4, 0.3, 4)
	w.hq_garage = center + Vector3(10, 0.4, 2)
	w.add_region_point("city", Vector3(center.x, 0.2, north - STREET * 0.5))


# --------------------------------------------------------------- details

func _water_tank(top: Vector3) -> void:
	var tank := CylinderMesh.new()
	tank.top_radius = 1.6
	tank.bottom_radius = 1.6
	tank.height = 3.4
	tank.radial_segments = 10
	b.mesh(tank, Transform3D(Basis(), top + Vector3(0, 3.6, 0)), "wood")
	var cap := CylinderMesh.new()
	cap.top_radius = 0.0
	cap.bottom_radius = 1.8
	cap.height = 1.0
	cap.radial_segments = 10
	b.mesh(cap, Transform3D(Basis(), top + Vector3(0, 5.8, 0)), "roof")
	b.box(Vector3(3.0, 1.9, 3.0), top + Vector3(0, 0.95, 0), "metal", false)


func _street_furniture(c: Vector3, trees: bool) -> void:
	for side: float in [-1.0, 1.0]:
		var z := c.z + side * (BLOCK_D * 0.5 - 0.6)
		var x := c.x - BLOCK_W * 0.5 + 6.0
		var i := 0
		while x < c.x + BLOCK_W * 0.5 - 4.0:
			if i % 3 == 0:
				w.add_street_light(Vector3(x, 0.12, z), side)
			elif trees and rng.randf() < 0.7:
				w.add_tree(Vector3(x, 0.12, z - side * 0.6), rng.randf_range(0.7, 1.0), false)
			x += 9.0
			i += 1


func _street_lines() -> void:
	var dash := BoxMesh.new()
	dash.size = Vector3(0.15, 0.02, 2.4)
	var transforms: Array[Transform3D] = []
	for ix in BLOCKS_X + 1:
		var z := -HALF_Z
		while z < HALF_Z:
			transforms.append(Transform3D(Basis(), Vector3(street_x(ix), 0.015, z)))
			z += 7.0
	for iz in BLOCKS_Z + 1:
		var x := -HALF_X
		while x < HALF_X:
			transforms.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x, 0.015, street_z(iz))))
			x += 7.0
	w.add_multimesh(dash, transforms, "line")


func _register_map() -> void:
	for ix in BLOCKS_X + 1:
		w.map_lines.append(PackedVector2Array([Vector2(street_x(ix), -HALF_Z), Vector2(street_x(ix), HALF_Z)]))
	for iz in BLOCKS_Z + 1:
		w.map_lines.append(PackedVector2Array([Vector2(-HALF_X, street_z(iz)), Vector2(HALF_X, street_z(iz))]))
