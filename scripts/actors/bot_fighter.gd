class_name BotFighter
extends Fighter
## A street fighter AI: circles its target, closes in, throws combos and
## shoulder charges, blocks when you swing, rolls away, uses its surge.

var target: Fighter
var skill := 0.6                  # 0..1
var arena_center := Vector3.ZERO
var arena_radius := 0.0           # keep inside (Clean Hands ring)
var _think := 0.0
var _strafe := 1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	super._ready()
	_rng.randomize()
	run_speed = 5.2
	sprint_speed = 7.5


func _wants_move() -> Vector3:
	if target == null or not is_instance_valid(target) or not target.alive:
		return _keep_in_arena(Vector3.ZERO)
	var d := target.global_position - global_position
	d.y = 0.0
	var dist := d.length()
	var dir := d.normalized()
	var side := Vector3(-dir.z, 0, dir.x) * _strafe
	var want := Vector3.ZERO
	if dist > 2.6:
		want = dir
	elif dist < 1.3:
		want = -dir * 0.6 + side * 0.5
	else:
		want = side * 0.45
	return _keep_in_arena(want)


func _keep_in_arena(v: Vector3) -> Vector3:
	if arena_radius <= 0.0:
		return v
	var off := global_position - arena_center
	off.y = 0.0
	if off.length() > arena_radius - 1.0:
		return (v - off.normalized()).limit_length(1.0)
	return v


func _face_target() -> Fighter:
	return target


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if not alive:
		return
	_think -= delta
	if _think > 0.0:
		return
	_think = lerpf(0.55, 0.22, skill) * _rng.randf_range(0.7, 1.3)
	if target == null or not is_instance_valid(target) or not target.alive or target.in_car:
		target = _pick_target()
		return
	if _rng.randf() < 0.2:
		_strafe = -_strafe
	var dist := target.global_position.distance_to(global_position)
	# React to an incoming swing.
	if target.state == State.ATTACK and dist < 2.4:
		if _rng.randf() < skill * 0.5:
			block(true)
			return
		if _rng.randf() < skill * 0.25:
			dodge(global_basis.x * (1.0 if _rng.randf() < 0.5 else -1.0))
			return
	if state == State.BLOCK and _rng.randf() < 0.6:
		block(false)
	if surge >= 50.0 and dist < 4.0 and _rng.randf() < 0.3:
		power_surge()
		return
	if dist < 2.0:
		if _rng.randf() < 0.75:
			punch()
		else:
			heavy()
	elif dist < 5.0 and _rng.randf() < 0.12:
		heavy()


func _pick_target() -> Fighter:
	var best: Fighter = null
	var best_d := 60.0
	for node in get_tree().get_nodes_in_group(&"fighters"):
		var f := node as Fighter
		if f == self or not f.alive or f.in_car or f.is_in_group(&"civilians"):
			continue
		var d := f.global_position.distance_to(global_position) * _rng.randf_range(0.8, 1.2)
		if d < best_d:
			best_d = d
			best = f
	return best
