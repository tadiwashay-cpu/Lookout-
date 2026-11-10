class_name SkidMarks
extends MultiMeshInstance3D
## Tyre marks left by drifting / handbraking cars. One MultiMesh ring buffer
## for the whole world (a single draw call): each skid segment is a thin
## flat quad stretched between two contact points; the oldest are reused.

const MAX_MARKS := 1200
const WIDTH := 0.24

var _next := 0


## The world's skid mark layer, created on first use.
static func instance(tree: SceneTree) -> SkidMarks:
	var existing := tree.get_first_node_in_group(&"skid_marks") as SkidMarks
	if existing:
		return existing
	if tree.current_scene == null:
		return null
	var marks := SkidMarks.new()
	tree.current_scene.add_child(marks)
	return marks


func _ready() -> void:
	add_to_group(&"skid_marks")
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2(WIDTH, 1.0)
	quad.orientation = PlaneMesh.FACE_Y
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.03, 0.03, 0.03, 0.55)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = 1.0
	material.vertex_color_use_as_albedo = true
	material.render_priority = -1
	quad.material = material
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = MAX_MARKS
	mm.visible_instance_count = 0
	multimesh = mm
	# Huge custom AABB: marks are scattered over the whole map.
	custom_aabb = AABB(Vector3(-5000, -500, -5000), Vector3(10000, 1000, 10000))


## Lay one segment of rubber from `from` to `to` on a surface with `normal`.
func add_segment(from: Vector3, to: Vector3, normal: Vector3, strength: float = 1.0) -> void:
	var along := to - from
	var length := along.length()
	if length < 0.05 or length > 4.0:
		return
	var up := normal.normalized() if normal.length() > 0.1 else Vector3.UP
	var z := along / length
	var x := up.cross(z).normalized()
	if x.length() < 0.1:
		return
	z = x.cross(up).normalized()
	var basis := Basis(x, up, z * length)
	var centre := (from + to) * 0.5 + up * 0.025   # just above the road: no z-fighting
	multimesh.set_instance_transform(_next, Transform3D(basis, centre))
	multimesh.set_instance_color(_next, Color(1, 1, 1, clampf(strength, 0.25, 1.0)))
	_next = (_next + 1) % MAX_MARKS
	multimesh.visible_instance_count = maxi(multimesh.visible_instance_count, _next if _next > 0 else MAX_MARKS)
