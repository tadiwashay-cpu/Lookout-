class_name CarCatalog
extends RefCounted
## The car pack. Models: "Generic passenger car pack" by Comrade1280 (CC BY
## 4.0) plus the original supercars added to it. Stats are tuned for a
## planted, grippy feel (Forza / NFS: Most Wanted), not simulation.

## top: m/s   accel: m/s^2   grip: lateral hold   steer: max angle (rad)
const CARS := {
	"compact":    {"name": "Compact", "mass": 1000.0, "drive": "fwd", "top": 44.0, "accel": 6.5, "grip": 1.0, "steer": 0.55, "health": 700.0},
	"hatchback":  {"name": "Hatchback", "mass": 1150.0, "drive": "fwd", "top": 48.0, "accel": 7.2, "grip": 1.05, "steer": 0.55, "health": 750.0},
	"sedan":      {"name": "Sedan", "mass": 1400.0, "drive": "rwd", "top": 52.0, "accel": 7.6, "grip": 1.05, "steer": 0.52, "health": 850.0},
	"wagon":      {"name": "Wagon", "mass": 1500.0, "drive": "rwd", "top": 50.0, "accel": 7.0, "grip": 1.0, "steer": 0.5, "health": 900.0},
	"minivan":    {"name": "Minivan", "mass": 1800.0, "drive": "fwd", "top": 44.0, "accel": 5.8, "grip": 0.95, "steer": 0.5, "health": 1000.0},
	"pickup":     {"name": "Pickup", "mass": 2100.0, "drive": "awd", "top": 48.0, "accel": 6.6, "grip": 1.0, "steer": 0.5, "health": 1200.0},
	"suv":        {"name": "SUV", "mass": 2100.0, "drive": "awd", "top": 52.0, "accel": 7.0, "grip": 1.0, "steer": 0.5, "health": 1200.0},
	"offroad":    {"name": "Offroad", "mass": 1700.0, "drive": "awd", "top": 50.0, "accel": 7.4, "grip": 1.05, "steer": 0.52, "health": 1100.0},
	"coupe":      {"name": "Coupe", "mass": 1300.0, "drive": "rwd", "top": 62.0, "accel": 9.0, "grip": 1.15, "steer": 0.55, "health": 850.0},
	"sport":      {"name": "Sport", "mass": 1250.0, "drive": "rwd", "top": 72.0, "accel": 10.5, "grip": 1.25, "steer": 0.56, "health": 850.0},
	"crown_vic":  {"name": "Interceptor", "mass": 1800.0, "drive": "rwd", "top": 62.0, "accel": 9.0, "grip": 1.15, "steer": 0.52, "health": 1300.0},
	"spyder_rs":  {"name": "Spyder RS", "mass": 1350.0, "drive": "rwd", "top": 78.0, "accel": 11.5, "grip": 1.35, "steer": 0.58, "health": 900.0},
	"aurora_gt":  {"name": "Aurora GT", "mass": 1550.0, "drive": "rwd", "top": 82.0, "accel": 11.8, "grip": 1.3, "steer": 0.55, "health": 950.0},
	"regal_gt":   {"name": "Regal GT", "mass": 2000.0, "drive": "awd", "top": 84.0, "accel": 11.6, "grip": 1.35, "steer": 0.54, "health": 1300.0},
	"strix_v12":  {"name": "Strix V12", "mass": 1600.0, "drive": "awd", "top": 90.0, "accel": 13.0, "grip": 1.45, "steer": 0.56, "health": 1000.0},
	"vortex_rs":  {"name": "Vortex RS", "mass": 1400.0, "drive": "rwd", "top": 94.0, "accel": 13.5, "grip": 1.45, "steer": 0.57, "health": 950.0},
	"redline_gt": {"name": "Redline GT", "mass": 1450.0, "drive": "awd", "top": 98.0, "accel": 14.0, "grip": 1.5, "steer": 0.57, "health": 1000.0},
}
const RACE_CARS := ["sport", "coupe", "spyder_rs", "aurora_gt", "regal_gt", "strix_v12", "vortex_rs", "redline_gt"]
const STREET_CARS := ["compact", "hatchback", "sedan", "wagon", "minivan", "pickup", "suv", "offroad", "coupe"]
const PAINTS := [Color(0.55, 0.04, 0.04), Color(0.05, 0.2, 0.5), Color(0.08, 0.08, 0.09), Color(0.85, 0.85, 0.83),
	Color(0.55, 0.56, 0.58), Color(0.1, 0.32, 0.15), Color(0.85, 0.45, 0.05), Color(0.3, 0.05, 0.35)]


static func data(id: String) -> Dictionary:
	var d: Dictionary = CARS.get(id, CARS["sedan"]).duplicate()
	d["id"] = id
	d["model"] = "res://assets/vehicles/%s.glb" % id
	return d
