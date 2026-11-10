extends Node
## Police heat. The hero is not automatically one of the good guys:
## brawling in public draws a little attention, hurting civilians or police
## escalates fast. Heat decays once you lose the cops.

signal stars_changed(stars: int)
signal crime_reported(severity: float, position: Vector3)

const MAX_STARS := 5
const HEAT_PER_STAR := 100.0
const DECAY_DELAY := 8.0
const DECAY_PER_SECOND := 10.0

## Crime severities (heat added) and the highest star level each can push you to.
const CRIME_VIGILANTE := 8.0        # beating up goons in public
const CRIME_VIGILANTE_CAP := 1
const CRIME_ASSAULT_CIVILIAN := 45.0
const CRIME_ASSAULT_POLICE := 90.0
const CRIME_GUNFIRE := 60.0
const CRIME_VEHICLE_THEFT := 35.0
const CRIME_POLICE_VEHICLE_THEFT := 120.0

var heat: float = 0.0
var stars: int = 0
var _time_since_crime: float = 999.0
var _seen_by_police: bool = false


func _process(delta: float) -> void:
	_time_since_crime += delta
	if heat > 0.0 and not _seen_by_police and _time_since_crime > DECAY_DELAY:
		heat = maxf(heat - DECAY_PER_SECOND * delta, 0.0)
		_refresh_stars()


func report_crime(severity: float, at: Vector3, max_stars: int = MAX_STARS) -> void:
	var cap := float(clampi(max_stars, 0, MAX_STARS)) * HEAT_PER_STAR
	if heat < cap:
		heat = minf(heat + severity, cap)
	_time_since_crime = 0.0
	crime_reported.emit(severity, at)
	_refresh_stars()


func is_seen() -> bool:
	return _seen_by_police


## 0..1 while slipping away: fills during the delay before heat starts to drop.
func evade_progress() -> float:
	return clampf(_time_since_crime / DECAY_DELAY, 0.0, 1.0)


func set_seen_by_police(seen: bool) -> void:
	_seen_by_police = seen
	if seen:
		_time_since_crime = 0.0


func clear() -> void:
	heat = 0.0
	_time_since_crime = 999.0
	_refresh_stars()


func _refresh_stars() -> void:
	var new_stars := clampi(ceili(heat / HEAT_PER_STAR), 0, MAX_STARS)
	if new_stars != stars:
		stars = new_stars
		stars_changed.emit(stars)
