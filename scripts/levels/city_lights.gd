class_name CityLights
extends Node3D
## Street lights of the modelled city: every lamp head glows at night (one
## MultiMesh), and a small pool of real lights follows the lamps nearest the
## player so the street around you is actually lit.

const POOL := 6

var world: World
var _glow: MultiMeshInstance3D
var _pool: Array[OmniLight3D] = []
var _night := 0.0
var _tick := 0.0


func setup(lamps: Array[Vector3]) -> void:
	var bulb := SphereMesh.new()
	bulb.radius = 0.6
	bulb.height = 0.8
	bulb.radial_segments = 8
	bulb.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.86, 0.58)
	bulb.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bulb
	mm.instance_count = lamps.size()
	for i in lamps.size():
		mm.set_instance_transform(i, Transform3D(Basis(), lamps[i]))
	_glow = MultiMeshInstance3D.new()
	_glow.multimesh = mm
	_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow.visible = false
	add_child(_glow)
	for i in POOL:
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.82, 0.55)
		light.omni_range = 30.0
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		_pool.append(light)
	set_meta(&"lamps", lamps)


func set_night(amount: float) -> void:
	_night = amount
	_glow.visible = amount > 0.25
	for light in _pool:
		light.visible = amount > 0.25
		light.light_energy = 5.0 * amount


func _process(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or _night <= 0.25 or world.player == null:
		return
	_tick = 0.6
	var focus := world.player.current_vehicle.global_position if world.player.current_vehicle else world.player.global_position
	var lamps: Array[Vector3] = get_meta(&"lamps")
	var near: Array = []
	for lamp in lamps:
		var d := lamp.distance_squared_to(focus)
		if d < 90.0 * 90.0:
			near.append([d, lamp])
	near.sort_custom(func(p: Array, q: Array) -> bool: return p[0] < q[0])
	for i in POOL:
		_pool[i].visible = i < near.size()
		if i < near.size():
			_pool[i].global_position = (near[i][1] as Vector3) + Vector3.DOWN * 0.6
