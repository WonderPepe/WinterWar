class_name WeaponData
extends Resource
## All the numbers that describe one weapon. Each weapon is a .tres file in
## resources/weapons/ - open it in the Inspector to fine-tune it, no code needed.
## Spread and recoil angles are in degrees, distances in metres, times in seconds.

enum FireMode { BOLT_ACTION, SEMI_AUTO, FULL_AUTO }

@export var display_name: String = "Weapon"
@export var view_model: PackedScene ## The first-person model scene.

@export_group("Firing")
@export var fire_mode: FireMode = FireMode.SEMI_AUTO
@export var rounds_per_minute: float = 300.0 ## Fire rate for SEMI_AUTO and FULL_AUTO.
@export var bolt_cycle_time: float = 1.2 ## BOLT_ACTION: time after a shot before the next one.
@export var damage: float = 50.0
@export var max_range_m: float = 400.0
@export var falloff_start_m: float = 100.0 ## Damage starts to drop after this distance...
@export var falloff_end_m: float = 300.0   ## ...and reaches its minimum here.
@export_range(0.0, 1.0) var min_damage_multiplier: float = 0.5
@export var noise_radius_m: float = 120.0 ## Enemies within this distance hear the shot.

@export_group("Ammo")
@export var magazine_size: int = 10
@export var starting_reserve: int = 30 ## Spare rounds you start with.
@export var reload_time: float = 2.5

@export_group("Accuracy")
@export var hip_spread_deg: float = 2.0 ## Random spread when firing from the hip.
@export var ads_spread_deg: float = 0.2 ## Random spread when aiming down the sights.
@export var move_spread_deg: float = 2.0 ## Extra spread when moving at walking speed.
@export var bloom_per_shot_deg: float = 0.0 ## Extra spread added by each shot (automatic fire).
@export var max_bloom_deg: float = 0.0
@export var bloom_recovery_deg_per_s: float = 5.0

@export_group("Recoil")
@export var recoil_pitch_deg: float = 2.0 ## Camera kicks up this much per shot.
@export var recoil_yaw_deg: float = 0.5 ## Random left/right kick.
@export_range(0.0, 1.0) var recoil_recovery: float = 0.6 ## Part of the up-kick that returns by itself.
@export var recoil_return_speed: float = 8.0
@export var kick_back_m: float = 0.05 ## Visual push of the model towards you.
@export var kick_rotation_deg: float = 4.0 ## Visual tilt of the muzzle upwards.

@export_group("Aiming down sights")
@export var ads_fov: float = 55.0 ## Camera field of view while aiming (normal is 75).
@export var ads_time: float = 0.25 ## Seconds to raise the sights.
@export_range(0.1, 1.0) var ads_move_multiplier: float = 0.6 ## Movement speed while aiming.
@export_range(0.1, 1.0) var ads_sensitivity_multiplier: float = 0.6 ## Mouse sensitivity while aiming.

@export_group("Heat (water-cooled machine gun)")
@export var heat_per_shot: float = 0.0 ## 0 = never heats up. Heat goes from 0 (cold) to 1 (overheated).
@export var cooling_rate: float = 0.09 ## Share of the heat lost per second (a hot gun cools faster).
@export_range(0.0, 1.0) var firing_cooling_multiplier: float = 0.4 ## Cooling is slower while firing.
@export_range(0.0, 1.0) var steam_heat: float = 0.6 ## Steam starts rising from the water jacket here.
@export_range(0.0, 1.0) var overheat_recover_heat: float = 0.5 ## Overheated: no firing until it cools to this.

@export_group("Sounds")
@export var fire_sound: AudioStream
@export var cycle_sound: AudioStream ## Bolt being worked (bolt-action only).
@export var reload_sound: AudioStream
@export var empty_sound: AudioStream


## Seconds between two shots.
func get_shot_interval() -> float:
	if fire_mode == FireMode.BOLT_ACTION:
		return bolt_cycle_time
	return 60.0 / maxf(rounds_per_minute, 1.0)


## Damage after distance falloff.
func damage_at(distance: float) -> float:
	var t: float = inverse_lerp(falloff_start_m, falloff_end_m, distance)
	return damage * lerpf(1.0, min_damage_multiplier, clampf(t, 0.0, 1.0))
