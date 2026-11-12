class_name Mats
extends RefCounted
## Shared materials and meshes: Poly Haven PBR textures (assets/textures/<name>/
## diff, nor, arm) and the props (assets/props/*.glb) as reusable meshes.

static var _cache: Dictionary = {}


static func tex(set_name: String, map: String = "diff") -> Texture2D:
	var path := "res://assets/textures/%s/%s.jpg" % [set_name, map]
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## A PBR material from a texture set. `scale` is metres per texture repeat
## (world-space triplanar UVs, so any mesh size works).
static func pbr(set_name: String, metres: float = 4.0, tint: Color = Color.WHITE) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [set_name, metres, tint]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex(set_name, "diff")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = tex(set_name, "nor")
	m.roughness_texture = tex(set_name, "arm")
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / metres
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


static func flat(color: Color, roughness: float = 0.7, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "flat|%s|%s|%s" % [color, roughness, metallic]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	_cache[key] = m
	return m


static func glow(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var key := "glow|%s|%s" % [color, energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	_cache[key] = m
	return m


## The first mesh of a prop glb with its materials baked in as surface
## materials (for MultiMesh use). Returns {"mesh": Mesh, "aabb": AABB}.
static func prop(name: String) -> Dictionary:
	var key := "prop|" + name
	if _cache.has(key):
		return _cache[key]
	var scene := load("res://assets/props/%s.glb" % name) as PackedScene
	var root := scene.instantiate()
	var merged := ArrayMesh.new()
	var aabb := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		var xf := _xform_to(root, mi)
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for i in verts.size():
				verts[i] = xf * verts[i]
				if i < norms.size():
					norms[i] = (xf.basis * norms[i]).normalized()
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = norms
			arrays[Mesh.ARRAY_TANGENT] = null
			merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat := mi.get_active_material(s)
			merged.surface_set_material(merged.get_surface_count() - 1, mat)
			var box := xf * mi.mesh.get_aabb()
			aabb = box if first else aabb.merge(box)
			first = false
	root.free()
	var out := {"mesh": merged, "aabb": aabb}
	_cache[key] = out
	return out


static func _xform_to(root: Node, node: Node3D) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p and p != root:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


## Drops many copies of a mesh into the world as one MultiMesh.
static func scatter(parent: Node, mesh: Mesh, transforms: Array, shadows: bool = true, range_end: float = 0.0) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if range_end > 0.0:
		mmi.visibility_range_end = range_end
	parent.add_child(mmi)
	return mmi


## Solid box collider (one shape on a shared body).
static func box_collider(body: StaticBody3D, center: Vector3, size: Vector3, yaw: float = 0.0) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = Transform3D(Basis(Vector3.UP, yaw), center)
	body.add_child(col)
