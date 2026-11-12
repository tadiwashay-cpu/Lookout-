class_name City
extends RefCounted
## Downtown: a street grid, raised sidewalks, buildings (unit boxes in
## MultiMeshes with world-space PBR facades and night windows), street
## lights and street furniture. Downtown towers rise towards the centre.

const FACADES := [
	["rectangular_facade_tiles", 0.22, 0.75],
	["concrete_tile_facade", 0.25, 0.6],
	["brick_4", 0.3, 0.45],
	["grey_plaster", 0.25, 0.55],
]

var w: Node3D
var rng := RandomNumberGenerator.new()
## Every building: {"rect": Rect2, "height": float, "door": Vector3, "face": Vector3}
var buildings: Array[Dictionary] = []
var lamps: Array[Vector3] = []
var facade_materials: Array[ShaderMaterial] = []
var lamp_material: StandardMaterial3D
var sidewalk_points: Array[Vector3] = []   # where pedestrians may walk
var _reserved: Array[Rect2] = []


func _init(world: Node3D, seed_value: int) -> void:
	w = world
	rng.seed = seed_value


## Lots kept free for special buildings (services) before the fill.
func reserve(rect: Rect2) -> void:
	_reserved.append(rect)


func build() -> void:
	var y := Layout.CITY_Y
	# Asphalt over the whole city footprint.
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Layout.CITY_RECT.size
	ground.mesh = plane
	ground.material_override = _street_material()
	ground.position = Vector3(Layout.CITY_RECT.get_center().x, y + 0.03, Layout.CITY_RECT.get_center().y)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	w.add_child(ground)
	var body := StaticBody3D.new()
	body.name = "CityBody"
	body.collision_layer = Game.L_WORLD
	w.add_child(body)
	Mats.box_collider(body, Vector3(ground.position.x, y - 0.5, ground.position.z), Vector3(Layout.CITY_RECT.size.x, 1.0, Layout.CITY_RECT.size.y))
	for m in FACADES:
		var mat := ShaderMaterial.new()
		mat.shader = load("res://assets/shaders/facade.gdshader")
		mat.set_shader_parameter("wall_d", Mats.tex(m[0], "diff"))
		mat.set_shader_parameter("wall_n", Mats.tex(m[0], "nor"))
		mat.set_shader_parameter("roof_d", Mats.tex("concrete_block_wall", "diff"))
		mat.set_shader_parameter("wall_scale", m[1])
		mat.set_shader_parameter("glass", m[2])
		facade_materials.append(mat)
	var per_facade: Array = [[], [], [], []]   # [Transform3D, Color]
	var walk := []
	var center := Vector2(40.0, -60.0)
	for ix in Layout.CITY_X.size() - 1:
		for iz in Layout.CITY_Z.size() - 1:
			var x0: float = Layout.CITY_X[ix] + Layout.STREET_W * 0.5
			var x1: float = Layout.CITY_X[ix + 1] - Layout.STREET_W * 0.5
			var z0: float = Layout.CITY_Z[iz] + Layout.STREET_W * 0.5
			var z1: float = Layout.CITY_Z[iz + 1] - Layout.STREET_W * 0.5
			var block := Rect2(x0, z0, x1 - x0, z1 - z0)
			walk.append(block)
			# Sidewalk slab (with its curb), building lots inside it.
			var slab := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(block.size.x, 0.25, block.size.y)
			slab.mesh = box
			slab.material_override = Mats.pbr("brushed_concrete", 3.0, Color(0.85, 0.85, 0.83))
			slab.position = Vector3(block.get_center().x, y + 0.12, block.get_center().y)
			slab.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			w.add_child(slab)
			Mats.box_collider(body, slab.position, box.size)
			var inner := block.grow(-5.0)
			var downtown := 1.0 - clampf(block.get_center().distance_to(center) / 380.0, 0.0, 1.0)
			_fill_block(inner, downtown, per_facade, body)
	for i in FACADES.size():
		_flush(per_facade[i], facade_materials[i])
	_street_lights()
	_furniture(walk)
	for block: Rect2 in walk:
		for k in 6:
			var t := float(k) / 6.0
			sidewalk_points.append(Vector3(lerpf(block.position.x, block.end.x, t), y + 0.3, block.position.y + 2.0))
			sidewalk_points.append(Vector3(lerpf(block.position.x, block.end.x, t), y + 0.3, block.end.y - 2.0))


func _street_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
uniform sampler2D asphalt_d : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D asphalt_n : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float pitch = 120.0;
uniform vec2 origin = vec2(-320.0, -360.0);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec3 c = texture(asphalt_d, wpos.xz * 0.25).rgb * 0.75;
	vec2 g = wpos.xz - origin;
	vec2 m = mod(g + pitch * 0.5, pitch) - pitch * 0.5;   // distance to nearest street centre per axis
	float on_x = step(abs(m.x), 10.0);
	float on_z = step(abs(m.y), 10.0);
	float junction = on_x * on_z;
	float paint = 0.0;
	// centre lines (double yellow), dashed lane lines, crosswalks at junction edges
	float yx = step(0.1, abs(m.x)) * step(abs(m.x), 0.25) * on_x * (1.0 - on_z);
	float yz = step(0.1, abs(m.y)) * step(abs(m.y), 0.25) * on_z * (1.0 - on_x);
	float dx = step(abs(abs(m.x) - 5.0), 0.08) * step(fract(wpos.z / 9.0), 0.5) * on_x * (1.0 - on_z);
	float dz = step(abs(abs(m.y) - 5.0), 0.08) * step(fract(wpos.x / 9.0), 0.5) * on_z * (1.0 - on_x);
	float cw_band_x = on_x * step(10.0, abs(m.y)) * step(abs(m.y), 13.0) * step(fract(wpos.x / 1.2), 0.5);
	float cw_band_z = on_z * step(10.0, abs(m.x)) * step(abs(m.x), 13.0) * step(fract(wpos.z / 1.2), 0.5);
	paint = clamp(dx + dz + cw_band_x + cw_band_z, 0.0, 1.0);
	c = mix(c, vec3(0.86), paint * 0.9);
	c = mix(c, vec3(0.85, 0.65, 0.12), clamp(yx + yz, 0.0, 1.0) * 0.9);
	ALBEDO = c;
	NORMAL_MAP = texture(asphalt_n, wpos.xz * 0.25).rgb;
	ROUGHNESS = mix(0.8, 0.5, paint);
}
"""
	mat.shader = sh
	mat.set_shader_parameter("asphalt_d", Mats.tex("asphalt_02", "diff"))
	mat.set_shader_parameter("asphalt_n", Mats.tex("asphalt_02", "nor"))
	mat.set_shader_parameter("pitch", 120.0)
	mat.set_shader_parameter("origin", Vector2(Layout.CITY_X[0], Layout.CITY_Z[0]))
	return mat


func _fill_block(inner: Rect2, downtown: float, per_facade: Array, body: StaticBody3D) -> void:
	# Split the block into 2-4 lots along its long side, sometimes a plaza.
	var long_x := inner.size.x >= inner.size.y
	var count := rng.randi_range(2, 4)
	var cursor := 0.0
	var total := inner.size.x if long_x else inner.size.y
	for i in count:
		var span := total / count
		var lot := Rect2(inner.position + (Vector2(cursor, 0) if long_x else Vector2(0, cursor)), Vector2(span, inner.size.y) if long_x else Vector2(inner.size.x, span))
		cursor += span
		lot = lot.grow(-1.5)
		var blocked := false
		for r in _reserved:
			if r.intersects(lot):
				blocked = true
		if blocked or rng.randf() < 0.08:
			continue
		var height := lerpf(10.0, 24.0, rng.randf()) + downtown * downtown * rng.randf_range(20.0, 95.0)
		height = snappedf(height, 3.4) + 0.6
		_add_building(lot, height, per_facade, body)
		# Downtown: some towers get a narrower top section.
		if height > 45.0 and rng.randf() < 0.6:
			var top := lot.grow(-lot.size.x * 0.18)
			_add_building_at(top, height, height * rng.randf_range(0.25, 0.5), per_facade, body)


func _add_building(lot: Rect2, height: float, per_facade: Array, body: StaticBody3D) -> void:
	_add_building_at(lot, 0.0, height, per_facade, body)
	var c := lot.get_center()
	# Door on the side facing the nearest street.
	var face := Vector3.ZERO
	var best := INF
	for dir in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var edge := c + Vector2(dir.x * lot.size.x * 0.5, dir.z * lot.size.y * 0.5)
		var d := _street_distance(edge)
		if d < best:
			best = d
			face = dir
	var door := Vector3(c.x, Layout.CITY_Y + 0.25, c.y) + Vector3(face.x * (lot.size.x * 0.5 + 1.2), 0, face.z * (lot.size.y * 0.5 + 1.2))
	buildings.append({"rect": lot, "height": height, "door": door, "face": face})


func _add_building_at(lot: Rect2, base: float, height: float, per_facade: Array, body: StaticBody3D) -> void:
	var kind := rng.randi() % FACADES.size()
	var center := Vector3(lot.get_center().x, Layout.CITY_Y + 0.25 + base + height * 0.5, lot.get_center().y)
	var size := Vector3(lot.size.x, height, lot.size.y)
	var tint := Color.from_hsv(rng.randf(), rng.randf_range(0.0, 0.25), rng.randf_range(0.75, 1.0))
	tint.a = 1.0 if rng.randf() < 0.7 else 0.0   # shop windows on the ground floor
	(per_facade[kind] as Array).append([Transform3D(Basis.from_scale(size), center), tint])
	Mats.box_collider(body, center, size)


func _flush(items: Array, mat: Material) -> void:
	if items.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var box := BoxMesh.new()
	mm.mesh = box
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i][0])
		mm.set_instance_custom_data(i, items[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	w.add_child(mmi)


func _street_distance(p: Vector2) -> float:
	var best := INF
	for x: float in Layout.CITY_X:
		best = minf(best, absf(p.x - x))
	for z: float in Layout.CITY_Z:
		best = minf(best, absf(p.y - z))
	return best


func _street_lights() -> void:
	var y := Layout.CITY_Y + 0.25
	var poles: Array = []
	var heads: Array = []
	for x: float in Layout.CITY_X:
		var z: float = Layout.CITY_Z[0]
		while z < Layout.CITY_Z[Layout.CITY_Z.size() - 1]:
			for side in [-1.0, 1.0]:
				var base := Vector3(x + side * (Layout.STREET_W * 0.5 + 0.8), y, z + 30.0)
				if _clear_of_junction(base):
					poles.append(Transform3D(Basis.from_scale(Vector3(0.18, 8.0, 0.18)), base + Vector3.UP * 4.0))
					var head := base + Vector3(-side * 1.6, 7.9, 0)
					heads.append(Transform3D(Basis.from_scale(Vector3(0.9, 0.18, 0.45)), head))
					lamps.append(head)
			z += 40.0
	for z: float in Layout.CITY_Z:
		var x: float = Layout.CITY_X[0]
		while x < Layout.CITY_X[Layout.CITY_X.size() - 1]:
			for side in [-1.0, 1.0]:
				var base := Vector3(x + 30.0, y, z + side * (Layout.STREET_W * 0.5 + 0.8))
				if _clear_of_junction(base):
					poles.append(Transform3D(Basis.from_scale(Vector3(0.18, 8.0, 0.18)), base + Vector3.UP * 4.0))
					var head := base + Vector3(0, 7.9, -side * 1.6)
					heads.append(Transform3D(Basis.from_scale(Vector3(0.45, 0.18, 0.9)), head))
					lamps.append(head)
			x += 40.0
	var pole := CylinderMesh.new()
	pole.top_radius = 0.5
	pole.bottom_radius = 0.6
	pole.height = 1.0
	pole.radial_segments = 8
	pole.material = Mats.flat(Color(0.12, 0.13, 0.14), 0.4, 0.8)
	Mats.scatter(w, pole, poles, true, 350.0)
	var cap := BoxMesh.new()
	lamp_material = Mats.glow(Color(1.0, 0.85, 0.6), 0.0).duplicate()
	cap.material = lamp_material
	var mmi := Mats.scatter(w, cap, heads, false, 600.0)
	mmi.name = "LampHeads"


func _clear_of_junction(p: Vector3) -> bool:
	for x: float in Layout.CITY_X:
		for z: float in Layout.CITY_Z:
			if absf(p.x - x) < 16.0 and absf(p.z - z) < 16.0:
				return false
	return true


func _furniture(blocks: Array) -> void:
	var hydrant := Mats.prop("fire_hydrant")
	var bin := Mats.prop("metal_trash_can")
	var barrier := Mats.prop("concrete_road_barrier")
	var aircon := Mats.prop("exterior_aircon_unit")
	var hyd: Array = []
	var bins: Array = []
	for block: Rect2 in blocks:
		for k in 3:
			var x := rng.randf_range(block.position.x + 4.0, block.end.x - 4.0)
			var edge_z := block.position.y + 1.2 if rng.randf() < 0.5 else block.end.y - 1.2
			var p := Vector3(x, Layout.CITY_Y + 0.25, edge_z)
			if k == 0:
				hyd.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
			else:
				bins.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), p))
	Mats.scatter(w, hydrant["mesh"], hyd, true, 160.0)
	Mats.scatter(w, bin["mesh"], bins, true, 160.0)
	# Roadworks barriers and rooftop units for detail.
	var bars: Array = []
	for i in 14:
		var x: float = Layout.CITY_X[rng.randi() % Layout.CITY_X.size()]
		var z := rng.randf_range(Layout.CITY_Z[0], Layout.CITY_Z[Layout.CITY_Z.size() - 1])
		bars.append(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(x + Layout.STREET_W * 0.5 - 1.0, Layout.CITY_Y + 0.05, z)))
	Mats.scatter(w, barrier["mesh"], bars, true, 200.0)
	var roof: Array = []
	for b in buildings:
		if rng.randf() < 0.5:
			var r: Rect2 = b["rect"]
			roof.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(r.get_center().x + rng.randf_range(-3, 3), Layout.CITY_Y + 0.25 + float(b["height"]), r.get_center().y + rng.randf_range(-3, 3))))
	Mats.scatter(w, aircon["mesh"], roof, false, 300.0)


func set_night(amount: float) -> void:
	for m in facade_materials:
		m.set_shader_parameter("night", amount)
	if lamp_material:
		lamp_material.emission_energy_multiplier = 0.2 + amount * 6.0
