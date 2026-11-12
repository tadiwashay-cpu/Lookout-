class_name Layout
extends RefCounted
## Where everything is (metres). The world is 2.4 km square:
##   north: mountains (and a pass road)   east: harbour, then the sea
##   centre: the city                     west: suburbs
##   south-west: forest hills             all joined by roads.

const HALF := 1200.0
const CELL := 8.0                     # terrain grid
const CITY_Y := 2.0

# City grid: street centre lines.
const CITY_X := [-320.0, -200.0, -80.0, 40.0, 160.0, 280.0, 400.0]
const CITY_Z := [-360.0, -240.0, -120.0, 0.0, 120.0, 240.0]
const STREET_W := 20.0
const CITY_RECT := Rect2(-345.0, -385.0, 760.0, 650.0)
const HARBOUR_RECT := Rect2(415.0, -385.0, 285.0, 650.0)
const SHORE_X := 700.0
const SUBURB_RECT := Rect2(-940.0, -270.0, 480.0, 640.0)
const FOREST_RECT := Rect2(-1000.0, 420.0, 860.0, 700.0)

## Roads outside the city grid (control points x, z). Their ends meet city
## street ends, so the whole map is one connected network.
const ROADS := {
	"harbour": [Vector2(400, -120), Vector2(520, -120), Vector2(590, -124)],
	"coast_highway": [Vector2(590, -124), Vector2(640, -165), Vector2(660, -260), Vector2(662, -330), Vector2(645, -520), Vector2(500, -740), Vector2(240, -860),
		Vector2(-110, -905), Vector2(-470, -865), Vector2(-750, -705), Vector2(-850, -480), Vector2(-790, -320), Vector2(-700, -250)],
	"suburb_main": [Vector2(-700, -250), Vector2(-700, -120), Vector2(-700, 0), Vector2(-700, 160), Vector2(-700, 330)],
	"suburb_link": [Vector2(-920, 0), Vector2(-800, 0), Vector2(-700, 0), Vector2(-520, 0), Vector2(-320, 0)],
	"forest_road": [Vector2(-700, 330), Vector2(-725, 560), Vector2(-560, 820), Vector2(-260, 945), Vector2(40, 865),
		Vector2(185, 625), Vector2(160, 410), Vector2(160, 240)],
}
const ROAD_HALF_WIDTH := 7.0

## Key places.
const RING_CENTER := Vector3(560.0, CITY_Y, 140.0)       # Clean Hands ring (harbour yard)
const PLAYER_START := Vector3(30.0, CITY_Y + 0.3, 10.0)

## Race: the grand loop (city -> harbour -> coast highway over the mountain
## pass -> suburbs -> forest -> back into the city).
const RACE_LOOP := ["city:40,-120>400,-120", "harbour", "coast_highway", "suburb_main", "forest_road", "city:160,240>160,-120", "city:160,-120>40,-120"]


static func in_rect_soft(p: Vector2, r: Rect2, falloff: float) -> float:
	var dx := maxf(maxf(r.position.x - p.x, p.x - r.end.x), 0.0)
	var dz := maxf(maxf(r.position.y - p.y, p.y - r.end.y), 0.0)
	return 1.0 - smoothstep(0.0, falloff, sqrt(dx * dx + dz * dz))
