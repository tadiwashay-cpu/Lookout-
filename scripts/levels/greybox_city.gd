extends Node3D
## Greybox of the old market district of Port Halden — the "Clean Hands" level.
##
## This is a LAYOUT pass, not final art: block massing, street widths, sight
## lines and fight spaces, built procedurally so the district can be resized
## and re-seeded from the inspector. Art direction for the real pass is in
## docs/art-direction.md — weathered brick, concrete, sodium streetlights,
## overcast harbour light. No neon.

const PLAYER_SCENE := preload("res://scenes/characters/player.tscn")
const GOON_SCENE := preload("res://scenes/characters/goon.tscn")

@export var blocks_x: int = 5
@export var blocks_z: int = 5
@export var block_size: float = 42.0
@export var street_width: float = 14.0
@export var city_seed: int = 1977
@export var goon_squads: int = 4
@export var goons_per_squad: int = 3

var _rng := RandomNumberGenerator.new()
var _mat := {}
var _pitch := 0.0
var _player: PlayerController


func _ready() -> void:
	_rng.seed = city_seed
	_pitch = block_size + street_width
	_build_materials()
	_build_environment()
	_build_ground()
	_build_blocks()
	_build_street_markings()

	_player = PLAYER_SCENE.instantiate() as PlayerController
	_player.position = Vector3(_pitch * 0.5, 0.2, _pitch * 0.5)   # an intersection
	add_child(_player)

	var challenge := CleanHandsChallenge.new()
	challenge.name = "CleanHands"
	add_child(challenge)
	challenge.track_player(_player)

	var hud := GameHUD.new()
	add_child(hud)
	hud.bind_player(_player)
	hud.bind_challenge(challenge)

	var touch_layer := CanvasLayer.new()
	touch_layer.layer = 11
	add_child(touch_layer)
	var touch := TouchControls.new()
	touch.player = _player
	touch_layer.add_child(touch)

	_spawn_goons(challenge)
	challenge.goons_required = mini(challenge.goons_required, goon_squads * goons_per_squad)
	challenge.start()


# ------------------------------------------------------------------ lighting

func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.35, 0.43, 0.53)
	sky_material.sky_horizon_color = Color(0.71, 0.67, 0.6)
	sky_material.ground_horizon_color = Color(0.45, 0.42, 0.38)
	sky_material.ground_bottom_color = Color(0.18, 0.17, 0.16)
	var sky := Sky.new()
	sky.sky_material = sky_material

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.66, 0.64, 0.6)
	env.fog_density = 0.004
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.88
	env.adjustment_contrast = 1.06
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Low late-afternoon sun: long shadows down the streets.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-32.0, -38.0, 0.0)
	sun.light_color = Color(1.0, 0.89, 0.76)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 80.0
	add_child(sun)


func _build_materials() -> void:
	var grime := FastNoiseLite.new()
	grime.frequency = 0.02
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.72, 0.72))
	ramp.set_color(1, Color(1, 1, 1))
	var grime_tex := NoiseTexture2D.new()
	grime_tex.noise = grime
	grime_tex.seamless = true
	grime_tex.color_ramp = ramp
	grime_tex.width = 256
	grime_tex.height = 256

	_mat["asphalt"] = _make_material(Color(0.17, 0.17, 0.18), 0.92, grime_tex)
	_mat["sidewalk"] = _make_material(Color(0.52, 0.51, 0.49), 0.88, grime_tex)
	_mat["curb"] = _make_material(Color(0.42, 0.41, 0.4), 0.85, null)
	_mat["roof"] = _make_material(Color(0.22, 0.21, 0.21), 0.9, grime_tex)
	_mat["storefront"] = _make_material(Color(0.1, 0.11, 0.12), 0.35, null)
	_mat["line"] = _make_material(Color(0.78, 0.7, 0.42), 0.8, null)
	_mat["metal"] = _make_material(Color(0.25, 0.26, 0.27), 0.5, null)
	(_mat["metal"] as StandardMaterial3D).metallic = 0.7
	_mat["dumpster"] = _make_material(Color(0.16, 0.25, 0.19), 0.7, null)

	var lamp := _make_material(Color(1.0, 0.72, 0.38), 0.5, null)   # sodium vapour
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.62, 0.28)
	lamp.emission_energy_multiplier = 2.0
	_mat["lamp"] = lamp

	# Facade palette: old brick, concrete, sandstone, painted render, soot-dark stone.
	_mat["facades"] = [
		_make_material(Color(0.45, 0.23, 0.17), 0.9, grime_tex),
		_make_material(Color(0.36, 0.2, 0.16), 0.9, grime_tex),
		_make_material(Color(0.55, 0.54, 0.51), 0.85, grime_tex),
		_make_material(Color(0.63, 0.55, 0.42), 0.88, grime_tex),
		_make_material(Color(0.7, 0.66, 0.57), 0.85, grime_tex),
		_make_material(Color(0.3, 0.29, 0.28), 0.9, grime_tex),
	]
	_mat["cars"] = [
		_make_material(Color(0.32, 0.08, 0.07), 0.35, null),
		_make_material(Color(0.12, 0.17, 0.24), 0.35, null),
		_make_material(Color(0.58, 0.57, 0.53), 0.35, null),
		_make_material(Color(0.09, 0.09, 0.1), 0.3, null),
		_make_material(Color(0.36, 0.33, 0.22), 0.4, null),
	]


func _make_material(color: Color, roughness: float, texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	if texture:
		material.albedo_texture = texture
		material.uv1_triplanar = true
		material.uv1_scale = Vector3(0.08, 0.08, 0.08)
	return material


# ----------------------------------------------------------------- geometry

func _build_ground() -> void:
	var extent := _pitch * (maxi(blocks_x, blocks_z) + 2)
	_add_solid(Vector3(extent, 1.0, extent), Vector3(0, -0.5, 0), _mat["asphalt"])


func _block_center(ix: int, iz: int) -> Vector3:
	return Vector3((ix - (blocks_x - 1) * 0.5) * _pitch, 0.0, (iz - (blocks_z - 1) * 0.5) * _pitch)


func _build_blocks() -> void:
	var max_dist := Vector2(blocks_x, blocks_z).length() * 0.5
	for ix in blocks_x:
		for iz in blocks_z:
			var center := _block_center(ix, iz)
			# Sidewalk slab + curb.
			_add_solid(Vector3(block_size, 0.18, block_size), center + Vector3(0, 0.09, 0), _mat["sidewalk"])
			# Downtown is taller toward the middle of the grid.
			var centrality := 1.0 - Vector2(ix - (blocks_x - 1) * 0.5, iz - (blocks_z - 1) * 0.5).length() / max_dist
			if _rng.randf() < 0.12:
				_build_square(center)
			else:
				_build_lots(center, centrality)
			_build_streetlights(center)


## Four lots per block with a service alley between them.
func _build_lots(center: Vector3, centrality: float) -> void:
	var inset := 3.0
	var alley := 4.0
	var lot := (block_size - inset * 2.0 - alley) * 0.5
	for qx: float in [-1.0, 1.0]:
		for qz: float in [-1.0, 1.0]:
			var lot_center := center + Vector3(qx, 0.0, qz) * (lot * 0.5 + alley * 0.5)
			var height := lerpf(9.0, 58.0, pow(centrality, 1.6)) * _rng.randf_range(0.55, 1.15)
			height = maxf(height, 7.0)
			_build_building(lot_center, Vector2(lot, lot) * _rng.randf_range(0.82, 1.0), height)
	if _rng.randf() < 0.7:
		var dumpster_pos := center + Vector3(_rng.randf_range(-6, 6), 0.18, alley * 0.25)
		_add_solid(Vector3(2.0, 1.4, 1.1), dumpster_pos + Vector3(0, 0.7, 0), _mat["dumpster"])


func _build_building(base: Vector3, footprint: Vector2, height: float) -> void:
	var facades: Array = _mat["facades"]
	var facade: Material = facades[_rng.randi() % facades.size()]
	var size := Vector3(footprint.x, height, footprint.y)
	_add_solid(size, base + Vector3(0, 0.18 + height * 0.5, 0), facade)
	# Recessed dark ground-floor storefront band.
	_add_visual(Vector3(footprint.x + 0.06, 3.6, footprint.y + 0.06), base + Vector3(0, 2.0, 0), _mat["storefront"])
	# Cornice / parapet cap.
	_add_visual(Vector3(footprint.x + 0.5, 0.6, footprint.y + 0.5), base + Vector3(0, 0.18 + height + 0.3, 0), _mat["roof"])
	# Older low-rise brick gets rooftop water tanks.
	if height < 26.0 and _rng.randf() < 0.35:
		var tank := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 1.4
		cylinder.bottom_radius = 1.4
		cylinder.height = 3.0
		tank.mesh = cylinder
		tank.material_override = _mat["metal"]
		tank.position = base + Vector3(_rng.randf_range(-2, 2), height + 2.4, _rng.randf_range(-2, 2))
		add_child(tank)


## Occasional open market square — a natural arena for fights.
func _build_square(center: Vector3) -> void:
	for i in 6:
		var stall := center + Vector3(_rng.randf_range(-14, 14), 0.18, _rng.randf_range(-14, 14))
		_add_solid(Vector3(3.0, 1.0, 1.6), stall + Vector3(0, 0.5, 0), _mat["metal"])
		_add_visual(Vector3(3.4, 0.1, 2.2), stall + Vector3(0, 2.3, 0), (_mat["cars"] as Array)[i % 5])


func _build_streetlights(center: Vector3) -> void:
	var half := block_size * 0.5 - 0.8
	for corner: Vector3 in [Vector3(half, 0, half), Vector3(-half, 0, half), Vector3(half, 0, -half), Vector3(-half, 0, -half)]:
		var base := center + corner
		_add_visual(Vector3(0.18, 7.0, 0.18), base + Vector3(0, 3.6, 0), _mat["metal"])
		var arm_dir := -corner.normalized()
		_add_visual(Vector3(0.12, 0.12, 0.12) + Vector3(absf(arm_dir.x), 0, absf(arm_dir.z)) * 1.2,
			base + Vector3(0, 7.0, 0) - arm_dir * 0.6, _mat["metal"])
		_add_visual(Vector3(0.5, 0.18, 0.5), base + Vector3(0, 6.9, 0) - arm_dir * 1.2, _mat["lamp"])
	# Parked cars along the block edge.
	for i in 2:
		var side := 1.0 if _rng.randf() > 0.5 else -1.0
		var along := _rng.randf_range(-block_size * 0.35, block_size * 0.35)
		var horizontal := _rng.randf() > 0.5
		var offset := block_size * 0.5 + 1.6
		var pos := center + (Vector3(along, 0, offset * side) if horizontal else Vector3(offset * side, 0, along))
		_build_car(pos, horizontal)


func _build_car(pos: Vector3, along_x: bool) -> void:
	var cars: Array = _mat["cars"]
	var paint: Material = cars[_rng.randi() % cars.size()]
	var length := _rng.randf_range(4.2, 4.9)
	var body := Vector3(length, 0.8, 1.8) if along_x else Vector3(1.8, 0.8, length)
	var cabin := Vector3(length * 0.55, 0.62, 1.6) if along_x else Vector3(1.6, 0.62, length * 0.55)
	_add_solid(body, pos + Vector3(0, 0.55, 0), paint)
	_add_visual(cabin, pos + Vector3(0, 1.26, 0), _mat["storefront"])


func _build_street_markings() -> void:
	# Dashed centre lines drawn with one MultiMesh: hundreds of dashes, one draw call.
	var dash := BoxMesh.new()
	dash.size = Vector3(0.15, 0.02, 2.2)
	var transforms: Array[Transform3D] = []
	var span := _pitch * maxi(blocks_x, blocks_z)
	for line in range(-1, maxi(blocks_x, blocks_z)):
		var offset := (line + 0.5 - (maxi(blocks_x, blocks_z) - 1) * 0.5) * _pitch
		var t := -span * 0.5
		while t < span * 0.5:
			transforms.append(Transform3D(Basis(), Vector3(offset, 0.01, t)))
			transforms.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(t, 0.01, offset)))
			t += 6.0
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.mesh = dash
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = _mat["line"]
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


# ------------------------------------------------------------------- enemies

func _spawn_goons(challenge: CleanHandsChallenge) -> void:
	var player_pos := _player.position
	var spawned := 0
	var attempts := 0
	while spawned < goon_squads and attempts < 50:
		attempts += 1
		var ix := _rng.randi_range(0, blocks_x)
		var iz := _rng.randi_range(0, blocks_z)
		# Intersections sit half a pitch off block centres.
		var spot := _block_center(ix, iz) - Vector3(_pitch * 0.5, 0, _pitch * 0.5)
		if spot.distance_to(player_pos) < 25.0:
			continue
		for i in goons_per_squad:
			var goon := GOON_SCENE.instantiate() as Goon
			goon.position = spot + Vector3(_rng.randf_range(-3, 3), 0.2, _rng.randf_range(-3, 3))
			add_child(goon)
			challenge.track_goon(goon)
		spawned += 1


# ------------------------------------------------------------------- helpers

func _add_solid(size: Vector3, pos: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	body.add_child(shape)
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	body.add_child(visual)
	add_child(body)


func _add_visual(size: Vector3, pos: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.position = pos
	add_child(visual)
