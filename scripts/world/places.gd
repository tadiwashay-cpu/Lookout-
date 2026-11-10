class_name Places
extends RefCounted
## Story-mode places you can use: the enterable bank (savings account) and
## the pawn shop (buy gear, sell guns). Interiors are small rooms built away
## from the city; doors fade you in and out.

const BANK_INTERIOR_DROP := 90.0   # the hall is built this far below the street
const INTEREST := 0.02             # per in-game day


static func build(world: World) -> void:
	_bank(world)
	_pawn_shop(world)


static func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, solid := true) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.8
	mesh.material_override = mat
	mesh.position = pos
	parent.add_child(mesh)
	if solid:
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		body.position = pos
		body.add_child(col)
		parent.add_child(body)


static func _spot(parent: Node3D, pos: Vector3, prompt: String, action: Callable) -> Interactable:
	var spot := Interactable.new()
	spot.prompt = prompt
	spot.position = pos
	parent.add_child(spot)
	spot.used.connect(action)
	return spot


# ------------------------------------------------------------------ bank

static func _bank(world: World) -> void:
	var door := world.bank_position
	var hall := Node3D.new()
	hall.name = "BankHall"
	world.add_child(hall)
	var o := door - Vector3(0, BANK_INTERIOR_DROP, 0)
	var marble := Color(0.86, 0.84, 0.8)
	var wood := Color(0.32, 0.2, 0.12)
	_box(hall, Vector3(30, 0.4, 22), o + Vector3(0, -0.2, -8), marble)                 # floor
	_box(hall, Vector3(30, 0.4, 22), o + Vector3(0, 8.2, -8), Color(0.75, 0.72, 0.66))  # ceiling
	_box(hall, Vector3(30, 8.4, 0.4), o + Vector3(0, 4, 3), Color(0.7, 0.66, 0.58))     # front wall
	_box(hall, Vector3(30, 8.4, 0.4), o + Vector3(0, 4, -19), Color(0.7, 0.66, 0.58))   # back wall
	_box(hall, Vector3(0.4, 8.4, 22), o + Vector3(-15, 4, -8), Color(0.7, 0.66, 0.58))
	_box(hall, Vector3(0.4, 8.4, 22), o + Vector3(15, 4, -8), Color(0.7, 0.66, 0.58))
	_box(hall, Vector3(18, 1.2, 1.2), o + Vector3(0, 0.6, -10), wood)                   # teller counter
	_box(hall, Vector3(18, 1.4, 0.1), o + Vector3(0, 1.9, -10), Color(0.7, 0.85, 0.9, 1.0), false)   # glass
	_box(hall, Vector3(5, 5, 0.6), o + Vector3(0, 2.5, -18.6), Color(0.45, 0.47, 0.5))  # vault door
	for x in [-9.0, -3.0, 3.0, 9.0]:
		_box(hall, Vector3(1.0, 8, 1.0), o + Vector3(x, 4, -2), Color(0.8, 0.78, 0.72))  # columns
	for x in [-8.0, 0.0, 8.0]:
		var lamp := OmniLight3D.new()
		lamp.position = o + Vector3(x, 6.5, -7)
		lamp.omni_range = 14.0
		lamp.light_energy = 1.4
		lamp.light_color = Color(1.0, 0.92, 0.8)
		hall.add_child(lamp)
	var board := Label3D.new()
	board.text = "FIRST HARBOR BANK"
	board.font_size = 72
	board.position = o + Vector3(0, 6, -18.2)
	board.modulate = Color(0.85, 0.75, 0.45)
	hall.add_child(board)
	var inside := o + Vector3(0, 0.3, 0.5)
	_spot(world, door, "Enter the bank", func(p: PlayerController) -> void: _travel(p, inside, 0.0))
	_spot(hall, o + Vector3(0, 0, 1.8), "Leave the bank", func(p: PlayerController) -> void: _travel(p, door + Vector3(0, 0, 2.5), PI))
	_spot(hall, o + Vector3(0, 0, -8.6), "Talk to the teller", func(p: PlayerController) -> void: _teller(p))


static var _busy := false


static func _travel(player: PlayerController, to: Vector3, yaw: float) -> void:
	if _busy:
		return
	_busy = true
	var hud := player.get_tree().get_first_node_in_group(&"hud") as GameHUD
	if hud:
		await hud.fade(true)
	# The hall is below the street: move the "fell out of the world" plane.
	player.kill_y = to.y - 30.0 if to.y < -30.0 else -40.0
	if is_instance_valid(player):
		player.respawn_at_quiet(to, yaw)
	if hud and is_instance_valid(hud):
		await hud.fade(false)
	_busy = false


static func _teller(player: PlayerController) -> void:
	var hud := player.get_tree().get_first_node_in_group(&"hud") as GameHUD
	if hud == null:
		return
	var refresh := func() -> Array:
		return [
			["Savings: $%d   •   Cash: $%d   •   +%d%% a day" % [GameSettings.bank_balance, GameSettings.money, int(INTEREST * 100)], "", Callable()],
			["Deposit all cash (safe if you get knocked out or busted)", "DEPOSIT", func() -> void: GameSettings.bank_deposit(GameSettings.money)],
			["Deposit $500", "DEPOSIT", func() -> void: GameSettings.bank_deposit(500)],
			["Withdraw $500", "WITHDRAW", func() -> void: GameSettings.bank_withdraw(500)],
			["Withdraw everything", "WITHDRAW", func() -> void: GameSettings.bank_withdraw(GameSettings.bank_balance)],
		]
	hud.open_menu("TELLER", refresh)


# ------------------------------------------------------------- pawn shop

static func _pawn_shop(world: World) -> void:
	var c := WorldCity.block_center(2, 1)
	var front := c + Vector3(-WorldCity.BLOCK_W * 0.25, 0.12, WorldCity.BLOCK_D * 0.5 - 1.2)
	if world.imported_city:
		front = world.imported_city.pawn + Vector3.UP * 0.1
	var shop := Node3D.new()
	shop.name = "PawnShop"
	world.add_child(shop)
	_box(shop, Vector3(7.0, 0.2, 2.0), front + Vector3(0, 3.4, 0.6), Color(0.55, 0.08, 0.06), false)   # awning
	var board := Label3D.new()
	board.text = "PAWN  •  GUNS  •  GOLD"
	board.font_size = 64
	board.position = front + Vector3(0, 4.1, 0.2)
	board.modulate = Color(1.0, 0.8, 0.3)
	board.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	shop.add_child(board)
	world.add_label("PAWN", front + Vector3(0, 8, 0), 40, Color(1.0, 0.8, 0.3))
	_spot(world, front + Vector3(0, 0, 1.2), "Pawn shop", func(p: PlayerController) -> void: _pawn(p))
	world.pawn_shop_position = front


static func _pawn(player: PlayerController) -> void:
	var hud := player.get_tree().get_first_node_in_group(&"hud") as GameHUD
	if hud == null:
		return
	var refresh := func() -> Array:
		var rows: Array = [["Cash: $%d" % GameSettings.money, "", Callable()]]
		rows.append(["Med kit (full health)", "$150", func() -> void:
			if GameSettings.money >= 150 and player.health.current < player.health.max_health:
				GameSettings.add_money(-150)
				player.health.revive()])
		rows.append(["3 grenades", "$200", func() -> void:
			if GameSettings.money >= 200:
				GameSettings.add_money(-200)
				player.refill_grenades(3)])
		rows.append(["Ammo (fill reserve)", "$100", func() -> void:
			if GameSettings.money >= 100:
				GameSettings.add_money(-100)
				player.refill_ammo()])
		for id: String in WeaponCatalog.shop_ids():
			var data := WeaponCatalog.get_data(id)
			if GameSettings.owned_weapons.has(id):
				if GameSettings.owned_weapons.size() > 1:
					rows.append(["Sell %s" % data["name"], "+$%d" % int(int(data["price"]) * 0.5), func() -> void:
						var before := GameSettings.equipped_weapon
						GameSettings.sell_weapon(id)
						if GameSettings.equipped_weapon != before:
							player.equip(GameSettings.equipped_weapon)])
			else:
				rows.append(["Buy %s" % data["name"], "$%d" % int(data["price"]), func() -> void:
					if GameSettings.buy_weapon(id):
						player.equip(id)])
		return rows
	hud.open_menu("PAWN SHOP", refresh)
