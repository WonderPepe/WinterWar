class_name DifficultyData
extends Resource
## One difficulty level (resources/difficulty/*.tres). Open it in the Inspector to tune it.

@export var display_name: String = "Normal"
@export var waves_to_win: int = 8 ## Clear this many waves and the line has held until dusk.
@export var trench_limit: int = 4 ## This many Soviets in the trench at the same time = the line is broken.
@export var base_enemies: int = 6 ## Soldiers in wave 1 (only used when `waves` is empty).
@export var enemies_added_per_wave: int = 2 ## (only used when `waves` is empty)
## G2: what each wave is made of (riflemen, officers, machine-gun teams). Waves beyond the end
## of the list repeat the last entry. Empty = only riflemen, base_enemies + added per wave.
@export var waves: Array[WaveData] = []
@export var enemy_spread_multiplier: float = 1.0 ## < 1 = the enemy aims better.
@export var respawn_time: float = 5.0
