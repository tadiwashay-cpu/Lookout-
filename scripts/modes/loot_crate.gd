class_name LootCrate
extends Node3D
## Battle-royale loot: walk up, ENTER to open. Contents are rolled from the
## match seed so every device sees the same crate; opening one is announced
## so it disappears for everyone.

signal opened(index: int, player: PlayerController)

var index := 0
var kind := "weapon"       # weapon | ammo | medkit
var weapon_id := ""
var _spot: Interactable


func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.9, 0.6, 0.6)
	var mat := StandardMaterial3D.new()
	var color: Color = {"weapon": Color(1.0, 0.7, 0.2), "ammo": Color(0.35, 0.6, 1.0), "medkit": Color(0.3, 0.9, 0.4)}[kind]
	mat.albedo_color = color.darkened(0.55)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 0.9
	box.material = mat
	var mesh := MeshInstance3D.new()
	mesh.mesh = box
	mesh.position.y = 0.3
	mesh.visibility_range_end = 120.0
	add_child(mesh)
	var label := Label3D.new()
	label.text = {"weapon": WeaponCatalog.get_data(weapon_id)["name"] if weapon_id != "" else "GUN", "ammo": "AMMO", "medkit": "MED KIT"}[kind]
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 8
	label.modulate = color
	label.position.y = 1.1
	label.visibility_range_end = 35.0
	add_child(label)
	_spot = Interactable.new()
	_spot.prompt = "Open: %s" % label.text
	_spot.radius = 1.8
	add_child(_spot)
	_spot.used.connect(func(p: PlayerController) -> void: opened.emit(index, p))


## Give the contents to the player who opened it.
func apply(p: PlayerController) -> void:
	match kind:
		"weapon":
			p.equip(weapon_id)
			p.draw_weapon()
		"ammo":
			p.refill_ammo()
			p.refill_grenades(mini(p.grenades + 2, 4))
		"medkit":
			p.health.heal(60.0)
	Audio.play("reload", global_position + Vector3.UP)
