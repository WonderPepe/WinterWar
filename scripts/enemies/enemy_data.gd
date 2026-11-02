class_name EnemyData
extends Resource
## All the numbers that describe one enemy type. Each type is a .tres file in
## resources/enemies/ - open it in the Inspector to tune it, no code needed.

enum Kind { RIFLEMAN, OFFICER, MG_GUNNER }

@export var display_name: String = "Soviet rifleman"
@export var kind: Kind = Kind.RIFLEMAN ## Decides his body/weapon and some behaviour (G2).
@export var max_health: float = 100.0
@export var fire_sound: AudioStream ## His shot (placeholder until a real recording exists).
@export var fire_sound_recording: String = "" ## e.g. "dp27": uses assets/audio/recorded/dp27… if present.
@export var fire_sound_pitch: float = 1.0

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
@export var max_fire_distance_m: float = 1000.0 ## Doesn't shoot at targets further away (officer's pistol).

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

@export_group("Assault on the trench")
@export var assault_hold_min: float = 6.0 ## Seconds spent firing from the jump-off point in front of the trench...
@export var assault_hold_max: float = 14.0 ## ...before rushing the trench and jumping in.
@export var trench_fire_interval_min: float = 1.4 ## Faster shooting at close range inside the trench.
@export var trench_fire_interval_max: float = 2.4

@export_group("Suppression (G2)")
## Player bullets passing this close (metres) make him duck: the closer, the more.
@export var suppression_radius_m: float = 3.0
@export var nerve: float = 1.0 ## Multiplies the suppression he gets (< 1 = steadier).
@export var suppression_recovery: float = 0.22 ## Suppression lost per second.
@export var recovery_delay: float = 1.2 ## Seconds after the last close bullet before he starts to recover.
@export_range(0.0, 1.0) var prone_threshold: float = 0.35 ## Above this he throws himself flat and stops advancing.
@export_range(0.0, 1.0) var pinned_threshold: float = 0.8 ## Above this he keeps his head down and doesn't shoot.
@export var suppressed_spread_multiplier: float = 2.5 ## Aim at full suppression is this much worse.
@export var suppressed_fire_interval_multiplier: float = 1.8 ## ...and he shoots this much more slowly.
@export var wounded_suppression: float = 0.45 ## Added when he is hit but survives.

@export_group("Officer (G2)")
@export var rally_radius_m: float = 25.0 ## Soldiers this close to a living officer are steadier.
@export var rally_nerve_multiplier: float = 0.6 ## Their suppression is multiplied by this.
@export var whistle_cooldown_min: float = 9.0 ## Seconds between two whistles...
@export var whistle_cooldown_max: float = 15.0
@export var whistle_rally: float = 0.5 ## A whistle takes this much suppression off the soldiers around him.
@export var leaderless_time: float = 15.0 ## His death makes the soldiers around him hesitate this long:
@export var leaderless_nerve_multiplier: float = 1.6 ## easier to pin down...
@export var leaderless_extra_hold: float = 8.0 ## ...and slower to rush the trench.

@export_group("Machine gun (G2)")
## The gun team opens fire (lies down) once it sees a Finn and is this close to the trench – a random
## distance between the two for each team (owner: 80–130 m).
@export var mg_fire_range_min_m: float = 80.0
@export var mg_fire_range_max_m: float = 130.0
## Fire, then move up (owner): the team follows its riflemen this far behind (random per team)...
@export var mg_follow_back_min_m: float = 5.0
@export var mg_follow_back_max_m: float = 10.0
## ...and gets up from its firing position once the riflemen are this much further forward.
@export var mg_move_up_m: float = 20.0
@export var mg_min_fire_time: float = 8.0 ## Seconds the gun fires from a position before it may move up.
@export var mg_magazine: int = 47 ## Rounds in a DP-27 pan.
@export var mg_shot_interval: float = 0.11 ## Seconds between rounds in a burst (~550 rounds/min).
@export var mg_burst_min: int = 4
@export var mg_burst_max: int = 9
@export var mg_burst_pause_min: float = 0.7 ## Pause between bursts.
@export var mg_burst_pause_max: float = 1.6
@export var mg_reload_time: float = 6.0 ## Changing the pan alone...
@export var mg_reload_time_assisted: float = 3.5 ## ...and with his helper next to him.
