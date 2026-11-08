class_name FrontReports
extends Resource
## The battle briefings (resources/front_reports.tres): line 1 is battle 1, line 2 is battle 2,
## and so on. Shown BEFORE each battle (loading screen for the first, the day screen after each
## cleared battle for the next). Open the .tres in the Inspector to change or add briefings –
## `dates`, `texts` and `weathers` go together. (The class keeps its old name; the owner's old
## Finnish front reports are kept in tools/build_scenes.gd as OLD_FRONT_REPORTS, not shown.)

@export var dates: PackedStringArray = PackedStringArray() ## e.g. "30 November 1939"
@export_multiline var texts: PackedStringArray = PackedStringArray() ## The briefing text.
## Weather lines for each battle, e.g. "Weather: Dense Fog\nTemperature: ~−20°C".
@export_multiline var weathers: PackedStringArray = PackedStringArray()
## A wartime photo for each day (SA-kuva, CC BY 4.0), e.g. "res://assets/photos/sa_kuva_a_511.jpg".
## Empty = no photo that day. Loaded only when the day screen shows it.
@export var photos: PackedStringArray = PackedStringArray()


## The briefing of battle `wave` (1 = first): [date, text], or empty if there is none.
func get_report(wave: int) -> PackedStringArray:
	var i: int = wave - 1
	if i < 0 or i >= dates.size() or i >= texts.size():
		return PackedStringArray()
	return PackedStringArray([dates[i], texts[i]])


## The weather lines of battle `wave`, or "".
func get_weather(wave: int) -> String:
	var i: int = wave - 1
	if i < 0 or i >= weathers.size():
		return ""
	return weathers[i]


## The photo shown with the briefing of battle `wave`, or null.
func get_photo(wave: int) -> Texture2D:
	var i: int = wave - 1
	if i < 0 or i >= photos.size() or photos[i].is_empty() or not ResourceLoader.exists(photos[i]):
		return null
	return load(photos[i]) as Texture2D
