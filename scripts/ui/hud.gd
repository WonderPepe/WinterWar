class_name HUD
extends CanvasLayer
## The on-screen display for the player on THIS computer.
## It only READS information (signals and simple getters) and never changes the game,
## so it works the same for the host and for co-op clients.
## Every element ignores the mouse (mouse_filter = IGNORE) so it can't block mouse look.

@export var damage_flash_time: float = 0.6
@export var wave_banner_time: float = 2.5

var _player: Player
var _last_health: int = 100
var _flash: float = 0.0
var _last_wave: int = 0
var _banner_left: float = 0.0
var _death_time: float = -1.0

@onready var crosshair: Crosshair = $Crosshair
@onready var hit_marker: HitMarker = $HitMarker
@onready var damage_flash: TextureRect = $DamageFlash
@onready var health_bar: ProgressBar = $Vitals/HealthBar
@onready var health_value: Label = $Vitals/HealthBar/Value
@onready var stamina_bar: ProgressBar = $Vitals/StaminaBar
@onready var weapon_panel: Control = $WeaponPanel
@onready var weapon_name: Label = $WeaponPanel/WeaponName
@onready var ammo_label: Label = $WeaponPanel/Ammo
@onready var reload_label: Label = $WeaponPanel/Reloading
@onready var wave_label: Label = $WavePanel/Wave
@onready var enemies_label: Label = $WavePanel/Enemies
@onready var next_wave_label: Label = $WavePanel/NextWave
@onready var score_label: Label = $WavePanel/Score
@onready var wave_banner: Label = $WaveBanner
@onready var death_screen: Control = $DeathScreen
@onready var respawn_label: Label = $DeathScreen/Respawn
@onready var hit_sound: AudioStreamPlayer = $HitSound
@onready var interact_prompt: Label = $InteractPrompt
@onready var damage_indicator: DamageIndicator = $DamageIndicator
@onready var hurt_sound: AudioStreamPlayer = $HurtSound


func _ready() -> void:
	damage_flash.modulate.a = 0.0
	wave_banner.modulate.a = 0.0
	death_screen.visible = false


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_find_local_player()
		if _player == null:
			return
	_update_vitals()
	_update_weapon()
	_update_waves(delta)
	_update_death()
	_flash = maxf(_flash - delta / damage_flash_time, 0.0)
	damage_flash.modulate.a = _flash


func _find_local_player() -> void:
	for node in get_tree().get_nodes_in_group("players"):
		var p := node as Player
		if p and p.is_local_player():
			_player = p
			_last_health = p.health
			p.health_changed.connect(_on_health_changed)
			p.weapons.hit_confirmed.connect(_on_hit_confirmed)
			p.hurt_from.connect(damage_indicator.add_hit)
			damage_indicator.set_player(p)
			return


func _on_health_changed(new_health: int) -> void:
	if new_health < _last_health:
		_flash = 1.0 # we got hurt: flash the screen edges red
		hurt_sound.play()
	_last_health = new_health


func _on_hit_confirmed(killed: bool) -> void:
	hit_marker.show_hit(killed)
	hit_sound.pitch_scale = 0.75 if killed else 1.0
	hit_sound.play()


func _update_vitals() -> void:
	health_bar.max_value = _player.max_health
	health_bar.value = _player.health
	health_value.text = str(_player.health)
	stamina_bar.max_value = _player.max_stamina
	stamina_bar.value = _player.stamina


func _update_weapon() -> void:
	var weapons: WeaponController = _player.weapons
	var w: WeaponData = weapons.get_current_weapon()
	weapon_panel.visible = not _player.is_dead
	if w:
		weapon_name.text = w.display_name
		var reserve: int = weapons.get_reserve_ammo()
		ammo_label.text = "%d / %s" % [weapons.get_mag_ammo(), "∞" if reserve < 0 else str(reserve)]
	reload_label.visible = weapons.is_reloading_now()
	reload_label.text = "NEW BELT" if weapons.get_mounted_gun() else "RELOADING"
	# "[F] Use Maxim" near a free mounted gun, a reminder how to leave while on it.
	var gun := weapons.get_mounted_gun()
	if _player.is_dead:
		interact_prompt.text = ""
	elif gun:
		interact_prompt.text = "[F] Leave the gun    [R] New belt"
	else:
		var usable := _player.find_usable_gun()
		interact_prompt.text = "[F] Use %s" % usable.data.display_name if usable else ""
	crosshair.visible = not weapons.is_aiming and not _player.is_dead
	crosshair.spread_deg = weapons.get_current_spread_deg()
	crosshair.fov_deg = _player.camera.fov


func _update_waves(delta: float) -> void:
	var waves := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	if waves == null:
		return
	wave_label.text = "WAVE %d" % waves.wave_number if waves.wave_number > 0 else "Get ready"
	enemies_label.text = "Enemies: %d" % waves.alive_count
	var next: float = waves.get_time_to_next_wave()
	next_wave_label.visible = next > 0.0
	next_wave_label.text = "Next wave in %d s" % ceili(next)
	score_label.text = "Kills %d   Deaths %d" % [_player.kills, _player.deaths]
	# Big "WAVE n" banner when a new wave starts.
	if waves.wave_number > _last_wave:
		_last_wave = waves.wave_number
		wave_banner.text = "WAVE %d" % _last_wave
		_banner_left = wave_banner_time
	_banner_left = maxf(_banner_left - delta, 0.0)
	wave_banner.modulate.a = clampf(_banner_left / 0.6, 0.0, 1.0) # fades out in the last 0.6 s


func _update_death() -> void:
	death_screen.visible = _player.is_dead
	if not _player.is_dead:
		_death_time = -1.0
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if _death_time < 0.0:
		_death_time = now
	var game := get_tree().get_first_node_in_group("game") as Game
	var total: float = game.respawn_time if game else 5.0
	respawn_label.text = "Respawning in %d..." % maxi(ceili(total - (now - _death_time)), 1)
