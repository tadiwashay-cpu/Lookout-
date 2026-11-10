class_name DayNight
extends Node
## Day/night cycle: sun arc, moon, sky and fog colours, ambient light,
## street lamps and lit windows. Length in Settings (minutes per day).

var world: World
var sun: DirectionalLight3D
var env: Environment
var sky: ProceduralSkyMaterial
var nature: WorldNature
## 0 = midnight, 0.25 = 6am, 0.5 = noon, 0.75 = 6pm
var time_of_day := 0.36

var _moon: DirectionalLight3D
var _facades: Array[ShaderMaterial] = []
var _facade_lit: Array[float] = []
var _tick := 0.0

const NIGHT_TOP := Color(0.02, 0.03, 0.07)
const DAY_TOP := Color(0.2, 0.42, 0.74)
const NIGHT_HORIZON := Color(0.07, 0.08, 0.12)
const DUSK_HORIZON := Color(0.86, 0.5, 0.3)
const DAY_HORIZON := Color(0.62, 0.74, 0.86)


func setup() -> void:
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.55, 0.65, 0.9)
	_moon.shadow_enabled = false
	world.add_child(_moon)
	for key: String in world.batcher.materials:
		var material = world.batcher.materials[key]
		if material is ShaderMaterial and (material as ShaderMaterial).get_shader_parameter("lit_chance") != null:
			_facades.append(material)
			_facade_lit.append(float((material as ShaderMaterial).get_shader_parameter("lit_chance")))
	if Session.mode != Session.MODE_STORY:
		time_of_day = Session.match_rng(3).randf_range(0.3, 0.8)   # every device agrees
	_apply()


func clock_text() -> String:
	var minutes := int(time_of_day * 24.0 * 60.0)
	return "%02d:%02d" % [minutes / 60, minutes % 60]


func _process(delta: float) -> void:
	var before := time_of_day
	time_of_day = fmod(time_of_day + delta / maxf(GameSettings.day_length_minutes * 60.0, 30.0), 1.0)
	if time_of_day < before and Session.mode == Session.MODE_STORY:   # a new day: bank interest
		var gain := GameSettings.bank_interest(Places.INTEREST)
		if gain > 0 and world.hud:
			world.hud.show_hint("Bank interest: +$%d" % gain)
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.25   # lighting changes slowly; no need to update every frame
		_apply()


func _apply() -> void:
	var angle := (time_of_day - 0.25) * TAU          # 0 at sunrise, PI/2 at noon
	var elevation := sin(angle)
	var day := smoothstep(-0.08, 0.28, elevation)
	DrivableCar.night = clampf(1.0 - day * 1.6, 0.0, 1.0)   # car lights on from dusk
	var dusk := clampf(1.0 - absf(elevation) * 3.5, 0.0, 1.0) * smoothstep(-0.2, 0.05, elevation)

	sun.rotation = Vector3(-maxf(angle, 0.05) if elevation > 0.0 else -0.05, deg_to_rad(-38.0), 0.0)
	sun.light_energy = 1.35 * day
	sun.light_color = Color(1.0, 0.62, 0.38).lerp(Color(1.0, 0.92, 0.8), smoothstep(0.05, 0.45, elevation))
	sun.shadow_enabled = GameSettings.shadows_enabled and day > 0.1
	_moon.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(140.0), 0.0)
	_moon.light_energy = 0.22 * (1.0 - day)

	sky.sky_top_color = NIGHT_TOP.lerp(DAY_TOP, day)
	var horizon := NIGHT_HORIZON.lerp(DAY_HORIZON, day).lerp(DUSK_HORIZON, dusk * 0.8)
	sky.sky_horizon_color = horizon
	sky.ground_horizon_color = horizon.darkened(0.3)
	env.ambient_light_energy = lerpf(0.28, 0.8, day)
	env.fog_light_color = horizon.lerp(Color(0.7, 0.78, 0.86), day * 0.6)

	var lamp := world.batcher.materials.get("lamp") as StandardMaterial3D
	if lamp:
		lamp.emission_energy_multiplier = lerpf(6.0, 0.6, day)
	for i in _facades.size():
		_facades[i].set_shader_parameter("lit_chance", lerpf(0.5, _facade_lit[i] * 0.4, day))
	if nature:
		nature.set_light(Color(0.18, 0.2, 0.26).lerp(Color(1, 1, 1), day).lerp(Color(1.0, 0.72, 0.55), dusk * 0.7))
