extends Node3D
## Builds the open world (terrain, roads, city, suburbs, harbour, forest,
## enterable services, the ring), spawns Nash and the camera, then hands
## over to the selected mode (free roam, Clean Hands or a race).

var roads: Roads
var city: City
var regions: Regions
var services: Services
var ring: Ring
var player: Player
var cam: CameraRig
var hud: Hud
var touch: TouchControls
var mode: Node
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial
var time_of_day := 0.42           # 0 midnight .. 0.5 noon
var rng := RandomNumberGenerator.new()
var _lamp_pool: Array[OmniLight3D] = []
var _lamp_tick := 0.0


func _ready() -> void:
	add_to_group(&"world")
	var seed_value := 20261112        # the map is the same for everyone
	rng.seed = int(Game.match_config.get("seed", 1))
	Terrain.setup(seed_value)
	_environment()
	roads = Roads.new()
	roads.build_paths()
	Terrain.roads = roads
	Terrain.build(self)
	roads.build_meshes(self)
	city = City.new(self, seed_value)
	city.build()
	regions = Regions.new(self, seed_value)
	regions.build(roads)
	services = Services.new(self)
	services.build(city)
	ring = Ring.new()
	ring.name = "Ring"
	ring.position = Layout.RING_CENTER
	add_child(ring)
	ring.build()
	_street_light_pool()
	_spawn_player()
	_ui()
	_start_mode()


func _environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.22, 0.42, 0.72)
	sky_mat.sky_horizon_color = Color(0.68, 0.76, 0.85)
	sky_mat.ground_horizon_color = Color(0.6, 0.65, 0.7)
	sky_mat.sun_angle_max = 20.0
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 0.85
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.68, 0.74, 0.82)
	env.fog_density = 0.45 / Game.view_distance
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.3
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.18
	env.adjustment_contrast = 1.05
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0 if Game.quality < 2 else 160.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.light_energy = 1.3
	add_child(sun)
	_apply_time()


func _apply_time() -> void:
	var angle := (time_of_day - 0.25) * TAU          # 0 at sunrise
	var elevation := sin(angle)
	sun.rotation = Vector3(-maxf(elevation, 0.05) * PI * 0.45 - 0.15, 0.8 + time_of_day, 0)
	var day := clampf(elevation * 3.0 + 0.2, 0.0, 1.0)
	var dusk := clampf(1.0 - absf(elevation) * 4.0, 0.0, 1.0)
	sun.light_energy = lerpf(0.0, 1.15, day)
	sun.light_color = Color(1.0, 0.95, 0.88).lerp(Color(1.0, 0.6, 0.35), dusk * 0.8)
	sky_mat.sky_top_color = Color(0.02, 0.03, 0.07).lerp(Color(0.22, 0.42, 0.72), day)
	sky_mat.sky_horizon_color = Color(0.08, 0.09, 0.14).lerp(Color(0.68, 0.76, 0.85), day).lerp(Color(0.95, 0.55, 0.35), dusk * 0.6)
	env.ambient_light_energy = lerpf(0.22, 0.5, day)
	env.fog_light_color = sky_mat.sky_horizon_color
	var night := 1.0 - day
	if city:
		city.set_night(night)
	var sub = get_meta(&"suburb_facade") if has_meta(&"suburb_facade") else null
	if sub:
		(sub as ShaderMaterial).set_shader_parameter("night", night)
	for c in get_tree().get_nodes_in_group(&"cars"):
		(c as Car).lights(night > 0.5)
	for l in _lamp_pool:
		l.visible = night > 0.4


func _street_light_pool() -> void:
	for i in 8:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.55)
		l.omni_range = 28.0
		l.light_energy = 7.0
		l.visible = false
		add_child(l)
		_lamp_pool.append(l)


func _process(delta: float) -> void:
	if Game.mode() == Game.Mode.FREE_ROAM:
		time_of_day = fmod(time_of_day + delta / (24.0 * 60.0), 1.0)   # 24-minute day
		_lamp_tick -= delta
		if _lamp_tick <= 0.0:
			_lamp_tick = 0.5
			_apply_time()
			_place_lamps()


func _place_lamps() -> void:
	if _lamp_pool.is_empty() or not _lamp_pool[0].visible or player == null:
		return
	var focus := player.global_position
	var near: Array = []
	for lamp in city.lamps:
		var d := lamp.distance_squared_to(focus)
		if d < 100.0 * 100.0:
			near.append([d, lamp])
	near.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	for i in _lamp_pool.size():
		_lamp_pool[i].visible = i < near.size()
		if i < near.size():
			_lamp_pool[i].global_position = (near[i][1] as Vector3) + Vector3.DOWN * 0.5


func _spawn_player() -> void:
	player = Player.new()
	player.name = "Nash"
	player.position = Layout.PLAYER_START
	add_child(player)
	cam = CameraRig.new()
	add_child(cam)
	cam.make_current()
	player.setup_camera(cam)


func _ui() -> void:
	hud = Hud.new()
	add_child(hud)
	hud.bind(self)
	touch = TouchControls.new()
	touch.player = player
	hud.add_child(touch)


func _start_mode() -> void:
	match Game.mode():
		Game.Mode.CLEAN_HANDS:
			mode = CleanHandsMode.new()
		Game.Mode.RACE:
			mode = RaceMode.new()
		_:
			mode = FreeRoamMode.new()
	mode.name = "Mode"
	mode.set("world", self)
	add_child(mode)
	mode.call("begin")


func spawn_car(id: String, pos: Vector3, yaw: float, paint: Color = Color(0, 0, 0, 0)) -> Car:
	var c := Car.new()
	c.car_id = id
	c.paint = paint
	c.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	add_child(c)
	return c
