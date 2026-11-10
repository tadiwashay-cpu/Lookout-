class_name Interactable
extends Area3D
## A spot the player can use with ENTER (bank door, teller, pawn counter).
## Walk into it: the HUD shows `prompt` and the touch layout shows ENTER.

signal used(player: PlayerController)

var prompt := "Use"
var radius := 2.2


func _ready() -> void:
	collision_layer = 0
	collision_mask = 2   # player
	monitorable = false
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = 3.0
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position.y = 1.5
	add_child(col)
	body_entered.connect(func(body: Node) -> void:
		if body is PlayerController:
			(body as PlayerController).set_interactable(self))
	body_exited.connect(func(body: Node) -> void:
		if body is PlayerController:
			(body as PlayerController).clear_interactable(self))
