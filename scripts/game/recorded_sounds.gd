class_name RecordedSounds
extends RefCounted
## Real sound recordings, found by file name in res://assets/audio/recorded/.
##
## Drop .ogg / .wav files with these names into that folder and the game uses them:
##   reload_mosin…  reloading the Mosin (stripper clip)
##   reload_suomi…  changing the Suomi's drum
##   reload_maxim…  a new belt in the Maxim
##   hurt…          you get hit (several files = a random one each time)
##   officer_whistle…  a Soviet officer's whistle (G2)
##   dp27…          one DP-27 machine-gun shot (G2)
##   telegraph…     typewriter clatter while a front-report telegram types itself out
## Example: hurt_1.ogg, hurt_2.ogg, hurt_3.ogg, reload_mosin.ogg.
## Missing files = silence (better than a bad placeholder). See the README in the folder.

const FOLDER: String = "res://assets/audio/recorded/"

static var _streams: Dictionary = {} # lower-case file name -> AudioStream
static var _loaded: bool = false


## All recordings whose file name starts with `prefix`; may be empty.
static func get_sounds(prefix: String) -> Array[AudioStream]:
	_load_all()
	var list: Array[AudioStream] = []
	if prefix.is_empty():
		return list
	for file: String in _streams:
		if file.begins_with(prefix.to_lower()):
			list.append(_streams[file])
	return list


## One random recording for `prefix`, or null if there is none.
static func pick(prefix: String) -> AudioStream:
	var list: Array[AudioStream] = get_sounds(prefix)
	return null if list.is_empty() else list[randi() % list.size()]


static func _load_all() -> void:
	if _loaded:
		return
	_loaded = true
	if not DirAccess.dir_exists_absolute(FOLDER):
		return
	# list_directory also works in exported games (where files are stored differently).
	for file in ResourceLoader.list_directory(FOLDER):
		var lower: String = file.to_lower()
		if lower.ends_with(".ogg") or lower.ends_with(".wav") or lower.ends_with(".mp3"):
			var stream := load(FOLDER + file) as AudioStream
			if stream:
				_streams[lower] = stream
