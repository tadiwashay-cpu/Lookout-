class_name World
extends Node3D
## The whole map: Brooklyn-style city, harbour, curvy highway, forest and
## suburb (see WorldCity / WorldRegions), plus the session it hosts:
## story (start at HQ) or a multiplayer mode (random region spawns).
## The layout uses a fixed seed so every device builds the same world.

const LAYOUT_SEED := 20261109
const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const GOON_SCENE := preload("res://scenes/characters/goon.tscn")
const CAR_SCENE := preload("res://scenes/vehicles/car.tscn")
const FACADE_SHADER := preload("res://assets/materials/shaders/facade.gdshader")
## Minimap / battle-royale bounds (x, z).
const MAP_BOUNDS := Rect2(-1180.0, -1820.0, 1700.0, 2100.0)

var rng := RandomNumberGenerator.new()
var batcher: MeshBatcher
var city: WorldCity
var regions: WorldRegions
var player: PlayerController
var hud: GameHUD
var touch: TouchControls
var mode: GameMode

# Points of interest (filled in by the builders)
var hq_spawn := Vector3.ZERO
var hq_garage := Vector3.ZERO
var bank_position := Vector3.ZERO
var precinct_position := Vector3.ZERO
var supercar_spot := Vector3.ZERO
var extraction_points: Dictionary = {}
var region_points: Dictionary = {}

# Minimap data
var map_lines: Array[PackedVector2Array] = []
var map_water := Rect2()
var map_forest := Rect2()

var _tree_trunks: Dictionary = {}     # Vector2i -> Array[Transform3D]
var _tree_canopies: Dictionary = {}   # "pine"/"round" -> {Vector2i -> Array[Transform3D]}
var _parked: Array[Dictionary] = []
var _car_spots: Array[Vector3] = []
var _remote: Dictionary = {}          # peer_id -> RemoteAvatar
var _sun: DirectionalLight3D
var _env: Environment
var _sky: ProceduralSkyMaterial
var nature: WorldNature
var day_night: DayNight
var police: PoliceManager
var _road_points: Array[Vector3] = []
var _a_class_count := 0


func _ready() -> void:
	rng.seed = LAYOUT_SEED
	batcher = MeshBatcher.new(self, GameSettings.view_distance)
	_build_materials()
	_build_environment()
	_build_ground()
	city = WorldCity.new(self)
	city.build()
	regions = WorldRegions.new(self)
	regions.build()
	nature = WorldNature.new(self)
	nature.build()
	_flush_trees()
	batcher.finish()
	_spawn_cars()
	_spawn_player()
	_build_ui()
	day_night = DayNight.new()
	day_night.name = "DayNight"
	day_night.world = self
	day_night.sun = _sun
	day_night.env = _env
	day_night.sky = _sky
	day_night.nature = nature
	add_child(day_night)
	day_night.setup()
	var blur := MotionBlur.new()
	blur.speed_source = func() -> float: return player.current_vehicle.linear_velocity.length() if player.current_vehicle else 0.0
	add_child(blur)
	_start_mode()
	if Session.networked:
		_setup_network()
	GameSettings.settings_changed.connect(_apply_graphics)
	_apply_graphics()


# ---------------------------------------------------------------- queries

func ground_height(x: float, z: float) -> float:
	if regions and WorldRegions.FOREST_RECT.has_point(Vector2(x, z)):
		return regions.forest_height(x, z)
	return 0.0


func add_region_point(region: String, point: Vector3) -> void:
	if not region_points.has(region):
		region_points[region] = []
	(region_points[region] as Array).append(point)


func random_point_in(region: String, picker: RandomNumberGenerator) -> Vector3:
	var points: Array = region_points.get(region, [])
	if points.is_empty():
		return hq_spawn
	var base: Vector3 = points[picker.randi() % points.size()]
	var p := base + Vector3(picker.randf_range(-3.0, 3.0), 0.0, picker.randf_range(-3.0, 3.0))
	p.y = maxf(p.y, ground_height(p.x, p.z) + 0.4)
	return p


# --------------------------------------------------------------- materials

func _facade(wall: Color, window: Color, trim: Color, spacing: float = 2.4, size: Vector2 = Vector2(0.5, 0.58), metal: float = 0.0, lit: float = 0.12) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = FACADE_SHADER
	m.set_shader_parameter("wall_color", wall)
	m.set_shader_parameter("window_color", window)
	m.set_shader_parameter("trim_color", trim)
	m.set_shader_parameter("window_spacing", spacing)
	m.set_shader_parameter("window_size", size)
	m.set_shader_parameter("window_metal", metal)
	m.set_shader_parameter("lit_chance", lit)
	return m


func _flat(color: Color, roughness: float = 0.85, metallic: float = 0.0, grime: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if grime:
		m.albedo_texture = grime
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.06, 0.06, 0.06)
	return m


func _build_materials() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.74, 0.74, 0.74))
	ramp.set_color(1, Color(1, 1, 1))
	var grime := NoiseTexture2D.new()
	grime.noise = noise
	grime.seamless = true
	grime.color_ramp = ramp
	grime.width = 256
	grime.height = 256
	var trim := Color(0.62, 0.58, 0.5)
	var dark_glass := Color(0.07, 0.08, 0.09)
	var m := batcher.materials
	m["brownstone"] = _facade(Color(0.36, 0.23, 0.17), dark_glass, Color(0.42, 0.3, 0.22), 2.2)
	m["brick_red"] = _facade(Color(0.46, 0.22, 0.16), dark_glass, trim)
	m["brick_dark"] = _facade(Color(0.3, 0.17, 0.13), dark_glass, Color(0.5, 0.46, 0.4), 3.2, Vector2(0.6, 0.55))
	m["limestone"] = _facade(Color(0.63, 0.58, 0.49), dark_glass, Color(0.7, 0.66, 0.58))
	m["painted"] = _facade(Color(0.58, 0.54, 0.47), dark_glass, Color(0.8, 0.78, 0.72))
	m["glass_tower"] = _facade(Color(0.2, 0.24, 0.27), Color(0.18, 0.25, 0.3), Color(0.3, 0.32, 0.34), 1.8, Vector2(0.9, 0.82), 0.6, 0.18)
	m["stone_tower"] = _facade(Color(0.52, 0.49, 0.44), dark_glass, Color(0.6, 0.57, 0.5), 2.0, Vector2(0.55, 0.6), 0.0, 0.15)
	m["trim"] = _flat(trim, 0.8)
	m["stone"] = _flat(Color(0.6, 0.57, 0.5), 0.85, 0.0, grime)
	m["sidewalk"] = _flat(Color(0.5, 0.49, 0.47), 0.9, 0.0, grime)
	m["concrete"] = _flat(Color(0.47, 0.46, 0.44), 0.9, 0.0, grime)
	m["asphalt"] = _flat(Color(0.16, 0.16, 0.17), 0.92, 0.0, grime)
	m["roof"] = _flat(Color(0.2, 0.19, 0.19), 0.95)
	m["metal"] = _flat(Color(0.24, 0.25, 0.26), 0.5, 0.7)
	m["wood"] = _flat(Color(0.33, 0.24, 0.16), 0.9)
	m["line"] = _flat(Color(0.8, 0.72, 0.42), 0.8)
	m["grass"] = _flat(Color(0.2, 0.28, 0.14), 0.95, 0.0, grime)
	m["path"] = _flat(Color(0.5, 0.45, 0.38), 0.95)
	m["dirt"] = _flat(Color(0.32, 0.25, 0.17), 0.97, 0.0, grime)
	m["forest_floor"] = _flat(Color(0.2, 0.24, 0.13), 0.97, 0.0, grime)
	m["water"] = _flat(Color(0.1, 0.16, 0.19), 0.08, 0.3)
	m["shed"] = _flat(Color(0.36, 0.38, 0.4), 0.6, 0.5, grime)
	m["crane"] = _flat(Color(0.55, 0.2, 0.12), 0.6, 0.4)
	m["ship_hull"] = _flat(Color(0.2, 0.07, 0.06), 0.7, 0.3, grime)
	m["ship_deck"] = _flat(Color(0.35, 0.3, 0.25), 0.9)
	m["white_paint"] = _facade(Color(0.82, 0.82, 0.78), dark_glass, Color(0.82, 0.82, 0.78), 2.0, Vector2(0.6, 0.5), 0.0, 0.05)
	m["container_red"] = _flat(Color(0.45, 0.13, 0.08), 0.7, 0.4)
	m["container_blue"] = _flat(Color(0.12, 0.2, 0.32), 0.7, 0.4)
	m["container_teal"] = _flat(Color(0.12, 0.3, 0.3), 0.7, 0.4)
	m["container_grey"] = _flat(Color(0.4, 0.41, 0.42), 0.7, 0.4)
	m["siding_beige"] = _facade(Color(0.68, 0.62, 0.52), dark_glass, Color(0.9, 0.9, 0.88), 3.0, Vector2(0.35, 0.5), 0.0, 0.1)
	m["siding_blue"] = _facade(Color(0.42, 0.5, 0.56), dark_glass, Color(0.9, 0.9, 0.88), 3.0, Vector2(0.35, 0.5), 0.0, 0.1)
	m["siding_white"] = _facade(Color(0.82, 0.81, 0.77), dark_glass, Color(0.55, 0.55, 0.55), 3.0, Vector2(0.35, 0.5), 0.0, 0.1)
	m["siding_yellow"] = _facade(Color(0.74, 0.66, 0.44), dark_glass, Color(0.9, 0.9, 0.88), 3.0, Vector2(0.35, 0.5), 0.0, 0.1)
	m["siding_grey"] = _facade(Color(0.5, 0.5, 0.48), dark_glass, Color(0.9, 0.9, 0.88), 3.0, Vector2(0.35, 0.5), 0.0, 0.1)
	m["shingles"] = _flat(Color(0.22, 0.2, 0.2), 0.9)
	m["fence"] = _flat(Color(0.75, 0.73, 0.68), 0.8)
	var lamp := _flat(Color(1.0, 0.72, 0.4), 0.5)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.62, 0.28)
	lamp.emission_energy_multiplier = 2.0
	m["lamp"] = lamp
	m["bark"] = _flat(Color(0.25, 0.18, 0.13), 0.95)
	m["pine"] = _flat(Color(0.12, 0.2, 0.12), 0.95)
	m["leaves"] = _flat(Color(0.2, 0.3, 0.15), 0.95)


# ------------------------------------------------------------- environment

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.36, 0.44, 0.54)
	sky_material.sky_horizon_color = Color(0.72, 0.68, 0.61)
	sky_material.ground_horizon_color = Color(0.45, 0.42, 0.38)
	sky_material.ground_bottom_color = Color(0.18, 0.17, 0.16)
	var sky := Sky.new()
	sky.sky_material = sky_material
	_sky = sky_material
	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_energy = 0.8
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.66, 0.65, 0.62)
	_env.adjustment_enabled = true
	_env.adjustment_saturation = 0.9
	_env.adjustment_contrast = 1.05
	var world_env := WorldEnvironment.new()
	world_env.environment = _env
	add_child(world_env)
	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-34.0, -38.0, 0.0)
	_sun.light_color = Color(1.0, 0.9, 0.78)
	_sun.light_energy = 1.3
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(_sun)


func _apply_graphics() -> void:
	_sun.shadow_enabled = GameSettings.shadows_enabled and _sun.light_energy > 0.1
	_sun.directional_shadow_max_distance = clampf(GameSettings.view_distance * 0.2, 40.0, 110.0)
	_env.fog_density = 2.2 / maxf(GameSettings.view_distance, 100.0)
	if player:
		player.camera().far = maxf(GameSettings.view_distance * 1.6, 300.0)


func _build_ground() -> void:
	# City + quay asphalt, then grass for everything else (slightly lower).
	batcher.collider_box(Vector3(640.0, 1.0, 560.0), Vector3(17.0, -0.5, 0.0))
	var asphalt := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(640.0, 560.0)
	asphalt.mesh = plane
	asphalt.material_override = batcher.materials["asphalt"]
	asphalt.position = Vector3(17.0, 0.0, 0.0)
	add_child(asphalt)
	var grass_rect := Rect2(-1300.0, -1900.0, 1635.0, 2300.0)
	var grass := MeshInstance3D.new()
	var grass_plane := PlaneMesh.new()
	grass_plane.size = grass_rect.size
	grass.mesh = grass_plane
	grass.material_override = batcher.materials["grass"]
	grass.position = Vector3(grass_rect.get_center().x, -0.03, grass_rect.get_center().y)
	add_child(grass)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := BoxShape3D.new()
	shape.size = Vector3(grass_rect.size.x, 1.0, grass_rect.size.y)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(grass_rect.get_center().x, -0.53, grass_rect.get_center().y)
	body.add_child(collision)
	add_child(body)


# ------------------------------------------------------- builder helpers

func add_label(text: String, pos: Vector3, size: int, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = size
	label.modulate = color
	label.outline_size = 12
	label.position = pos
	label.visibility_range_end = 220.0
	add_child(label)


func add_multimesh(source: Mesh, transforms: Array[Transform3D], key: String) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = source
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = batcher.materials.get(key)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func add_street_light(base: Vector3, side: float, height: float = 6.5) -> void:
	batcher.box(Vector3(0.18, height, 0.18), base + Vector3(0, height * 0.5, 0), "metal")
	batcher.box(Vector3(0.12, 0.12, 1.6), base + Vector3(0, height, -side * 0.8), "metal", false)
	batcher.box(Vector3(0.5, 0.16, 0.5), base + Vector3(0, height - 0.1, -side * 1.5), "lamp", false)


## Trees are drawn with MultiMeshes per chunk (thousands of trees, few draw calls).
func add_tree(base: Vector3, size: float, pine: bool) -> void:
	var chunk := Vector2i(floori(base.x / 128.0), floori(base.z / 128.0))
	var kind := "pine" if pine else "round"
	if not _tree_canopies.has(kind):
		_tree_canopies[kind] = {}
	var trunk_h := (3.0 if pine else 2.6) * size
	if not _tree_trunks.has(chunk):
		_tree_trunks[chunk] = []
	(_tree_trunks[chunk] as Array).append(Transform3D(Basis.from_scale(Vector3(size, size, size)), base + Vector3(0, trunk_h * 0.5, 0)))
	var canopies: Dictionary = _tree_canopies[kind]
	if not canopies.has(chunk):
		canopies[chunk] = []
	var yaw := rng.randf() * TAU
	var canopy_y := trunk_h + (3.0 if pine else 1.6) * size
	(canopies[chunk] as Array).append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * size), base + Vector3(0, canopy_y, 0)))
	batcher.collider_box(Vector3(0.5, trunk_h, 0.5) * size, base + Vector3(0, trunk_h * 0.5, 0))


func _flush_trees() -> void:
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.18
	trunk.bottom_radius = 0.26
	trunk.height = 3.0
	trunk.radial_segments = 6
	var pine := CylinderMesh.new()
	pine.top_radius = 0.0
	pine.bottom_radius = 2.0
	pine.height = 7.0
	pine.radial_segments = 7
	var leafy := SphereMesh.new()
	leafy.radius = 2.2
	leafy.height = 3.8
	leafy.radial_segments = 8
	leafy.rings = 5
	for chunk: Vector2i in _tree_trunks:
		_tree_batch(trunk, _tree_trunks[chunk], "bark")
	for kind: String in _tree_canopies:
		var canopies: Dictionary = _tree_canopies[kind]
		for chunk: Vector2i in canopies:
			_tree_batch(pine if kind == "pine" else leafy, canopies[chunk], "pine" if kind == "pine" else "leaves")


func _tree_batch(source: Mesh, transforms: Array, key: String) -> void:
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = source
	multimesh.instance_count = transforms.size()
	var center := Vector3.ZERO
	for t: Transform3D in transforms:
		center += t.origin
	center /= maxf(transforms.size(), 1)
	for i in transforms.size():
		var t: Transform3D = transforms[i]
		t.origin -= center
		multimesh.set_instance_transform(i, t)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = batcher.materials.get(key)
	instance.position = center
	instance.visibility_range_end = GameSettings.view_distance + 60.0
	add_child(instance)


func add_parked_car(pos: Vector3, yaw: float) -> void:
	_parked.append({"pos": pos, "yaw": yaw})


# ------------------------------------------------------------------ cars

func _spawn_car(id: String, pos: Vector3, yaw: float, paint: Color = Color(0, 0, 0, 0)) -> DrivableCar:
	var car := CAR_SCENE.instantiate() as DrivableCar
	car.vehicle_id = id
	car.paint = paint
	car.position = pos + Vector3.UP * 0.35
	car.rotation.y = yaw
	add_child(car)
	_car_spots.append(pos)
	return car


func _spot_free(pos: Vector3) -> bool:
	for spot in _car_spots:
		if Vector2(spot.x - pos.x, spot.z - pos.z).length() < 8.0:
			return false
	return true


## No S-class in normal parking, and only a few A-class cars on the map.
func _limit_rank(id: String) -> String:
	var rank: String = VehicleCatalog.VEHICLES[id]["rank"]
	if rank == "S":
		return "hatchback"
	if rank == "A":
		_a_class_count += 1
		if _a_class_count > 3:
			return "suv"
	return id


## Points on drivable roads (police spawns, roadblocks).
func road_points() -> Array[Vector3]:
	if not _road_points.is_empty():
		return _road_points
	for ix in WorldCity.BLOCKS_X + 1:
		var z := -WorldCity.HALF_Z + 12.0
		while z < WorldCity.HALF_Z - 12.0:
			_road_points.append(Vector3(WorldCity.street_x(ix), 0.3, z))
			z += 25.0
	for iz in WorldCity.BLOCKS_Z + 1:
		var x := -WorldCity.HALF_X + 12.0
		while x < WorldCity.HALF_X - 12.0:
			_road_points.append(Vector3(x, 0.3, WorldCity.street_z(iz)))
			x += 25.0
	for i in range(0, regions.highway_samples.size(), 3):
		_road_points.append(regions.highway_samples[i] + Vector3.UP * 0.3)
	for i in range(0, regions.forest_road_samples.size(), 2):
		var p := regions.forest_road_samples[i]
		_road_points.append(Vector3(p.x, ground_height(p.x, p.z) + 0.3, p.z))
	var x := WorldRegions.SUBURB_RECT.position.x + 10.0
	while x < WorldRegions.SUBURB_RECT.end.x:
		_road_points.append(Vector3(x, 0.3, WorldRegions.SUBURB_MAIN_Z))
		x += 20.0
	return _road_points


func _spawn_cars() -> void:
	if Session.mode == Session.MODE_STREET_RACE:
		return   # race cars only
	# Crew car in the HQ garage (yours — no theft heat).
	if Session.mode == Session.MODE_STORY:
		var own := _spawn_car("coupe", hq_garage, 0.0, Color(0.1, 0.1, 0.11))
		own.has_been_stolen = true
	# Police at the precinct
	_spawn_car("police_sedan", precinct_position + Vector3(-6, 0, 0), PI * 0.5)
	_spawn_car("police_suv", precinct_position + Vector3(4, 0, 0), PI * 0.5)
	# The S-class car is genuinely rare: at most one in the whole map, only
	# in some sessions, in one of a few hidden spots that changes each time.
	var luck := RandomNumberGenerator.new()
	luck.randomize()
	if Session.mode == Session.MODE_STORY and luck.randf() < 0.45:
		var hidden: Array[Vector3] = [
			supercar_spot,
			Vector3(-372.0, ground_height(-372.0, -1462.0) + 0.5, -1462.0),             # by the ranger tower
			extraction_points.get("suburb", supercar_spot),                            # end of the suburb street
			regions.highway_samples[regions.highway_samples.size() / 3] + Vector3(14, 0.3, 0),   # highway lay-by
			WorldCity.block_center(5, 0) + Vector3(0, 0.3, WorldCity.BLOCK_D * 0.5 + 2.0),       # downtown side street
		]
		_spawn_car("sport", hidden[luck.randi() % hidden.size()], luck.randf() * TAU, VehicleCatalog.random_paint(luck))
	# City kerbside parking: about one per block
	for ix in WorldCity.BLOCKS_X:
		for iz in WorldCity.BLOCKS_Z:
			var c := WorldCity.block_center(ix, iz)
			var side := 1.0 if rng.randf() > 0.5 else -1.0
			var pos := c + Vector3(rng.randf_range(-26.0, 26.0), 0.0, side * (WorldCity.BLOCK_D * 0.5 + 2.0))
			if not _spot_free(pos):
				continue
			var id := _limit_rank(VehicleCatalog.pick_civilian(rng))
			_spawn_car(id, pos, PI * 0.5 + (PI if rng.randf() > 0.5 else 0.0), VehicleCatalog.random_paint(rng))
	# Suburb driveways
	for parked in _parked:
		var pos: Vector3 = parked["pos"]
		if _spot_free(pos):
			var id := _limit_rank(VehicleCatalog.pick_civilian(rng))
			_spawn_car(id, pos, parked["yaw"], VehicleCatalog.random_paint(rng))


# ---------------------------------------------------------------- player

func _spawn_player() -> void:
	player = PLAYER_SCENE.instantiate() as PlayerController
	var spawn := hq_spawn
	var yaw := 0.0
	if Session.mode == Session.MODE_BATTLE_ROYALE:
		var region := Session.spawn_region_for(Session.my_id())
		spawn = random_point_in(region, Session.match_rng(Session.my_id()))
	elif Session.mode == Session.MODE_HEIST:
		if Session.team_of(Session.my_id()) == "police":
			spawn = precinct_position + Vector3(Session.match_rng(Session.my_id()).randf_range(-6, 6), 0.3, -2.0)
		else:
			spawn = bank_position + Vector3(Session.match_rng(Session.my_id()).randf_range(-5, 5), 0.3, 1.0)
	player.position = spawn + Vector3.UP * 0.3
	player.rotation.y = yaw
	add_child(player)
	player.spawn_point = player.global_position


func _build_ui() -> void:
	hud = GameHUD.new()
	add_child(hud)
	hud.bind_world(self)
	hud.bind_player(player)
	var touch_layer := CanvasLayer.new()
	touch_layer.layer = 11
	add_child(touch_layer)
	touch = TouchControls.new()
	touch.player = player
	touch_layer.add_child(touch)
	if Session.mode == Session.MODE_STORY:
		police = PoliceManager.new()
		police.name = "Police"
		police.world = self
		add_child(police)
		var crowd := PedestrianManager.new()
		crowd.name = "Pedestrians"
		crowd.world = self
		add_child(crowd)


func _start_mode() -> void:
	if Session.mode == Session.MODE_BATTLE_ROYALE:
		mode = BattleRoyaleMode.new()
	elif Session.mode == Session.MODE_STREET_RACE:
		mode = StreetRaceMode.new()
	elif Session.mode == Session.MODE_HEIST:
		mode = HeistMode.new()
	else:
		mode = StoryMode.new()
	mode.name = "Mode"
	mode.world = self
	add_child(mode)
	hud.bind_mode(mode)
	mode.begin()


## Used by modes (race cars, goons).
func spawn_car(id: String, pos: Vector3, yaw: float, paint: Color = Color(0, 0, 0, 0)) -> DrivableCar:
	return _spawn_car(id, pos, yaw, paint)


func spawn_goon(pos: Vector3) -> Goon:
	var goon := GOON_SCENE.instantiate() as Goon
	goon.position = pos
	add_child(goon)
	return goon


# --------------------------------------------------------------- network

func _setup_network() -> void:
	Net.state_received.connect(_on_remote_state)
	Net.players_changed.connect(_sync_remote_list)
	Net.match_event.connect(_on_net_event)
	Net.session_ended.connect(func(reason: String) -> void: hud.show_banner(reason, 3.0, 40))
	_sync_remote_list()


func _sync_remote_list() -> void:
	for id: int in Net.players:
		if id != multiplayer.get_unique_id() and not _remote.has(id):
			var avatar := RemoteAvatar.new()
			avatar.setup(id, Net.players[id])
			add_child(avatar)
			_remote[id] = avatar
	for id: int in _remote.keys():
		if not Net.players.has(id):
			(_remote[id] as Node).queue_free()
			_remote.erase(id)


func _on_remote_state(peer_id: int, state: Dictionary) -> void:
	if not _remote.has(peer_id):
		_sync_remote_list()
	var avatar := _remote.get(peer_id) as RemoteAvatar
	if avatar:
		avatar.apply_state(state)


func remote_avatars() -> Array:
	return _remote.values()


## Visual-only copies of other players' shots, grenades and surges.
func _on_net_event(kind: String, data: Dictionary) -> void:
	if int(data.get("sender", 0)) == multiplayer.get_unique_id():
		return
	match kind:
		"shot":
			Effects.tracer(get_tree(), data.get("a", Vector3.ZERO), data.get("b", Vector3.ZERO))
		"grenade":
			var grenade := Grenade.new()
			grenade.visual_only = true
			add_child(grenade)
			grenade.global_position = data.get("pos", Vector3.ZERO)
			grenade.linear_velocity = data.get("vel", Vector3.ZERO)
		"surge":
			Effects.surge(get_tree(), data.get("pos", Vector3.ZERO), float(data.get("r", 6.0)))
