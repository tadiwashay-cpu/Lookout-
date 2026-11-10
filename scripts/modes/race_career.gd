class_name RaceCareer
extends RefCounted
## Single-player race career: 8 street races that unlock in order. You race
## your own garage car (buy better ones in the CAR shop); rivals get faster,
## smarter and more numerous. Winning pays out and unlocks store cars.

## route: fraction of the highway->forest->suburb run used (0..1)
## rivals: [car id, ...]   skill: [min, max] for CarPilot.skill
const EVENTS := [
	{"name": "Rookie Run", "route": 0.25, "rivals": ["hatchback", "compact"], "skill": [0.7, 0.8], "reward": 300},
	{"name": "Harbour Sprint", "route": 0.35, "rivals": ["sedan", "hatchback", "wagon"], "skill": [0.75, 0.85], "reward": 500},
	{"name": "Highway Pull", "route": 0.45, "rivals": ["suv", "sedan", "offroad"], "skill": [0.8, 0.9], "reward": 800},
	{"name": "Forest Switchbacks", "route": 0.6, "rivals": ["offroad", "coupe", "suv"], "skill": [0.85, 0.95], "reward": 1200},
	{"name": "Night Shift", "route": 0.7, "rivals": ["coupe", "coupe", "rally_hatch"], "skill": [0.88, 0.98], "reward": 1800},
	{"name": "Suburb Showdown", "route": 0.8, "rivals": ["drift_spec", "coupe", "trophy_truck"], "skill": [0.92, 1.0], "reward": 2500},
	{"name": "Coast to Coast", "route": 1.0, "rivals": ["sport", "drift_spec", "street_king"], "skill": [0.95, 1.05], "reward": 3500},
	{"name": "Kingpin", "route": 1.0, "rivals": ["street_king", "sport", "night_runner", "street_king"], "skill": [1.0, 1.1], "reward": 6000},
]


static func event(index: int) -> Dictionary:
	return EVENTS[clampi(index, 0, EVENTS.size() - 1)]


static func unlocked(index: int) -> bool:
	return index <= GameSettings.career_won
