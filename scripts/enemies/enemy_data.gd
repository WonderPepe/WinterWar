class_name EnemyData
extends Resource
## All the numbers that describe one enemy type. Each type is a .tres file in
## resources/enemies/ - open it in the Inspector to tune it, no code needed.

@export var display_name: String = "Soviet rifleman"
@export var max_health: float = 100.0

@export_group("Movement")
@export var walk_speed: float = 2.5 ## Advancing across the snow.
@export var hurry_speed: float = 3.5 ## When alerted.
@export var turn_speed: float = 4.0 ## Radians per second.

@export_group("Senses")
@export var vision_range_m: float = 150.0
@export var vision_angle_deg: float = 120.0 ## Full width of the view cone.
@export var spot_time_near: float = 0.3 ## Seconds of looking needed to notice a player up close...
@export var spot_time_far: float = 2.0 ## ...and at the edge of vision range.
@export var crouch_spot_multiplier: float = 1.6 ## Crouching players take longer to notice.
@export var lose_sight_time: float = 3.0 ## Seconds without seeing the target before giving up.
@export var alert_duration: float = 8.0 ## How long the soldier stays alerted by a noise.

@export_group("Combat")
@export var damage: float = 35.0
@export var reaction_time_min: float = 0.8 ## Delay before the first shot at a new target.
@export var reaction_time_max: float = 1.5
@export var fire_interval_min: float = 2.5 ## Time between shots (bolt-action rifle).
@export var fire_interval_max: float = 4.0
@export var shot_range_m: float = 300.0
@export var shot_noise_radius_m: float = 150.0 ## Other soldiers within this distance hear the shot.

@export_group("Accuracy (degrees)")
@export var base_spread_deg: float = 2.0
@export var spread_per_100m_deg: float = 1.0 ## Worse aim further away.
@export var moving_target_spread_deg: float = 1.5 ## Extra when the player is moving.
@export var first_shot_multiplier: float = 2.0 ## First shot at a new target is less accurate.
@export var full_aim_time: float = 4.0 ## Seconds of steady aiming to reach best accuracy...
@export_range(0.1, 1.0) var best_aim_multiplier: float = 0.5 ## ...which multiplies the spread by this.

@export_group("Attack advance")
@export var advance_time_min: float = 5.0 ## When far from its goal, the soldier alternates:
@export var advance_time_max: float = 8.0 ## advance for a few seconds...
@export var shots_per_stop: int = 2 ## ...then kneel and fire this many shots...
@export var stop_time_min: float = 4.0 ## ...staying kneeling for at most this long
@export var stop_time_max: float = 7.0 ## (moves on early when the shots are done).
