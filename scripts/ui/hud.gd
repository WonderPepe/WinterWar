class_name HUD
extends CanvasLayer
## The on-screen display for the player on THIS computer.
## It only READS information (signals and simple getters) and never changes the game,
## so it works the same for the host and for co-op clients.
## Every element ignores the mouse (mouse_filter = IGNORE) so it can't block mouse look.

@export var damage_flash_time: float = 0.6
@export var wave_banner_time: float = 2.5
@export var front_reports: FrontReports ## Shown one by one after each cleared wave.
@export var report_time: float = 16.0 ## Seconds a front report stays up (it also goes when the next wave starts).

var _player: Player
var _last_health: int = 100
var _flash: float = 0.0
var _last_wave: int = 0
var _banner_left: float = 0.0
var _death_time: float = -1.0
var _last_cleared: int = 0
var _report_left: float = 0.0

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
@onready var overheat_label: Label = $WeaponPanel/Overheated
@onready var heat_row: Control = $WeaponPanel/HeatRow
@onready var heat_bar: ProgressBar = $WeaponPanel/HeatRow/HeatBar
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
@onready var trench_label: Label = $WavePanel/TrenchAlert
@onready var banner_sub: Label = $WaveBannerSub
@onready var bandage_label: Label = $Vitals/Bandages
@onready var end_screen: EndScreen = $EndScreen
@onready var report_panel: Control = $FrontReport
@onready var report_date: Label = $FrontReport/VBox/Date
@onready var report_text: Label = $FrontReport/VBox/Text

var _director: MatchDirector
var _message: String = ""
var _message_until: float = 0.0


func _ready() -> void:
	damage_flash.modulate.a = 0.0
	wave_banner.modulate.a = 0.0
	banner_sub.modulate.a = 0.0
	death_screen.visible = false
	report_panel.visible = false


func _process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_find_local_player()
		if _player == null:
			return
	if _director == null or not is_instance_valid(_director):
		_director = get_tree().get_first_node_in_group("match_director") as MatchDirector
	_update_vitals()
	_update_weapon()
	_update_waves(delta)
	_update_death()
	if _director and _director.is_over() and not end_screen.visible:
		end_screen.open(_director, _player, front_reports)
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
			p.resupplied.connect(_show_message.bind("Ammo and bandages refilled"))
			damage_indicator.set_player(p)
			return


func _on_health_changed(new_health: int) -> void:
	if new_health < _last_health:
		_flash = 1.0 # we got hurt: flash the screen edges red
		# Real recordings only (assets/audio/recorded/hurt…): the generated thump sounded bad.
		var sound: AudioStream = RecordedSounds.pick("hurt")
		if sound:
			hurt_sound.stream = sound
			hurt_sound.pitch_scale = randf_range(0.95, 1.05)
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
	if _player.is_bandaging:
		bandage_label.text = "Bandaging... %d %%" % roundi(_player.get_bandage_progress() * 100.0)
	else:
		bandage_label.text = "Bandages: %d   [B]" % _player.bandages


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
	_update_heat(weapons.get_mounted_gun())
	# "[F] Use Maxim" near a free mounted gun, a reminder how to leave while on it.
	var gun := weapons.get_mounted_gun()
	if _player.is_dead:
		interact_prompt.text = ""
	elif gun:
		interact_prompt.text = "[F] Leave the gun    [R] New belt"
	elif Time.get_ticks_msec() / 1000.0 < _message_until:
		interact_prompt.text = _message
	else:
		var usable := _player.find_usable_gun()
		var crate := _player.find_ammo_crate() if usable == null else null
		if usable:
			interact_prompt.text = "[F] Use %s" % usable.data.display_name
		elif crate:
			interact_prompt.text = "[F] Take ammunition and bandages"
		else:
			interact_prompt.text = ""
	crosshair.visible = not weapons.is_aiming and not _player.is_dead
	crosshair.spread_deg = weapons.get_current_spread_deg()
	crosshair.fov_deg = _player.camera.fov


## Maxim water-jacket heat: white → orange → red, and "OVERHEATED" (blinking) at the top.
func _update_heat(gun: MountedGun) -> void:
	var shown: bool = gun != null and gun.data != null and gun.data.heat_per_shot > 0.0
	heat_row.visible = shown
	overheat_label.visible = shown and gun.is_overheated
	if not shown:
		return
	heat_bar.value = gun.heat
	var col: Color = Color(0.95, 0.95, 0.95).lerp(Color(1.0, 0.6, 0.2), smoothstep(0.3, 0.6, gun.heat))
	col = col.lerp(Color(0.95, 0.2, 0.12), smoothstep(0.75, 1.0, gun.heat))
	(heat_bar.get_theme_stylebox("fill") as StyleBoxFlat).bg_color = col
	overheat_label.modulate.a = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 120.0)


func _update_waves(delta: float) -> void:
	var waves := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	if waves == null:
		return
	var total: int = _director.waves_to_win if _director else 0
	if waves.wave_number <= 0:
		wave_label.text = "Get ready"
	elif total > 0:
		wave_label.text = "WAVE %d / %d" % [waves.wave_number, total]
	else:
		wave_label.text = "WAVE %d" % waves.wave_number
	# Soviets inside the trench: the line breaks when there are too many at once.
	var inside: int = _director.in_trench if _director else 0
	trench_label.visible = inside > 0
	if inside > 0:
		trench_label.text = "SOVIETS IN THE TRENCH: %d / %d" % [inside, _director.trench_limit]
		trench_label.modulate.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 110.0)
	enemies_label.text = "Enemies: %d" % waves.alive_count
	var next: float = waves.get_time_to_next_wave()
	next_wave_label.visible = next > 0.0
	next_wave_label.text = "Next wave in %d s" % ceili(next)
	score_label.text = "Kills %d   Deaths %d" % [_player.kills, _player.deaths]
	_update_front_report(delta)
	# Big "WAVE n" banner when a new wave starts.
	if waves.wave_number > _last_wave:
		_last_wave = waves.wave_number
		_report_left = minf(_report_left, 0.6) # the report makes way for the new wave
		wave_banner.text = "WAVE %d" % _last_wave
		banner_sub.text = ""
		if _last_wave == 1 and total > 0:
			banner_sub.text = "Hold the line until dusk – %d waves" % total
		elif total > 0 and _last_wave == total:
			banner_sub.text = "The last wave – hold on!"
		# G2: what is coming (only worth saying once officers or machine guns join in).
		if waves.wave_officers > 0 or waves.wave_mg_teams > 0:
			var comp: String = WaveData.describe(waves.wave_riflemen, waves.wave_officers, waves.wave_mg_teams)
			banner_sub.text = comp if banner_sub.text == "" else banner_sub.text + "\n" + comp
		_banner_left = wave_banner_time + (1.5 if banner_sub.text != "" else 0.0)
	_banner_left = maxf(_banner_left - delta, 0.0)
	wave_banner.modulate.a = clampf(_banner_left / 0.6, 0.0, 1.0) # fades out in the last 0.6 s
	banner_sub.modulate.a = wave_banner.modulate.a


## A wave has been cleared: show the next front report (in order: wave 1 → the first one).
func _update_front_report(delta: float) -> void:
	var cleared: int = _director.waves_cleared if _director else 0
	if cleared > _last_cleared:
		_last_cleared = cleared
		var report: PackedStringArray = front_reports.get_report(cleared) if front_reports else PackedStringArray()
		if report.size() == 2:
			report_date.text = report[0]
			report_text.text = report[1]
			_report_left = report_time
	_report_left = maxf(_report_left - delta, 0.0)
	report_panel.visible = _report_left > 0.0 and not end_screen.visible
	report_panel.modulate.a = clampf(_report_left / 0.6, 0.0, 1.0) * clampf((report_time - _report_left) / 0.4, 0.0, 1.0)


func _show_message(text: String) -> void:
	_message = text
	_message_until = Time.get_ticks_msec() / 1000.0 + 2.0


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
