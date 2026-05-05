extends Node

# Bump this when the save format changes incompatibly.
const SAVE_VERSION: int = 1

const SAVE_PATH: String = "user://save.json"

# Registry of savable objects, keyed by stable string identifiers.
# Each entry is the node itself; we call save_state() / load_state() on it.
var _savables: Dictionary = {}


func _ready() -> void:
	# DEFERRED so this runs after same-frame listeners that reposition the
	# player / restore stamina. Save must capture the post-skip world state
	TimeSkipSystem.time_skipped.connect(_on_time_skipped, CONNECT_DEFERRED)
	
func _on_time_skipped(from_minute: int, _to_minute: int, _context: Dictionary) -> void:
	# Only autosave if a calendar day actually rolled during this skip.
	var minutes_per_day := 24 * 60
	if from_minute / minutes_per_day != _to_minute / minutes_per_day:
		save_to_disk()


# Systems call this in their _ready to register themselves for saving.
# key must be unique and stable across versions (it's the JSON key).
func register_savable(key: String, node: Node) -> void:
	if _savables.has(key):
		push_warning("SaveSystem: overwriting savable '%s'" % key)
	_savables[key] = node


# Manual save. Returns true on success.
func save_to_disk() -> bool:
	var data := {
		"version": SAVE_VERSION,
		"timestamp_unix": int(Time.get_unix_time_from_system()),
		"savables": {},
	}
	for key in _savables:
		var node: Node = _savables[key]
		if not node.has_method("save_state"):
			push_warning("Savable '%s' has no save_state() method, skipping" % key)
			continue
		data["savables"][key] = node.save_state()

	var json := JSON.stringify(data, "\t")  # pretty-printed for debug
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: failed to open save file for writing")
		return false
	file.store_string(json)
	file.close()
	print("[Save] wrote save to %s" % SAVE_PATH)
	return true


# Returns true if a save was loaded, false if no save existed or load failed.
func load_from_disk() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("SaveSystem: save exists but failed to open")
		return false
	var json_text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(json_text)
	if parsed == null or not parsed is Dictionary:
		push_error("SaveSystem: save file is corrupt")
		return false

	var data: Dictionary = parsed
	if data.get("version") != SAVE_VERSION:
		push_error("SaveSystem: save version %s does not match current %d" %
			[data.get("version"), SAVE_VERSION])
		return false

	var savables_data: Dictionary = data.get("savables", {})

	# Iterate the registry order, not the JSON's key order. JSON parsing
	# doesn't guarantee key order preservation, and load order matters
	# (e.g., WorldStateSystem must populate before world.load_state triggers
	# a room change that reads from it).
	for key in _savables:
		if not savables_data.has(key):
			continue  # save predates this savable; skip
		var node: Node = _savables[key]
		if not node.has_method("load_state"):
			push_warning("Savable '%s' has no load_state() method" % key)
			continue
		node.load_state(savables_data[key])

	# Warn about save data that has no current registrant.
	for key in savables_data:
		if not _savables.has(key):
			push_warning("Save contains unknown key '%s', skipping" % key)

	print("[Save] loaded save from %s" % SAVE_PATH)
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		print("[Save] deleted save file")


func _on_day_rolled(_dow: int, _dom: int) -> void:
	save_to_disk()
