class_name MolotovCrate
extends StaticBody3D
## A box of Molotov cocktails in the trench (T2). Press F next to it to take a full load
## (MolotovHandler.max_carry bottles). Unlimited – but you have to walk there.

@export var use_distance: float = 1.8 ## How close you must be (to the box's centre).


func _ready() -> void:
	add_to_group("molotov_crates")


## Host: fill up the player's bottles.
func give(p: Player) -> void:
	if multiplayer.is_server():
		p.molotov.refill()
