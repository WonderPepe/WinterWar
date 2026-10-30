class_name FootstepSounds
extends RefCounted
## Footstep recordings, found by file name in res://assets/audio/footsteps/.
##
## Put sound files (.ogg or .wav) in that folder and they are used automatically:
##   a name containing "snow"   → walking on snow (also used in the trench if there is nothing else)
##   a name containing "trench" or "gravel" → the trampled trench floor
##   a name containing "wood"   → the bunker floor and the Maxim platform
## Example: footstep_snow_000.ogg … footstep_snow_004.ogg (Kenney "Impact Sounds", CC0).
## No files = no footsteps (the game stays silent instead of playing bad sounds).

const FOLDER: String = "res://assets/audio/footsteps/"
const SURFACES: Dictionary = {
	"snow": ["snow"],
	"trench": ["trench", "gravel"],
	"wood": ["wood"],
}

static var _cache: Dictionary = {} # surface -> Array[AudioStream]
static var _loaded: bool = false


## All recordings for a surface ("snow", "trench", "wood"); may be empty.
static func get_sounds(surface: String) -> Array[AudioStream]:
	_load_all()
	var list: Array[AudioStream] = _cache.get(surface, [] as Array[AudioStream])
	if list.is_empty() and surface == "trench":
		list = _cache.get("snow", [] as Array[AudioStream])
	return list


static func has_any() -> bool:
	_load_all()
	for surface in _cache:
		if not (_cache[surface] as Array).is_empty():
			return true
	return false


static func _load_all() -> void:
	if _loaded:
		return
	_loaded = true
	for surface in SURFACES:
		_cache[surface] = [] as Array[AudioStream]
	if not DirAccess.dir_exists_absolute(FOLDER):
		return
	# list_directory also works in exported games (where files are stored differently).
	for file in ResourceLoader.list_directory(FOLDER):
		var lower: String = file.to_lower()
		if not (lower.ends_with(".ogg") or lower.ends_with(".wav") or lower.ends_with(".mp3")):
			continue
		for surface: String in SURFACES:
			for word: String in SURFACES[surface]:
				if lower.contains(word):
					var stream := load(FOLDER + file) as AudioStream
					if stream:
						(_cache[surface] as Array[AudioStream]).append(stream)
