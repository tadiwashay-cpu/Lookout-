class_name WeaponCatalog
extends RefCounted
## Every gun: stats, shop price and model. Buy them with money earned in
## multiplayer and missions (Main menu > SHOP). Tune balance here.
##   damage per bullet, rate (shots/s), mag, reload (s), spread (deg, hip),
##   range (m), pellets (shotguns), auto (hold to fire), price ($)

const START_WEAPON := "m4a1"

const WEAPONS := {
	"m4a1": {"name": "M4A1", "model": "m4a1", "class": "rifle", "damage": 20.0, "rate": 9.0, "mag": 30, "reload": 2.2, "spread": 1.6, "range": 160.0, "pellets": 1, "auto": true, "price": 0},
	"ak47": {"name": "AK-47", "model": "ak47", "class": "rifle", "damage": 26.0, "rate": 7.5, "mag": 30, "reload": 2.4, "spread": 2.2, "range": 150.0, "pellets": 1, "auto": true, "price": 1200},
	"m16a4": {"name": "M16A4", "model": "m16a4", "class": "rifle", "damage": 30.0, "rate": 5.0, "mag": 30, "reload": 2.2, "spread": 0.9, "range": 190.0, "pellets": 1, "auto": false, "price": 1500},
	"g36": {"name": "G36", "model": "g36", "class": "rifle", "damage": 22.0, "rate": 9.5, "mag": 30, "reload": 2.1, "spread": 1.3, "range": 170.0, "pellets": 1, "auto": true, "price": 1800},
	"scar_h": {"name": "SCAR-H", "model": "scar_h", "class": "rifle", "damage": 34.0, "rate": 6.5, "mag": 20, "reload": 2.5, "spread": 1.2, "range": 190.0, "pellets": 1, "auto": true, "price": 2600},
	"mp5k": {"name": "MP5K", "model": "mp5k", "class": "smg", "damage": 15.0, "rate": 13.0, "mag": 30, "reload": 1.8, "spread": 2.6, "range": 90.0, "pellets": 1, "auto": true, "price": 900},
	"uzi": {"name": "Uzi", "model": "uzi", "class": "smg", "damage": 13.0, "rate": 15.0, "mag": 32, "reload": 1.7, "spread": 3.2, "range": 80.0, "pellets": 1, "auto": true, "price": 700},
	"p90": {"name": "P90", "model": "p90", "class": "smg", "damage": 16.0, "rate": 14.0, "mag": 50, "reload": 2.3, "spread": 2.2, "range": 100.0, "pellets": 1, "auto": true, "price": 2000},
	"glock17": {"name": "Glock 17", "model": "glock17", "class": "pistol", "damage": 18.0, "rate": 6.0, "mag": 17, "reload": 1.3, "spread": 1.8, "range": 80.0, "pellets": 1, "auto": false, "price": 300},
	"deagle": {"name": "Desert Eagle", "model": "deagle", "class": "pistol", "damage": 48.0, "rate": 2.5, "mag": 7, "reload": 1.6, "spread": 1.4, "range": 110.0, "pellets": 1, "auto": false, "price": 1100},
	"spas12": {"name": "SPAS-12", "model": "spas12", "class": "shotgun", "damage": 14.0, "rate": 1.6, "mag": 8, "reload": 3.0, "spread": 6.0, "range": 45.0, "pellets": 8, "auto": false, "price": 1700},
	"awp": {"name": "AWP", "model": "awp", "class": "sniper", "damage": 120.0, "rate": 0.8, "mag": 5, "reload": 3.2, "spread": 0.15, "range": 400.0, "pellets": 1, "auto": false, "price": 4000},
	"m249": {"name": "M249", "model": "m249", "class": "lmg", "damage": 22.0, "rate": 12.0, "mag": 100, "reload": 4.5, "spread": 3.0, "range": 160.0, "pellets": 1, "auto": true, "price": 4500},
}


static func get_data(id: String) -> Dictionary:
	var data: Dictionary = WEAPONS.get(id, WEAPONS[START_WEAPON]).duplicate()
	data["id"] = id if WEAPONS.has(id) else START_WEAPON
	data["path"] = "res://assets/models/weapons/%s.glb" % data["model"]
	return data


## Shop order: cheapest first.
static func shop_ids() -> Array:
	var ids: Array = WEAPONS.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(WEAPONS[a]["price"]) < int(WEAPONS[b]["price"]))
	return ids
