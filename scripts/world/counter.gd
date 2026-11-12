class_name Counter
extends RefCounted
## What each service sells (opened from its counter).


static func make(parent: Node, pos: Vector3, text: String, kind: String) -> void:
	Door.make(parent, pos, text, func(p: Player) -> void: open(p, kind))


static func open(p: Player, kind: String) -> void:
	var hud := p.get_tree().get_first_node_in_group(&"hud")
	if hud == null:
		return
	var rows := func() -> Array:
		var out: Array = [["Cash: $%d" % Game.money, "", Callable()]]
		match kind:
			"repair":
				var car := _nearest_car(p)
				if car == null:
					out.append(["Park a car outside the workshop and come back.", "", Callable()])
				else:
					var full: float = car.data["health"]
					out.append(["%s outside: condition %d%%" % [car.data["name"], int(car.health / full * 100.0)], "", Callable()])
					out.append(["Full repair", "$250", func() -> void: if _pay(250): car.repair()])
					out.append(["Respray", "$300", func() -> void:
						if _pay(300):
							car.paint = CarCatalog.PAINTS[randi() % CarCatalog.PAINTS.size()]
							car.repair()])
					out.append(["Fill the nitro bottle", "$120", func() -> void: if _pay(120): car.nitro = 1.0])
			"clinic":
				out.append(["Health %d / %d" % [int(p.health), int(p.max_health)], "", Callable()])
				out.append(["Patch me up", "$90", func() -> void: if p.health < p.max_health and _pay(90): p.health = p.max_health])
			"diner":
				out.append(["Coffee (+15 health)", "$8", func() -> void: if _pay(8): p.health = minf(p.health + 15.0, p.max_health)])
				out.append(["Burger and fries (+45 health)", "$25", func() -> void: if _pay(25): p.health = minf(p.health + 45.0, p.max_health)])
			"gym":
				out.append(["Spar to charge your surge", "$50", func() -> void: if _pay(50): p.surge = 100.0])
			"bank":
				out.append(["Your cash is safe here (savings coming with the story).", "", Callable()])
		return out
	hud.call("open_menu", kind.to_upper(), rows)


static func _pay(amount: int) -> bool:
	if Game.money < amount:
		return false
	Game.add_money(-amount)
	return true


static func _nearest_car(p: Player) -> Car:
	var world := p.get_tree().get_first_node_in_group(&"world")
	var door: Vector3 = world.get("services").doors.get("repair", Vector3.ZERO)
	var best: Car = null
	var best_d := 25.0
	for node in p.get_tree().get_nodes_in_group(&"cars"):
		var c := node as Car
		var d := c.global_position.distance_to(door)
		if c.driver == null and d < best_d:
			best_d = d
			best = c
	return best
