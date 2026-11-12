class_name RemoteFighter
extends Fighter
## Another player's fighter: follows the snapshots their device sends.
## Hits we land on it are forwarded to its owner, who applies them.

var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _anim := &"Idle"


func _ready() -> void:
	model_path = Humanoid.NASH
	max_health = 160.0
	super._ready()
	_target_pos = global_position


func apply_state(s: Dictionary) -> void:
	_target_pos = s.get("p", _target_pos)
	_target_yaw = s.get("y", _target_yaw)
	health = s.get("h", health)
	alive = s.get("a", alive)
	in_car = s.get("c", false)
	visible = not in_car
	var clip: StringName = StringName(s.get("n", "Idle"))
	if clip != _anim:
		_anim = clip
		body.cancel_one_shot()
		body.play(clip, 0.1, float(s.get("s", 1.0)), true)
	var st: int = s.get("st", 0)
	state = st as State


func _physics_process(delta: float) -> void:
	global_position = global_position.lerp(_target_pos, clampf(delta * 14.0, 0.0, 1.0))
	if global_position.distance_to(_target_pos) > 6.0:
		global_position = _target_pos
	rotation.y = lerp_angle(rotation.y, _target_yaw, clampf(delta * 14.0, 0.0, 1.0))


func receive_hit(damage: float, push: Vector3, attacker: Fighter, heavy: bool) -> void:
	if not alive or in_car:
		return
	Sfx.play("heavy" if heavy else "punch", global_position + Vector3.UP * 1.4)
	Fx.sparks(get_parent(), global_position + Vector3.UP * 1.4, Color(1.0, 0.8, 0.5))
	Net.send_event("hit", {"to": peer_id, "dmg": damage, "push": push, "from": Net.my_id(), "heavy": heavy})


## Snapshot of a local fighter for the network.
static func snapshot(f: Fighter) -> Dictionary:
	return {"p": f.global_position, "y": f.rotation.y, "h": f.health, "a": f.alive, "c": f.in_car,
		"n": String(f.body.current), "s": f.body.anim.speed_scale if f.body.anim else 1.0, "st": int(f.state)}
