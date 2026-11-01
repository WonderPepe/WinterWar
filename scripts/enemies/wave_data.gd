class_name WaveData
extends Resource
## What one wave of the Soviet attack is made of (G2). The difficulty levels
## (resources/difficulty/*.tres) hold a list of these, one per wave – open one in the
## Inspector and change the numbers, no code needed.

@export var riflemen: int = 6
@export var officers: int = 0 ## Each one goes with a group of riflemen and whistles them forward.
@export var mg_teams: int = 0 ## DP-27 teams: a gunner and his helper (2 soldiers each).
@export var barrage: bool = false ## Artillery shells the trench first while this wave moves up.
@export var tanks: int = 0 ## T3: T-26 tanks with this wave. The wave only ends once they are all knocked out.


func make(r: int, o: int, m: int, b: bool = false, t: int = 0) -> WaveData:
	riflemen = r
	officers = o
	mg_teams = m
	barrage = b
	tanks = t
	return self


## Number of soldiers in the wave.
func total_soldiers() -> int:
	return riflemen + officers + mg_teams * 2


## e.g. "8 riflemen · 1 officer · 1 machine-gun team · 1 tank" (for the HUD).
static func describe(r: int, o: int, m: int, t: int = 0) -> String:
	var parts: PackedStringArray = PackedStringArray()
	if r > 0:
		parts.append("%d rifle%s" % [r, "men" if r != 1 else "man"])
	if o > 0:
		parts.append("%d officer%s" % [o, "s" if o != 1 else ""])
	if m > 0:
		parts.append("%d machine-gun team%s" % [m, "s" if m != 1 else ""])
	if t > 0:
		parts.append("%d tank%s" % [t, "s" if t != 1 else ""])
	return " · ".join(parts)
