class_name Regions
extends RefCounted
## Everything outside downtown: suburban houses along the suburb roads, the
## harbour (quay, warehouses, container stacks, cranes, a moored ship, the
## sea) and the forest (impostor firs, rocks), plus trees on the hills.

var w: Node3D
var rng := RandomNumberGenerator.new()
var house_doors: Array[Vector3] = []
var body: StaticBody3D


func _init(world: Node3D, seed_value: int) -> void:
	w = world
	rng.seed = seed_value + 99


func build(roads: Roads) -> void:
	body = StaticBody3D.new()
	body.name = "RegionBodies"
	body.collision_layer = Game.L_WORLD
	w.add_child(body)
	_suburb(roads)
	_harbour()
	_sea()
	_forest(roads)


# ------------------------------------------------------------------ suburb

func _suburb(roads: Roads) -> void:
	var walls: Array = []
	var roofs: Array = []
	var garages: Array = []
	var roof_mesh := _gable_mesh()
	for road_name in ["suburb_main", "suburb_link"]:
		var path: Array = roads.paths[road_name]
		var i := 6
		while i < path.size() - 6:
			var a: Vector3 = path[i]
			var b: Vector3 = path[i + 1]
			var dir := (b - a)
			dir.y = 0.0
			dir = dir.normalized()
			var side_v := Vector3(-dir.z, 0, dir.x)
			for side in [-1.0, 1.0]:
				var center: Vector3 = a + side_v * side * 24.0
				if not Layout.SUBURB_RECT.grow(40.0).has_point(Vector2(center.x, center.z)):
					continue
				if Layout.CITY_RECT.grow(20.0).has_point(Vector2(center.x, center.z)):
					continue
				# Never on (or right beside) another road, e.g. at crossings.
				if _near_other_road(roads, road_name, center):
					continue
				var ground := Terrain.height_at(center.x, center.z)
				var yaw: float = atan2(side_v.x * side, side_v.z * side) + PI   # front faces the road
				var size := Vector3(rng.randf_range(10, 14), rng.randf_range(3.2, 6.4), rng.randf_range(9, 12))
				var basis := Basis(Vector3.UP, yaw)
				var base := Vector3(center.x, ground, center.z)
				walls.append([Transform3D(basis.scaled(size), base + Vector3.UP * (size.y * 0.5 - 0.6)), Color.from_hsv(rng.randf_range(0.05, 0.15), rng.randf_range(0.05, 0.3), rng.randf_range(0.75, 1.0))])
				roofs.append(Transform3D(basis.scaled(Vector3(size.x + 1.0, 2.6, size.z + 1.0)), base + Vector3.UP * (size.y - 0.6)))
				Mats.box_collider(body, base + Vector3.UP * (size.y * 0.5 - 0.6), size, yaw)
				var front := -basis.z
				house_doors.append(base + front * (size.z * 0.5 + 1.0) + Vector3.UP * 0.3)
				if rng.randf() < 0.5:
					var g := base + basis.x * (size.x * 0.5 + 3.5)
					garages.append(Transform3D(basis.scaled(Vector3(5.0, 3.0, 6.5)), g + Vector3.UP * 0.9))
					Mats.box_collider(body, g + Vector3.UP * 0.9, Vector3(5.0, 3.0, 6.5), yaw)
			i += 7
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/facade.gdshader")
	mat.set_shader_parameter("wall_d", Mats.tex("grey_plaster", "diff"))
	mat.set_shader_parameter("wall_n", Mats.tex("grey_plaster", "nor"))
	mat.set_shader_parameter("roof_d", Mats.tex("clay_roof_tiles", "diff"))
	mat.set_shader_parameter("wall_scale", 0.3)
	mat.set_shader_parameter("window_w", 4.5)
	mat.set_shader_parameter("floor_h", 3.2)
	mat.set_shader_parameter("glass", 0.35)
	w.set_meta(&"suburb_facade", mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = BoxMesh.new()
	mm.instance_count = walls.size()
	for k in walls.size():
		mm.set_instance_transform(k, walls[k][0])
		mm.set_instance_custom_data(k, walls[k][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.visibility_range_end = 700.0
	w.add_child(mmi)
	roof_mesh.surface_set_material(0, Mats.pbr("clay_roof_tiles", 3.0))
	Mats.scatter(w, roof_mesh, roofs, true, 700.0)
	var gbox := BoxMesh.new()
	gbox.material = Mats.pbr("painted_metal_shutter", 3.0, Color(0.85, 0.85, 0.85))
	Mats.scatter(w, gbox, garages, true, 500.0)


func _near_other_road(roads: Roads, own: String, p: Vector3) -> bool:
	for other: String in roads.paths:
		if other == own:
			continue
		var path: Array = roads.paths[other]
		for i in range(0, path.size(), 2):
			var q: Vector3 = path[i]
			if Vector2(q.x - p.x, q.z - p.z).length() < 26.0:
				return true
	return false


## A unit gable roof (ridge along X), base at y=0, height 1.
func _gable_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-0.5, 0, -0.5)
	var b := Vector3(0.5, 0, -0.5)
	var c := Vector3(0.5, 0, 0.5)
	var d := Vector3(-0.5, 0, 0.5)
	var r0 := Vector3(-0.5, 1, 0)
	var r1 := Vector3(0.5, 1, 0)
	for tri in [[a, r0, r1], [a, r1, b], [d, c, r1], [d, r1, r0], [a, d, r0], [b, r1, c]]:
		var n: Vector3 = ((tri[1] - tri[0]).cross(tri[2] - tri[0])).normalized()
		for v: Vector3 in tri:
			st.set_normal(-n)
			st.set_uv(Vector2(v.x + v.z, v.y))
			st.add_vertex(v)
	return st.commit()


# ----------------------------------------------------------------- harbour

func _harbour() -> void:
	var r := Layout.HARBOUR_RECT
	var y := Layout.CITY_Y
	# Quay slab + the quay wall into the water.
	var quay := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(r.size.x, 14.0, r.size.y)
	quay.mesh = slab
	quay.material_override = Mats.pbr("brushed_concrete", 4.0, Color(0.8, 0.8, 0.78))
	quay.position = Vector3(r.get_center().x, y - 7.0 + 0.02, r.get_center().y)
	w.add_child(quay)
	Mats.box_collider(body, quay.position, slab.size)
	# Warehouses along the north side.
	var sheds: Array = []
	for i in 3:   # (clear of the coast highway on the east side)
		var c := Vector3(r.position.x + 40.0 + i * 62.0, y, r.position.y + 40.0)
		var size := Vector3(50.0, rng.randf_range(10.0, 14.0), 40.0)
		sheds.append(Transform3D(Basis.from_scale(size), c + Vector3.UP * size.y * 0.5))
		Mats.box_collider(body, c + Vector3.UP * size.y * 0.5, size)
	var shed_box := BoxMesh.new()
	shed_box.material = Mats.pbr("painted_metal_shutter", 4.0, Color(0.55, 0.6, 0.62))
	Mats.scatter(w, shed_box, sheds)
	# Container stacks (colours vary per instance).
	var colors := [Color(0.6, 0.12, 0.08), Color(0.1, 0.3, 0.55), Color(0.15, 0.4, 0.2), Color(0.75, 0.55, 0.1), Color(0.5, 0.5, 0.52)]
	var stacks: Array = []
	for row in 5:
		for col in 6:
			var base := Vector3(r.position.x + 30.0 + col * 15.0, y, r.position.y + 120.0 + row * 7.5)
			if base.distance_to(Layout.RING_CENTER) < 40.0:
				continue
			var levels := rng.randi_range(1, 4)
			for lv in levels:
				stacks.append([Transform3D(Basis.from_scale(Vector3(12.2, 2.6, 2.45)), base + Vector3(0, 1.3 + lv * 2.6, 0)), colors[rng.randi() % colors.size()]])
			Mats.box_collider(body, base + Vector3(0, levels * 1.3, 0), Vector3(12.2, levels * 2.6, 2.45))
	var cmat := StandardMaterial3D.new()
	cmat.albedo_texture = Mats.tex("painted_metal_shutter", "diff")
	cmat.normal_enabled = true
	cmat.normal_texture = Mats.tex("painted_metal_shutter", "nor")
	cmat.vertex_color_use_as_albedo = true
	cmat.uv1_triplanar = true
	cmat.uv1_world_triplanar = true
	cmat.uv1_scale = Vector3.ONE * 0.35
	var cbox := BoxMesh.new()
	cbox.material = cmat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = cbox
	mm.instance_count = stacks.size()
	for k in stacks.size():
		mm.set_instance_transform(k, stacks[k][0])
		mm.set_instance_color(k, stacks[k][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	w.add_child(mmi)
	# Gantry cranes on the quay edge.
	var steel := Mats.flat(Color(0.75, 0.45, 0.1), 0.5, 0.6)
	for i in 3:
		var base := Vector3(Layout.SHORE_X - 8.0, y, r.position.y + 345.0 + i * 120.0)
		for leg in [Vector3(-6, 0, -8), Vector3(-6, 0, 8), Vector3(6, 0, -8), Vector3(6, 0, 8)]:
			_box(base + leg + Vector3.UP * 16.0, Vector3(1.2, 32.0, 1.2), steel, true)
		_box(base + Vector3(14.0, 33.0, 0), Vector3(60.0, 2.5, 18.0), steel, false)
	# A moored ship.
	var ship := Mats.prop("dutch_ship_medium")
	var holder := MeshInstance3D.new()
	holder.mesh = ship["mesh"]
	holder.position = Vector3(Layout.SHORE_X + 22.0, 0.0, r.position.y + 60.0)
	holder.rotation.y = PI * 0.5
	w.add_child(holder)
	# Barrels and boxes on the quay.
	var barrels: Array = []
	for i in 40:
		barrels.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(rng.randf_range(r.position.x + 20, Layout.SHORE_X - 30), y, rng.randf_range(r.position.y + 90, r.end.y - 20))))
	Mats.scatter(w, Mats.prop("barrel_01")["mesh"], barrels, true, 180.0)


func _box(center: Vector3, size: Vector3, mat: Material, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = mat
	mi.position = center
	w.add_child(mi)
	if solid:
		Mats.box_collider(body, center, size)


func _sea() -> void:
	var water := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1800, 3600)
	plane.subdivide_width = 60
	plane.subdivide_depth = 120
	water.mesh = plane
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/water.gdshader")
	water.material_override = mat
	water.position = Vector3(Layout.SHORE_X + 900.0, -0.4, 0)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(water)


# ------------------------------------------------------------------ forest

func _forest(roads: Roads) -> void:
	var tex_a := load("res://assets/trees/fir_a.png") as Texture2D
	var tex_b := load("res://assets/trees/fir_b.png") as Texture2D
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/tree_billboard.gdshader")
	mat.set_shader_parameter("tex", tex_a)
	var mesh := _cross_quads(9.0, 2.25)
	mesh.surface_set_material(0, mat)
	var mat_b := mat.duplicate() as ShaderMaterial
	mat_b.set_shader_parameter("tex", tex_b)
	var mesh_b := _cross_quads(9.0, 2.25)
	mesh_b.surface_set_material(0, mat_b)
	var chunks: Dictionary = {}       # Vector2i -> [Array a, Array b]
	var rocks: Array = []
	var place := func(x: float, z: float) -> void:
		var p := Vector2(x, z)
		if Layout.CITY_RECT.grow(30).has_point(p) or Layout.HARBOUR_RECT.grow(30).has_point(p) or Layout.SUBURB_RECT.grow(-10).has_point(p):
			return
		var h := Terrain.height_at(x, z)
		if h > 170.0 or h < 2.5 or roads.influence(x, z).x > 0.01:
			return
		var s := rng.randf_range(0.8, 1.5)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, h - 0.2, z))
		var key := Vector2i(floori(x / 200.0), floori(z / 200.0))
		if not chunks.has(key):
			chunks[key] = [[], []]
		(chunks[key][rng.randi() % 2] as Array).append(xf)
		if rng.randf() < 0.05:
			rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.6, 1.8)), Vector3(x + 3, h - 0.3, z + 2)))
	# The forest: dense (about one tree every 9 m), in clumps and clearings.
	var forest_count := 9000 if Game.quality >= 1 else 4500
	var r := Layout.FOREST_RECT
	for i in forest_count:
		var x := rng.randf_range(r.position.x, r.end.x)
		var z := rng.randf_range(r.position.y, r.end.y)
		if Terrain._n_low.get_noise_2d(x * 3.0, z * 3.0) < -0.35:
			continue   # clearing
		place.call(x, z)
	# Scattered trees on the other hills.
	for i in 2500:
		place.call(rng.randf_range(-Layout.HALF + 20, Layout.SHORE_X - 20), rng.randf_range(-Layout.HALF + 20, Layout.HALF - 20))
	for key in chunks:
		for k in 2:
			var list: Array = chunks[key][k]
			if list.is_empty():
				continue
			var mmi := Mats.scatter(w, mesh if k == 0 else mesh_b, list, true, 700.0)
			mmi.visibility_range_end_margin = 60.0
	Mats.scatter(w, Mats.prop("rock_moss_set_01")["mesh"], rocks, true, 300.0)
	var boulders: Array = []
	for i in 120:
		var x := rng.randf_range(-Layout.HALF + 50, Layout.SHORE_X)
		var z := rng.randf_range(-Layout.HALF + 50, -560.0)
		var h := Terrain.height_at(x, z)
		if roads.influence(x, z).x > 0.01:
			continue
		boulders.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(2.0, 6.0)), Vector3(x, h - 0.5, z)))
	Mats.scatter(w, Mats.prop("boulder_01")["mesh"], boulders, true, 600.0)


## Two crossed vertical quads, `h` tall and `half` wide, UV 0..1.
func _cross_quads(h: float, half: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 2:
		var ax := Vector3(1, 0, 0) if k == 0 else Vector3(0, 0, 1)
		var n := Vector3(0, 0, 1) if k == 0 else Vector3(1, 0, 0)
		var q := [[-ax * half, Vector2(0, 1)], [ax * half, Vector2(1, 1)], [ax * half + Vector3.UP * h, Vector2(1, 0)], [-ax * half + Vector3.UP * h, Vector2(0, 0)]]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP.lerp(n, 0.3).normalized())
			st.set_color(Color(1, 1, 1))
			st.set_uv(q[idx][1])
			st.add_vertex(q[idx][0])
	return st.commit()
