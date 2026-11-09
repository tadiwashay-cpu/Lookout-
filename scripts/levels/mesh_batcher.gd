class_name MeshBatcher
extends RefCounted
## Merges thousands of static boxes/prisms into one mesh per (area chunk,
## material) — a few dozen draw calls for a whole district instead of
## thousands — and gives each chunk one StaticBody3D with box colliders.
## Chunks fade out beyond the view distance (Settings > Graphics).

const WORLD_LAYER := 1

var chunk_size := 128.0
var view_distance := 350.0
var materials: Dictionary = {}          # key -> Material

var _unit_box := BoxMesh.new()
var _tools: Dictionary = {}             # "cx,cz|key" -> SurfaceTool
var _chunk_of_tool: Dictionary = {}     # same key -> Vector2i
var _bodies: Dictionary = {}            # Vector2i -> StaticBody3D
var _root: Node3D


func _init(root: Node3D, distance: float) -> void:
	_root = root
	view_distance = distance
	_unit_box.size = Vector3.ONE


func _chunk(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / chunk_size), floori(pos.z / chunk_size))


func _chunk_center(chunk: Vector2i) -> Vector3:
	return Vector3((chunk.x + 0.5) * chunk_size, 0.0, (chunk.y + 0.5) * chunk_size)


func _tool(chunk: Vector2i, key: String) -> SurfaceTool:
	var id := "%d,%d|%s" % [chunk.x, chunk.y, key]
	if not _tools.has(id):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[id] = st
		_chunk_of_tool[id] = chunk
	return _tools[id]


## Axis-aligned (optionally yaw-rotated) box. `solid` adds a collider.
func box(size: Vector3, center: Vector3, key: String, solid: bool = true, yaw: float = 0.0) -> void:
	# Scale first (in the box's own axes), then rotate.
	var basis := Basis(Vector3.UP, yaw) * Basis.from_scale(size)
	mesh(_unit_box, Transform3D(basis, center), key)
	if solid:
		collider_box(size, center, yaw)


## Any mesh (e.g. PrismMesh roofs) placed with a world transform.
func mesh(source: Mesh, xform: Transform3D, key: String) -> void:
	var chunk := _chunk(xform.origin)
	var local := xform
	local.origin -= _chunk_center(chunk)
	_tool(chunk, key).append_from(source, 0, local)


func collider_box(size: Vector3, center: Vector3, yaw: float = 0.0) -> void:
	var chunk := _chunk(center)
	if not _bodies.has(chunk):
		var body := StaticBody3D.new()
		body.collision_layer = WORLD_LAYER
		body.collision_mask = 0
		_root.add_child(body)
		_bodies[chunk] = body
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = center
	collision.rotation.y = yaw
	(_bodies[chunk] as StaticBody3D).add_child(collision)


func finish() -> void:
	for id: String in _tools:
		var st := _tools[id] as SurfaceTool
		var key := id.get_slice("|", 1)
		var array_mesh := st.commit()
		if array_mesh.get_surface_count() == 0:
			continue
		var instance := MeshInstance3D.new()
		instance.mesh = array_mesh
		instance.material_override = materials.get(key)
		instance.position = _chunk_center(_chunk_of_tool[id])
		instance.visibility_range_end = view_distance + chunk_size * 0.7
		_root.add_child(instance)
	_tools.clear()
