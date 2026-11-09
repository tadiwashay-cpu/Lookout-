class_name HealthComponent
extends Node
## Reusable health pool for the player, goons, police and civilians.

signal health_changed(current: float, maximum: float)
signal damaged(amount: float, source: Node)
signal died

@export var max_health: float = 100.0

var current: float = 0.0
var is_dead: bool = false


func _ready() -> void:
	current = max_health


func take_damage(amount: float, source: Node = null) -> void:
	if is_dead or amount <= 0.0:
		return
	current = maxf(current - amount, 0.0)
	damaged.emit(amount, source)
	health_changed.emit(current, max_health)
	if current <= 0.0:
		is_dead = true
		died.emit()


func heal(amount: float) -> void:
	if is_dead:
		return
	current = minf(current + amount, max_health)
	health_changed.emit(current, max_health)


func revive() -> void:
	is_dead = false
	current = max_health
	health_changed.emit(current, max_health)
