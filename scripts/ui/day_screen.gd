class_name DayScreen
extends Control
## Between battles (B1): the screen goes dark, a wartime photo (SA-kuva) fades in, the date comes
## up and the NEXT battle's weather and briefing type themselves out as a telegram, with radio
## static for the first seconds. (Battle 1's briefing is on the loading screen.) Space / Enter continues, otherwise it closes by itself after reading time.
##
## Part of the HUD (only reads the synced `MatchDirector.waves_cleared`), so co-op players see it
## too. On the host it holds the next wave's countdown (`WaveSpawner.hold`) while it is open.
## The game is not paused: the battle sounds are only turned down behind it.

signal closed

@export var intro_delay: float = 2.5 ## Seconds of "BATTLE n COMPLETED" (HUD banner) before the fade to black.
@export var type_speed: float = 28.0 ## Telegram letters per second.
@export var type_start: float = 3.0 ## Seconds after opening when the telegram starts typing.
@export var read_time: float = 7.0 ## Seconds to read after the telegram is typed out.
@export var skip_after: float = 1.5 ## Space / Enter works only after this many seconds.
@export var static_time: float = 5.0 ## Seconds of radio static at the start.
@export var static_volume_db: float = -8.0
@export var duck_db: float = -20.0 ## Battle sounds (SFX + Ambience) are turned down this much.
@export var zoom: float = 0.06 ## The photo slowly zooms in this much over the whole screen.
@export var photo_box: Vector2 = Vector2(600, 440) ## Largest size of the photo on screen.

const FADE_OUT: float = 1.2 # seconds: content goes first, then the black

var is_open: bool = false
var wave: int = 0 ## The battle that was just cleared (the briefing shown is for wave + 1).

var _t: float = 0.0
var _total: float = 0.0
var _closing: float = -1.0 # seconds since closing started (< 0 = not closing)
var _typed: float = 0.0

@onready var black: ColorRect = $Black
@onready var content: Control = $Content
@onready var title: Control = $Content/Title
@onready var day_label: Label = $Content/Title/Day
@onready var date_label: Label = $Content/Title/Date
@onready var frame: PanelContainer = $Content/PhotoFrame
@onready var clip: Control = $Content/PhotoFrame/Clip
@onready var photo: TextureRect = $Content/PhotoFrame/Clip/Photo
@onready var credit: Label = $Content/Credit
@onready var telegram: Control = $Content/Telegram
@onready var tele_header: Label = $Content/Telegram/VBox/Header
@onready var tele_date: Label = $Content/Telegram/VBox/Date
@onready var tele_text: Label = $Content/Telegram/VBox/Text
@onready var type_sound: AudioStreamPlayer = $Content/Telegram/TypeSound
@onready var hint: Label = $Content/Hint
@onready var static_player: AudioStreamPlayer = $Static

func _ready() -> void:
	add_to_group("day_screen")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## True while the screen is fully black (the battlefield can't be seen): DuskLight changes the
## light to the new day's light then, so nobody sees it change.
func is_black() -> bool:
	return is_open and black.color.a >= 0.99


## Shows the briefing of the battle after `cleared_wave`. Returns false if there is none.
func open(cleared_wave: int, reports: FrontReports) -> bool:
	var next: int = cleared_wave + 1
	var r: PackedStringArray = reports.get_report(next) if reports else PackedStringArray()
	if r.size() != 2:
		return false
	wave = cleared_wave
	day_label.text = "B A T T L E   %d" % next
	date_label.text = r[0]
	tele_header.text = "B R I E F I N G"
	tele_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tele_date.text = reports.get_weather(next) + "\n" # (a blank line before the briefing)
	tele_text.text = r[1]
	hint.text = "[Space] Continue"
	_set_photo(reports.get_photo(next))
	_typed = 0.0
	_t = -intro_delay # negative = the battlefield is still visible (the HUD shows "BATTLE n COMPLETED")
	_closing = -1.0
	_total = type_start + (r[0].length() + r[1].length()) / type_speed + read_time
	is_open = true
	visible = true
	_update(0.0)
	_set_hold(true)
	return true


## Starts fading out (Space, the next wave, or time is up).
func close() -> void:
	if is_open and _closing < 0.0:
		_closing = 0.0


## Hides at once (the end screen takes over).
func close_now() -> void:
	if is_open:
		_finish()


func _set_photo(tex: Texture2D) -> void:
	photo.texture = tex
	frame.visible = tex != null
	credit.visible = tex != null
	if tex == null:
		return
	# Fit the photo into the box, keeping its shape (one photo is upright).
	var s: Vector2 = tex.get_size()
	var k: float = minf(photo_box.x / s.x, photo_box.y / s.y)
	var size: Vector2 = (s * k).round()
	clip.custom_minimum_size = size
	photo.size = size
	photo.pivot_offset = size * 0.5
	frame.reset_size()
	# Centre the frame in the photo area (left half), the credit just below it.
	var area_centre := Vector2(-300, 30)
	var fsize: Vector2 = frame.get_combined_minimum_size()
	frame.position = area_centre - fsize * 0.5
	credit.position = Vector2(frame.position.x, frame.position.y + fsize.y + 6)
	credit.size.x = fsize.x


func _process(delta: float) -> void:
	if is_open:
		_update(delta)


func _input(event: InputEvent) -> void:
	if not is_open or _closing >= 0.0 or _t < skip_after:
		return
	if event.is_action_pressed("jump") or event.is_action_pressed("ui_accept"):
		close()
		get_viewport().set_input_as_handled()


func _update(delta: float) -> void:
	var was_before_fade: bool = _t < 0.0
	_t += delta
	if was_before_fade and _t >= 0.0 and _closing < 0.0:
		_start_static()
	if _closing < 0.0 and _t >= _total:
		close()
	var shown: float = 1.0
	var black_a: float = clampf(_t / 1.0, 0.0, 1.0)
	if _closing >= 0.0:
		_closing += delta
		shown = clampf(1.0 - _closing / 0.6, 0.0, 1.0)
		black_a = minf(black_a, clampf(1.0 - (_closing - 0.4) / (FADE_OUT - 0.4), 0.0, 1.0))
		if _closing >= FADE_OUT:
			_finish()
			return
	black.color.a = black_a
	content.modulate.a = shown
	frame.modulate.a = clampf((_t - 1.0) / 1.2, 0.0, 1.0)
	credit.modulate.a = frame.modulate.a
	title.modulate.a = clampf((_t - 1.8) / 0.8, 0.0, 1.0)
	telegram.modulate.a = clampf((_t - type_start + 0.4) / 0.4, 0.0, 1.0)
	hint.modulate.a = clampf((_t - type_start) / 0.8, 0.0, 1.0) * 0.8
	photo.scale = Vector2.ONE * (1.0 + zoom * clampf(_t / maxf(_total, 0.1), 0.0, 1.0))
	_type(delta)
	_update_static()
	_duck(black_a)


## The telegram types itself out letter by letter: first the date, then the message.
func _type(delta: float) -> void:
	var date_len: int = tele_date.text.length()
	var total: int = date_len + tele_text.text.length()
	var was_typing: bool = _typed < total
	if _t >= type_start:
		if _typed == 0.0:
			var clatter: AudioStream = RecordedSounds.pick("telegraph")
			if clatter:
				type_sound.stream = clatter
				type_sound.play()
		_typed = minf(_typed + delta * type_speed, float(total))
	var n: int = int(_typed)
	tele_date.visible_characters = mini(n, date_len)
	tele_text.visible_characters = maxi(n - date_len, 0)
	if was_typing and n >= total and type_sound.playing:
		type_sound.stop()


## Radio static (a real recording: assets/audio/recorded/radio_static…). None = silence.
func _start_static() -> void:
	var noise: AudioStream = RecordedSounds.pick("radio_static")
	if noise:
		static_player.stream = noise
		static_player.volume_db = -60.0
		static_player.play()


## Static fades in quickly, stays, and fades out at the end of `static_time`.
func _update_static() -> void:
	if not static_player.playing:
		return
	var v: float = clampf(_t / 0.6, 0.0, 1.0) * clampf((static_time - _t) / 1.5, 0.0, 1.0)
	if _closing >= 0.0:
		v *= clampf(1.0 - _closing / 0.6, 0.0, 1.0)
	if v <= 0.001 and _t > 1.0:
		static_player.stop()
		return
	static_player.volume_db = static_volume_db + linear_to_db(maxf(v, 0.0001))


## Turns the battle sounds down behind the black screen (0 = normal, 1 = fully down).
func _duck(amount: float) -> void:
	var db: float = duck_db * amount
	var sfx: int = AudioServer.get_bus_index(&"SFX")
	if sfx >= 0:
		AudioServer.set_bus_volume_db(sfx, db)
	var amb: int = AudioServer.get_bus_index(&"Ambience")
	if amb >= 0:
		# Same formula as Settings.apply(), plus the duck.
		AudioServer.set_bus_volume_db(amb, linear_to_db(maxf(Settings.ambience_volume, 0.0001)) - 3.0 + db)


## Host: the next wave's countdown waits while the day screen is open.
func _set_hold(on: bool) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var spawner := get_tree().get_first_node_in_group("wave_spawner") as WaveSpawner
	if spawner:
		spawner.hold = on


func _finish() -> void:
	is_open = false
	visible = false
	_closing = -1.0
	static_player.stop()
	type_sound.stop()
	_duck(0.0)
	_set_hold(false)
	closed.emit()


func _exit_tree() -> void:
	if is_open:
		_duck(0.0)
		_set_hold(false)
