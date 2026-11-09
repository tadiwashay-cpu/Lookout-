class_name VehicleCatalog
extends RefCounted
## Every drivable vehicle and its hidden class (D, C, B, A, S).
## The rank is NEVER shown to the player: it only drives stats and how
## rare the car is to find in the world. Tune handling numbers here.
##
## Car models: "Generic passenger car pack" by Comrade1280, CC-BY-4.0
## (see CREDITS.md). Split into per-car files by tools/split_cars.py.

const RANK_STATS := {
	# accel: m/s^2 at full throttle (applied directly as a force, so it's
	# the same whatever the car weighs). decel: braking in m/s^2.
	# brake: wheel brake (Godot units) used to hold parked cars.
	# top_speed: m/s (x3.6 for km/h). grip: tyre friction slip.
	# spawn_weight: relative chance to appear parked in the city.
	"D": {"accel": 3.4, "decel": 8.5, "top_speed": 36.0, "brake": 22.0, "steer": 0.52, "grip": 2.6, "health": 600.0, "spawn_weight": 30.0},
	"C": {"accel": 4.1, "decel": 9.0, "top_speed": 42.0, "brake": 24.0, "steer": 0.54, "grip": 2.8, "health": 700.0, "spawn_weight": 30.0},
	"B": {"accel": 4.8, "decel": 9.5, "top_speed": 47.0, "brake": 26.0, "steer": 0.55, "grip": 3.0, "health": 800.0, "spawn_weight": 14.0},
	"A": {"accel": 6.0, "decel": 10.0, "top_speed": 58.0, "brake": 28.0, "steer": 0.57, "grip": 3.4, "health": 850.0, "spawn_weight": 5.0},
	"S": {"accel": 7.8, "decel": 11.0, "top_speed": 72.0, "brake": 30.0, "steer": 0.6, "grip": 3.9, "health": 900.0, "spawn_weight": 1.0},
}

## drive: "rwd" | "fwd" | "awd"
const VEHICLES := {
	"compact": {"model": "compact", "rank": "D", "mass": 1000.0, "drive": "fwd"},
	"minivan": {"model": "minivan", "rank": "D", "mass": 1800.0, "drive": "fwd"},
	"hatchback": {"model": "hatchback", "rank": "C", "mass": 1150.0, "drive": "fwd"},
	"sedan": {"model": "sedan", "rank": "C", "mass": 1400.0, "drive": "rwd"},
	"wagon": {"model": "wagon", "rank": "C", "mass": 1500.0, "drive": "rwd"},
	"pickup": {"model": "pickup", "rank": "C", "mass": 2100.0, "drive": "awd"},
	"suv": {"model": "suv", "rank": "B", "mass": 2100.0, "drive": "awd"},
	"offroad": {"model": "offroad", "rank": "B", "mass": 1700.0, "drive": "awd"},
	"coupe": {"model": "coupe", "rank": "A", "mass": 1300.0, "drive": "rwd"},
	"sport": {"model": "sport", "rank": "S", "mass": 1250.0, "drive": "rwd"},
	# Police: interceptor sedan and utility SUV. Parked at the precinct —
	# you can take them, but it's a serious crime.
	"police_sedan": {"model": "sedan", "rank": "A", "mass": 1500.0, "drive": "rwd", "police": true},
	"police_suv": {"model": "suv", "rank": "B", "mass": 2200.0, "drive": "awd", "police": true},
}

const POLICE_PAINT := {
	"police_sedan": Color(0.05, 0.08, 0.16),   # deep navy
	"police_suv": Color(0.04, 0.04, 0.05),     # black
}

## Muted civilian palette (see docs/art-direction.md — no candy colours).
const CIVILIAN_PAINTS := [
	Color(0.32, 0.08, 0.07),  # oxblood
	Color(0.14, 0.2, 0.28),   # slate blue
	Color(0.55, 0.55, 0.53),  # silver grey
	Color(0.62, 0.58, 0.48),  # faded cream
	Color(0.14, 0.2, 0.15),   # bottle green
	Color(0.1, 0.1, 0.11),    # charcoal
	Color(0.42, 0.18, 0.1),   # rust
	Color(0.3, 0.32, 0.34),   # gunmetal
	Color(0.7, 0.7, 0.68),    # off-white
]


static func get_data(vehicle_id: String) -> Dictionary:
	var base: Dictionary = VEHICLES.get(vehicle_id, VEHICLES["sedan"])
	var data := base.duplicate()
	data.merge(RANK_STATS[base["rank"]])
	data["id"] = vehicle_id
	data["police"] = base.get("police", false)
	data["model_path"] = "res://assets/models/vehicles/%s.glb" % base["model"]
	return data


## Civilian car for a parked slot, weighted so S/A cars are rare finds.
static func pick_civilian(rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for id: String in VEHICLES:
		if not VEHICLES[id].get("police", false):
			total += float(RANK_STATS[VEHICLES[id]["rank"]]["spawn_weight"])
	var roll := rng.randf() * total
	for id: String in VEHICLES:
		if VEHICLES[id].get("police", false):
			continue
		roll -= float(RANK_STATS[VEHICLES[id]["rank"]]["spawn_weight"])
		if roll <= 0.0:
			return id
	return "sedan"


static func random_paint(rng: RandomNumberGenerator) -> Color:
	return CIVILIAN_PAINTS[rng.randi() % CIVILIAN_PAINTS.size()]
