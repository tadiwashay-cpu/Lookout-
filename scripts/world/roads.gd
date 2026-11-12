class_name Roads
extends RefCounted
## The roads between regions: Catmull-Rom splines sampled every few metres,
## heights following the land but smoothed (gentle grades over the pass),
## drawn as asphalt ribbons with their own colliders. Terrain asks
## `influence()` to flatten itself under them.

const STEP := 4.0
const GRID := 32.0
const BLEND := 16.0

## name -> Array[Vector3] (centre line with heights)
var paths: Dictionary = {}
var _grid: Dictionary = {}      # Vector2i -> Array[[Vector3 a, Vector3 b]]


func build_paths() -> void:
	for road_name: String in Layout.ROADS:
		var pts: Array = Layout.ROADS[road_name]
		var samples: Array[Vector3] = []
		for i in pts.size() - 1:
			var p0: Vector2 = pts[maxi(i - 1, 0)]
			var p1: Vector2 = pts[i]
			var p2: Vector2 = pts[i + 1]
			var p3: Vector2 = pts[mini(i + 2, pts.size() - 1)]
			var n := maxi(int(p1.distance_to(p2) / STEP), 1)
			for k in n:
				var t := float(k) / n
				var q := _catmull(p0, p1, p2, p3, t)
				samples.append(Vector3(q.x, Terrain.base_height(q.x, q.y), q.y))
		var last: Vector2 = pts[pts.size() - 1]
		samples.append(Vector3(last.x, Terrain.base_height(last.x, last.y), last.y))
		# Smooth the profile (no bumps, sensible grades) but keep both ends at
		# the height of what they join.
		for pass_i in 6:
			var copy := samples.duplicate()
			for i in range(1, samples.size() - 1):
				var acc := 0.0
				var cnt := 0
				for j in range(maxi(i - 8, 0), mini(i + 9, samples.size())):
					acc += copy[j].y
					cnt += 1
				samples[i].y = acc / cnt
		# Real roads: at most an 8% grade, and both ends sit on the ground they
		# join. Where the land is steeper the road cuts into it or rides an
		# embankment (the terrain follows the road).
		var g := 0.08
		var y0: float = Terrain.base_height(samples[0].x, samples[0].z)
		var yn: float = Terrain.base_height(samples[samples.size() - 1].x, samples[samples.size() - 1].z)
		var dist: Array[float] = [0.0]
		for i in range(1, samples.size()):
			dist.append(dist[i - 1] + Vector2(samples[i].x - samples[i - 1].x, samples[i].z - samples[i - 1].z).length())
		var total: float = dist[dist.size() - 1]
		for i in samples.size():
			var lo := maxf(y0 - g * dist[i], yn - g * (total - dist[i]))
			var hi := minf(y0 + g * dist[i], yn + g * (total - dist[i]))
			samples[i].y = clampf(samples[i].y, lo, hi) if lo <= hi else (lo + hi) * 0.5
		samples[0].y = y0
		samples[samples.size() - 1].y = yn
		for i in samples.size():
			samples[i].y = maxf(samples[i].y, Layout.CITY_Y)
			var near_city := maxf(Layout.in_rect_soft(Vector2(samples[i].x, samples[i].z), Layout.CITY_RECT, 40.0),
				Layout.in_rect_soft(Vector2(samples[i].x, samples[i].z), Layout.HARBOUR_RECT, 40.0))
			samples[i].y = lerpf(samples[i].y, Layout.CITY_Y, near_city)
		paths[road_name] = samples
		for i in samples.size() - 1:
			_index(samples[i], samples[i + 1])


func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


func _index(a: Vector3, b: Vector3) -> void:
	var reach := Layout.ROAD_HALF_WIDTH + 6.0 + BLEND + 2.0
	var x0 := floori((minf(a.x, b.x) - reach) / GRID)
	var x1 := floori((maxf(a.x, b.x) + reach) / GRID)
	var z0 := floori((minf(a.z, b.z) - reach) / GRID)
	var z1 := floori((maxf(a.z, b.z) + reach) / GRID)
	for gx in range(x0, x1 + 1):
		for gz in range(z0, z1 + 1):
			var key := Vector2i(gx, gz)
			if not _grid.has(key):
				_grid[key] = []
			(_grid[key] as Array).append([a, b])


## How strongly a road flattens the land here (0..1) and the road's height.
func influence(x: float, z: float) -> Vector2:
	var key := Vector2i(floori(x / GRID), floori(z / GRID))
	if not _grid.has(key):
		return Vector2.ZERO
	var best := INF
	var height := 0.0
	var p := Vector2(x, z)
	for seg: Array in _grid[key]:
		var a: Vector3 = seg[0]
		var b: Vector3 = seg[1]
		var a2 := Vector2(a.x, a.z)
		var ab := Vector2(b.x, b.z) - a2
		var t := clampf((p - a2).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := p.distance_to(a2 + ab * t)
		if d < best:
			best = d
			height = lerpf(a.y, b.y, t)
	# Fully flat out to 6 m past the edge (the 8 m terrain grid must not rise
	# across the road), then blend into the land.
	var w := 1.0 - smoothstep(Layout.ROAD_HALF_WIDTH + 6.0, Layout.ROAD_HALF_WIDTH + 6.0 + BLEND, best)
	return Vector2(w, height)


## Asphalt ribbons + colliders.
func build_meshes(parent: Node3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/road.gdshader")
	mat.set_shader_parameter("asphalt_d", Mats.tex("asphalt_02", "diff"))
	mat.set_shader_parameter("asphalt_n", Mats.tex("asphalt_02", "nor"))
	mat.set_shader_parameter("width", Layout.ROAD_HALF_WIDTH * 2.0)
	var body := StaticBody3D.new()
	body.name = "Roads"
	body.collision_layer = Game.L_WORLD
	parent.add_child(body)
	for road_name: String in paths:
		var s: Array = paths[road_name]
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var faces := PackedVector3Array()
		var along := 0.0
		for i in s.size() - 1:
			var a: Vector3 = s[i] + Vector3.UP * 0.06
			var b: Vector3 = s[i + 1] + Vector3.UP * 0.06
			var da := _dir(s, i)
			var db := _dir(s, i + 1)
			var sa := Vector3(-da.z, 0, da.x) * Layout.ROAD_HALF_WIDTH
			var sb := Vector3(-db.z, 0, db.x) * Layout.ROAD_HALF_WIDTH
			var len_ab := a.distance_to(b)
			var q := [[a - sa, Vector2(0, along)], [a + sa, Vector2(1, along)], [b + sb, Vector2(1, along + len_ab)], [b - sb, Vector2(0, along + len_ab)]]
			for idx in [0, 2, 1, 0, 3, 2]:
				st.set_normal(Vector3.UP)
				st.set_uv(q[idx][1])
				st.add_vertex(q[idx][0])
				faces.append(q[idx][0])
			along += len_ab
		st.generate_tangents()
		var mi := MeshInstance3D.new()
		mi.name = road_name
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)


func _dir(s: Array, i: int) -> Vector3:
	var a: Vector3 = s[maxi(i - 1, 0)]
	var b: Vector3 = s[mini(i + 1, s.size() - 1)]
	var d := b - a
	d.y = 0.0
	return d.normalized()


## A route through the network: road names, or "city:x,z>x,z" straight runs
## along city streets. Returns points every few metres (for racing).
func route(parts: Array) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for part: String in parts:
		if part.begins_with("city:"):
			var ends := part.substr(5).split(">")
			var a := _parse(ends[0])
			var b := _parse(ends[1])
			var n := maxi(int(a.distance_to(b) / 8.0), 1)
			for k in n + 1:
				out.append(a.lerp(b, float(k) / n))
		else:
			var s: Array = paths[part]
			for k in range(0, s.size(), 2):
				out.append(s[k] + Vector3.UP * 0.1)
	return out


func _parse(t: String) -> Vector3:
	var xy := t.split(",")
	return Vector3(float(xy[0]), Layout.CITY_Y + 0.1, float(xy[1]))
