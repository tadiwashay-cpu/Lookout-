class_name WorldNature
extends RefCounted
## Rocks to hide behind and clouds (sky layer + low forest clouds/mist).

const CLOUD_SHADER := preload("res://assets/materials/shaders/clouds.gdshader")

var w: World
var rng := RandomNumberGenerator.new()
var _rock_meshes: Array[ArrayMesh] = []
var _rocks: Dictionary = {}   # "variant|cx,cz" -> Array[Transform3D]
var cloud_material: ShaderMaterial
var puff_material: StandardMaterial3D


func _init(world: World) -> void:
	w = world
	rng.seed = 4242


func build() -> void:
	_make_rock_meshes()
	_scatter_rocks()
	_flush_rocks()
	_clouds()


# ------------------------------------------------------------------ rocks

func _make_rock_meshes() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.9
	for variant in 3:
		noise.seed = 11 + variant * 7
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 10
		sphere.rings = 6
		var arrays := sphere.get_mesh_arrays()
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			var v := verts[i]
			# Noise from position, so seam duplicates move together (no cracks).
			var bump := 1.0 + noise.get_noise_3dv(v * 1.7) * 0.35
			v *= bump
			v.y = v.y * 0.62 if v.y > 0.0 else v.y * 0.3   # flat-ish bottom, lumpy top
			verts[i] = v
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = null
		arrays[Mesh.ARRAY_TANGENT] = null
		var raw := ArrayMesh.new()
		raw.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var st := SurfaceTool.new()
		st.create_from(raw, 0)
		st.generate_normals()
		_rock_meshes.append(st.commit())


func add_rock(base: Vector3, size: Vector3, yaw: float) -> void:
	var variant := rng.randi() % _rock_meshes.size()
	var chunk := Vector2i(floori(base.x / 128.0), floori(base.z / 128.0))
	var key := "%d|%d,%d" % [variant, chunk.x, chunk.y]
	if not _rocks.has(key):
		_rocks[key] = []
	(_rocks[key] as Array).append(Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), base + Vector3.UP * size.y * 0.15))
	w.batcher.collider_box(Vector3(size.x * 1.5, size.y * 1.1, size.z * 1.5), base + Vector3.UP * size.y * 0.5, yaw)


func _scatter_rocks() -> void:
	var regions := w.regions
	var forest := WorldRegions.FOREST_RECT
	# Forest: clusters big enough to hide behind, off the road.
	var placed := 0
	var tries := 0
	while placed < 260 and tries < 3000:
		tries += 1
		var x := rng.randf_range(forest.position.x + 20, forest.end.x - 20)
		var z := rng.randf_range(forest.position.y + 20, forest.end.y - 20)
		if WorldRegions.distance_to_path(Vector2(x, z), regions.forest_road_samples) < 9.0:
			continue
		var cover := rng.randf() < 0.45
		var s := rng.randf_range(1.2, 2.2) if cover else rng.randf_range(0.4, 1.0)
		var size := Vector3(s * rng.randf_range(1.0, 1.6), s * rng.randf_range(0.9, 1.4), s * rng.randf_range(0.9, 1.4))
		add_rock(Vector3(x, regions.forest_height(x, z) - 0.2, z), size, rng.randf() * TAU)
		placed += 1
	# Highway shoulders (outside the guardrails)
	var samples := regions.highway_samples
	for i in range(4, samples.size() - 4, 7):
		var a := samples[i]
		var dir := (samples[i + 1] - a)
		dir.y = 0.0
		var side := Vector3(-dir.z, 0.0, dir.x).normalized() * (1.0 if rng.randf() > 0.5 else -1.0)
		var s := rng.randf_range(1.0, 2.0)
		add_rock(a + side * rng.randf_range(15.0, 28.0) + Vector3(0, -0.25, 0), Vector3(s * 1.4, s, s * 1.2), rng.randf() * TAU)
	# Suburb backyards and edges
	var sub := WorldRegions.SUBURB_RECT
	for i in 26:
		var p := Vector3(rng.randf_range(sub.position.x, sub.end.x), -0.1, rng.randf_range(sub.position.y, sub.end.y))
		var space_ok := absf(p.z - WorldRegions.SUBURB_MAIN_Z) > 10.0
		if space_ok:
			var s := rng.randf_range(0.7, 1.5)
			add_rock(p, Vector3(s * 1.3, s, s), rng.randf() * TAU)
	# Park and harbour edge
	var park := WorldCity.block_center(WorldCity.PARK_BLOCK.x, WorldCity.PARK_BLOCK.y)
	for i in 8:
		var s := rng.randf_range(0.8, 1.4)
		add_rock(park + Vector3(rng.randf_range(-30, 30), 0.1, rng.randf_range(-18, 18)), Vector3(s * 1.4, s, s * 1.2), rng.randf() * TAU)
	for i in 10:
		var s := rng.randf_range(0.9, 1.6)
		add_rock(Vector3(WorldRegions.QUAY_EDGE - 4.0, -0.1, rng.randf_range(-480.0, 300.0)), Vector3(s * 1.5, s, s * 1.3), rng.randf() * TAU)


func _flush_rocks() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.42, 0.4, 0.37)
	material.roughness = 0.95
	var grime := NoiseTexture2D.new()
	var noise := FastNoiseLite.new()
	noise.frequency = 0.05
	grime.noise = noise
	grime.seamless = true
	material.albedo_texture = grime
	material.uv1_triplanar = true
	material.uv1_scale = Vector3(0.4, 0.4, 0.4)
	for key: String in _rocks:
		var variant := int(key.get_slice("|", 0))
		var transforms: Array = _rocks[key]
		var center := Vector3.ZERO
		for t: Transform3D in transforms:
			center += t.origin
		center /= transforms.size()
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _rock_meshes[variant]
		multimesh.instance_count = transforms.size()
		for i in transforms.size():
			var t: Transform3D = transforms[i]
			t.origin -= center
			multimesh.set_instance_transform(i, t)
		var instance := MultiMeshInstance3D.new()
		instance.multimesh = multimesh
		instance.material_override = material
		instance.position = center
		instance.visibility_range_end = GameSettings.view_distance + 40.0
		w.add_child(instance)


# ----------------------------------------------------------------- clouds

func _clouds() -> void:
	# Sky layer over the whole map
	var noise := FastNoiseLite.new()
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var texture := NoiseTexture2D.new()
	texture.noise = noise
	texture.seamless = true
	texture.width = 512
	texture.height = 512
	cloud_material = ShaderMaterial.new()
	cloud_material.shader = CLOUD_SHADER
	cloud_material.set_shader_parameter("noise_tex", texture)
	var plane := PlaneMesh.new()
	plane.size = Vector2(4400.0, 4400.0)
	var layer := MeshInstance3D.new()
	layer.mesh = plane
	layer.material_override = cloud_material
	layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	layer.position = Vector3(-300.0, 380.0, -700.0)
	w.add_child(layer)

	# Low clouds and mist over the forest: soft billboards
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 0.85))
	gradient.set_color(1, Color(1, 1, 1, 0.0))
	var puff := GradientTexture2D.new()
	puff.gradient = gradient
	puff.fill = GradientTexture2D.FILL_RADIAL
	puff.fill_from = Vector2(0.5, 0.5)
	puff.fill_to = Vector2(1.0, 0.5)
	puff.width = 128
	puff.height = 128
	puff_material = StandardMaterial3D.new()
	puff_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	puff_material.billboard_keep_scale = true
	puff_material.albedo_texture = puff
	puff_material.albedo_color = Color(0.92, 0.93, 0.95, 0.7)
	puff_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var quad := QuadMesh.new()
	quad.size = Vector2(1.0, 1.0)
	var forest := WorldRegions.FOREST_RECT
	var transforms: Array[Transform3D] = []
	for i in 46:   # billowing clouds above the hills
		var x := rng.randf_range(forest.position.x, forest.end.x)
		var z := rng.randf_range(forest.position.y, forest.end.y)
		var s := rng.randf_range(45.0, 90.0)
		transforms.append(Transform3D(Basis.from_scale(Vector3(s, s * 0.55, s)), Vector3(x, rng.randf_range(70.0, 120.0), z)))
	for i in 26:   # low mist in the valleys
		var x := rng.randf_range(forest.position.x + 40, forest.end.x - 40)
		var z := rng.randf_range(forest.position.y + 40, forest.end.y - 40)
		var s := rng.randf_range(30.0, 55.0)
		transforms.append(Transform3D(Basis.from_scale(Vector3(s, s * 0.3, s)), Vector3(x, w.regions.forest_height(x, z) + rng.randf_range(10.0, 18.0), z)))
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = quad
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var clouds := MultiMeshInstance3D.new()
	clouds.multimesh = multimesh
	clouds.material_override = puff_material
	clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(clouds)


func set_light(tint: Color) -> void:
	if cloud_material:
		cloud_material.set_shader_parameter("tint", tint)
	if puff_material:
		puff_material.albedo_color = Color(tint.r, tint.g, tint.b, 0.6)
