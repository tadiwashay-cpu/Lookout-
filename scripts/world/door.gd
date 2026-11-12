class_name Door
extends Area3D
## Walk up to it and press ENTER. Doors and counters share this.

var prompt := "Enter"
var action: Callable


static func make(parent: Node, pos: Vector3, text: String, on_use: Callable) -> Door:
	var d := Door.new()
	d.prompt = text
	d.action = on_use
	d.position = pos
	parent.add_child(d)
	return d


func _ready() -> void:
	collision_layer = 0
	collision_mask = Game.L_CHARS
	monitorable = false
	var shape := CylinderShape3D.new()
	shape.radius = 2.0
	shape.height = 3.0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.5
	add_child(col)
	body_entered.connect(func(b: Node) -> void:
		if b is Player:
			(b as Player).set_interactable(self, prompt))
	body_exited.connect(func(b: Node) -> void:
		if b is Player:
			(b as Player).clear_interactable(self))


func use(p: Player) -> void:
	action.call(p)


static var _busy := false


## Fade out, move, fade in.
static func travel(p: Player, to: Vector3, yaw: float) -> void:
	if _busy:
		return
	_busy = true
	var hud := p.get_tree().get_first_node_in_group(&"hud")
	if hud:
		await hud.call("fade", true)
	p.global_position = to
	p.velocity = Vector3.ZERO
	p.rotation.y = yaw
	if p.cam:
		p.cam.yaw = yaw + PI
	if hud:
		await hud.call("fade", false)
	_busy = false
