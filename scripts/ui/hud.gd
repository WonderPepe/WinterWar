class_name HUD
extends CanvasLayer
## The on-screen display for the player on THIS computer.
## It only READS information (signals and simple getters) and never changes the game,
## so it works the same for the host and for co-op clients.
## Every element ignores the mouse (mouse_filter = IGNORE) so it can't block mouse look.

@export var damage_flash_time: float = 0.6
@export var wave_banner_time: float = 2.5
@export var tank_hint_time: float = 14.0 ## Seconds the Molotov hint stays up in the first tank battle.
@export var front_reports: FrontReports ## The day screen shows them one by one after each cleared wave.

var _player: Player
var _last_health: int = 100
var _flash: float = 0.0
var _last_wave: int = 0
var _banner_left: float = 0.0
var _death_time: float = -1.0
var _last_cleared: int = 0

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
@onready var interact_prompt: Label = $InteractPrompt
@onready var damage_indicator: DamageIndicator = $DamageIndicator
@onready var hurt_sound: AudioStreamPlayer = $HurtSound
@onready var trench_label: Label = $WavePanel/TrenchAlert
@onready var test_tag: Label = $WavePanel/TestTag
@onready var banner_sub: Label = $WaveBannerSub
@onready var bandage_label: Label = $Vitals/Bandages
@onready var end_screen: EndScreen = $EndScreen
@onready var day_screen: DayScreen = $DayScreen
@onready var artillery_label: Label = $ArtilleryWarning
@onready var tank_hint: Label = $TankHint

var _artillery: ArtilleryBarrage
var _raid: AirRaid

var _director: MatchDirector
var _message: String = ""
var _message_until: float = 0.0
var _tank_hint_shown: bool = false # once per match: the first battle that brings tanks
var _tank_hint_left: float = 0.0
var _tank_hint_wait: float = 0.0 # it waits for the BATTLE n banner to fade (same place on screen)


func _ready() -> void:
	damage_flash.modulate.a = 0.0
	wave_banner.modulate.a = 0.0
	banner_sub.modulate.a = 0.0
	death_screen.visible = false


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
	_update_artillery()
	_update_death()
	if _director and _director.is_over() and not end_screen.visible:
		day_screen.close_now()
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
			p.molotov.picked_up.connect(func(n: int) -> void: _show_message("Molotov cocktails: %d   [G]" % n))
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
	hit_marker.show_hit(killed) # (no sound: the owner removed the generated hit tick)


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
	if _player.molotov.count > 0:
		bandage_label.text += "      Molotovs: %d   [G]" % _player.molotov.count


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
	reload_label.modulate = Color.WHITE
	if _player.molotov.is_selected():
		_update_molotov(_player.molotov)
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
		var bottles := _player.find_molotov_crate() if usable == null else null
		if bottles and (crate == null or _player.global_position.distance_to(bottles.global_position) < _player.global_position.distance_to(crate.global_position)):
			crate = null
		if usable:
			interact_prompt.text = "[F] Use %s" % usable.data.display_name
		elif bottles:
			interact_prompt.text = "[F] Take Molotov cocktails"
		elif crate:
			interact_prompt.text = "[F] Take ammunition and bandages"
		else:
			interact_prompt.text = ""
	crosshair.visible = not weapons.is_aiming and not _player.is_dead
	crosshair.spread_deg = weapons.get_current_spread_deg()
	crosshair.fov_deg = _player.camera.fov


## Maxim water-jacket heat: white → orange → red, and "OVERHEATED" (blinking) at the top.
## T2: a Molotov cocktail in the hand – what to do next, and a warning when it burns too long.
func _update_molotov(m: MolotovHandler) -> void:
	weapon_name.text = "Molotov cocktail"
	ammo_label.text = "%d" % m.count
	reload_label.visible = true
	match m.phase:
		MolotovHandler.Phase.HELD:
			reload_label.text = "HOLD RIGHT MOUSE TO LIGHT IT    [1/2] GUN"
		MolotovHandler.Phase.IGNITING:
			reload_label.text = "LIGHTING... %d %%" % roundi(m.get_ignite_progress() * 100.0)
		MolotovHandler.Phase.LIT:
			var t: float = m.get_lit_time()
			if t >= m.danger_time:
				reload_label.text = "IT BURNS YOUR HAND – THROW IT!"
				reload_label.modulate = Color(1.0, 0.25, 0.15) if fmod(t, 0.4) < 0.2 else Color(1.0, 0.8, 0.3)
			elif t >= m.warn_time:
				reload_label.text = "THE RAG BURNS DOWN – THROW!  [LEFT MOUSE]"
				reload_label.modulate = Color(1.0, 0.6, 0.25)
			else:
				reload_label.text = "LIT – THROW [LEFT MOUSE]   aim [RIGHT MOUSE]"
		_:
			reload_label.visible = false


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
		wave_label.text = "BATTLE %d / %d" % [waves.wave_number, total]
	else:
		wave_label.text = "BATTLE %d" % waves.wave_number
	# Soviets inside the trench: the line breaks when there are too many at once.
	var inside: int = _director.in_trench if _director else 0
	trench_label.visible = inside > 0
	if inside > 0:
		trench_label.text = "SOVIETS IN THE TRENCH: %d / %d" % [inside, _director.trench_limit]
		trench_label.modulate.a = 0.65 + 0.35 * sin(Time.get_ticks_msec() / 110.0)
	enemies_label.text = "Enemies: %d" % waves.alive_count
	test_tag.visible = _director != null and _director.test_wave > 0
	var next: float = waves.get_time_to_next_wave()
	next_wave_label.visible = next > 0.0
	next_wave_label.text = "Battle %d begins in %d s" % [waves.wave_number + 1, ceili(next)]
	score_label.text = "Kills %d   Deaths %d" % [_player.kills, _player.deaths]
	_update_day_screen()
	# Big "BATTLE n" banner when a new wave starts.
	if waves.wave_number > _last_wave and _director and waves.wave_number < _director.test_wave:
		_last_wave = waves.wave_number # test mode: the skipped waves get no banner
	if waves.wave_number > _last_wave:
		_last_wave = waves.wave_number
		day_screen.close() # the day screen makes way for the new wave
		wave_banner.text = "BATTLE %d" % _last_wave
		banner_sub.text = ""
		if _last_wave == 1 and total > 0:
			banner_sub.text = "Hold the line through %d battles" % total
		elif total > 0 and _last_wave == total:
			banner_sub.text = "The last battle – hold on!"
		# G2/T3: what is coming (only worth saying once officers, machine guns or tanks join in).
		if waves.wave_officers > 0 or waves.wave_mg_teams > 0 or waves.wave_tanks > 0:
			var comp: String = WaveData.describe(waves.wave_riflemen, waves.wave_officers, waves.wave_mg_teams, waves.wave_tanks)
			banner_sub.text = comp if banner_sub.text == "" else banner_sub.text + "\n" + comp
		_banner_left = wave_banner_time + (1.5 if banner_sub.text != "" else 0.0)
		if waves.wave_tanks > 0 and not _tank_hint_shown:
			_show_tank_hint()
	_banner_left = maxf(_banner_left - delta, 0.0)
	if _tank_hint_wait > 0.0:
		_tank_hint_wait = maxf(_tank_hint_wait - delta, 0.0)
	else:
		_tank_hint_left = maxf(_tank_hint_left - delta, 0.0)
	tank_hint.visible = _tank_hint_left > 0.0 and _tank_hint_wait <= 0.0 and _banner_left <= 0.0
	tank_hint.modulate.a = clampf(_tank_hint_left / 1.0, 0.0, 1.0) # fades out in the last second
	wave_banner.modulate.a = clampf(_banner_left / 0.6, 0.0, 1.0) # fades out in the last 0.6 s
	banner_sub.modulate.a = wave_banner.modulate.a


## Artillery: warning, then "stay in the trench" while it lasts (nothing shown when it ends).
func _update_artillery() -> void:
	if _artillery == null or not is_instance_valid(_artillery):
		_artillery = get_tree().get_first_node_in_group("artillery") as ArtilleryBarrage
		if _artillery == null:
			artillery_label.visible = false
			return
	var now: float = Time.get_ticks_msec() / 1000.0
	var blink: float = 0.6 + 0.4 * sin(now * 9.0)
	if _raid == null or not is_instance_valid(_raid):
		_raid = get_tree().get_first_node_in_group("air_raid") as AirRaid
	if _raid and _raid.phase == AirRaid.Phase.APPROACH:
		_show_artillery("AIR RAID! GET INTO THE TRENCH!", Color(1.0, 0.45, 0.3), blink)
		return
	if _raid and _raid.phase == AirRaid.Phase.BOMBING:
		if ArtilleryBarrage.is_in_shelter(_player) or _player.is_dead:
			artillery_label.visible = false
		else:
			_show_artillery("GET INTO THE TRENCH!", Color(1.0, 0.35, 0.25), blink)
		return
	if _artillery.phase == ArtilleryBarrage.Phase.WARNING:
		_show_artillery("ARTILLERY! GET DOWN INTO THE TRENCH!", Color(1.0, 0.45, 0.3), blink)
	elif _artillery.phase == ArtilleryBarrage.Phase.FIRING:
		if ArtilleryBarrage.is_in_shelter(_player) or _player.is_dead:
			artillery_label.visible = false # no text while you are down in the trench
		else:
			_show_artillery("GET INTO THE TRENCH!", Color(1.0, 0.35, 0.25), blink)
	else:
		artillery_label.visible = false


func _show_artillery(text: String, color: Color, alpha: float) -> void:
	artillery_label.visible = not end_screen.visible
	artillery_label.text = text
	artillery_label.add_theme_color_override("font_color", color)
	artillery_label.modulate.a = alpha


## A wave has been cleared: a new day – the day screen with the photo and front report
## (in order: wave 1 → the first report). Not after the last wave: the end screen takes over.
func _update_day_screen() -> void:
	var cleared: int = _director.waves_cleared if _director else 0
	if cleared > _last_cleared:
		_last_cleared = cleared
		# Test mode: the waves before the chosen one were skipped – no day screens for them.
		if not _director.is_over() and cleared >= _director.test_wave:
			# "BATTLE n COMPLETED" over the battlefield first; the day screen fades in after it.
			wave_banner.text = "BATTLE %d COMPLETED" % cleared
			banner_sub.text = ""
			_banner_left = day_screen.intro_delay
			day_screen.open(cleared, front_reports)


## The first battle with tanks: tells where the Molotov cocktails are and how to use them.
## The keys come from the Input Map (the same names as the Controls screen).
func _show_tank_hint() -> void:
	_tank_hint_shown = true
	_tank_hint_left = tank_hint_time
	_tank_hint_wait = _banner_left
	var k := ControlsPanel.key_text
	tank_hint.text = "TANKS ARE COMING!\nMolotov cocktails are in boxes in the trench – walk up to one and press [%s]\n[%s] bottle in hand  ·  hold [%s] to light it\n[%s] throw – aim for the engine deck at the back" \
			% [k.call("interact"), k.call("molotov"), k.call("aim"), k.call("fire")]


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
