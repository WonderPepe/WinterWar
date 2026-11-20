class_name DifficultyData
extends Resource
## One difficulty level (resources/difficulty/*.tres). Open it in the Inspector to tune it.

@export var display_name: String = "Normal"
@export var waves_to_win: int = 10 ## Clear this many waves and the line has held until dusk.
## This many Soviets in the trench at the same time starts the countdown (TC1: 6 on every level).
@export var trench_limit: int = 6
## TC1: seconds to kill them below `trench_limit`, or the line is broken (0 = broken at once).
@export var trench_clear_time: float = 30.0
@export var base_enemies: int = 6 ## Soldiers in wave 1 (only used when `waves` is empty).
@export var enemies_added_per_wave: int = 2 ## (only used when `waves` is empty)
## G2: what each wave is made of (riflemen, officers, machine-gun teams). Waves beyond the end
## of the list repeat the last entry. Empty = only riflemen, base_enemies + added per wave.
@export var waves: Array[WaveData] = []
@export var enemy_spread_multiplier: float = 1.0 ## < 1 = the enemy aims better.
## Damage of Soviet soldiers' bullets × this (Easy 0.6). Artillery is not affected.
@export var enemy_damage_multiplier: float = 1.0
@export var respawn_time: float = 5.0
