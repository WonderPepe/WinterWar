class_name FrontReports
extends Resource
## The front reports shown after each cleared wave (resources/front_reports.tres): the report
## after wave 1 is the first line, after wave 2 the second, and so on. Open the .tres in the
## Inspector to change or add reports – `dates` and `texts` go in pairs.

@export var dates: PackedStringArray = PackedStringArray() ## e.g. "21.12.1939"
@export_multiline var texts: PackedStringArray = PackedStringArray()


## The report after wave `wave` (1 = first): [date, text], or empty if there is none.
func get_report(wave: int) -> PackedStringArray:
	var i: int = wave - 1
	if i < 0 or i >= dates.size() or i >= texts.size():
		return PackedStringArray()
	return PackedStringArray([dates[i], texts[i]])
