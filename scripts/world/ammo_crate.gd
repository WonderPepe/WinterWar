class_name AmmoCrate
extends StaticBody3D
## Ammunition boxes and a first-aid tin. Press F next to it (the host decides) to refill
## your spare ammunition and bandages. Unlimited – but you have to walk there.

@export var use_distance: float = 1.8 ## How close you must be (to the crate's centre).


func _ready() -> void:
	add_to_group("ammo_crates")


## Host: give the player full spare ammo and bandages.
func resupply(p: Player) -> void:
	if not multiplayer.is_server():
		return
	p.weapons.refill_reserve()
	p.bandages = p.max_bandages
	p.notify_resupplied.rpc_id(p.get_peer_id())
