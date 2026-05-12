extends Node

# ScheduleDatabase autoload. Mirrors DialogueDatabase.
#
# Loads .sched files from res://data/schedules/, hot-reloads them in
# debug builds, and answers "given the current context, which time-keyed
# entry is this NPC's location?" Each file contains one or more BLOCKS;
# the highest-specificity block matching the context wins, and its
# entries drive the NPC for the duration of that match.
#
# F6 forces a manual reload (F5 is owned by DialogueDatabase).

const SCHEDULE_FOLDER: String = "res://data/schedules/"
const ROOMS_FOLDER: String = "res://scenes/rooms/"
const HOT_RELOAD_INTERVAL: float = 1.0

# npc_id (String) → Array of block dicts (file order)
var _blocks: Dictionary = {}
# Scene basename ("hardware_store") → full path ("res://scenes/rooms/hardware_store.tscn")
var _scene_index: Dictionary = {}
# absolute .sched path → last-known modification time
var _file_mtimes: Dictionary = {}

var _hot_reload_timer: Timer = null

signal reloaded()


func _ready() -> void:
	_index_scenes()
	reload()
	if OS.is_debug_build():
		_setup_hot_reload()


# --- Scene index --------------------------------------------------------

func _index_scenes() -> void:
	_scene_index.clear()
	var dir: DirAccess = DirAccess.open(ROOMS_FOLDER)
	if dir == null:
		push_warning("ScheduleDatabase: rooms folder %s not found" % ROOMS_FOLDER)
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".tscn"):
			var basename: String = name.get_basename()
			_scene_index[basename] = ROOMS_FOLDER + name
		name = dir.get_next()
	dir.list_dir_end()


# --- Loading ------------------------------------------------------------

func reload() -> void:
	_blocks.clear()
	_file_mtimes.clear()

	var dir: DirAccess = DirAccess.open(SCHEDULE_FOLDER)
	if dir == null:
		push_warning("ScheduleDatabase: folder %s not found" % SCHEDULE_FOLDER)
		return

	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".sched"):
			_load_file(SCHEDULE_FOLDER + name)
		name = dir.get_next()
	dir.list_dir_end()

	print("[ScheduleDatabase] loaded %d NPC schedule file(s)" % _blocks.size())
	reloaded.emit()


func _load_file(path: String) -> void:
	var npc_id: String = path.get_file().get_basename()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("ScheduleDatabase: failed to open %s" % path)
		return
	var text: String = file.get_as_text()
	file.close()

	_file_mtimes[path] = FileAccess.get_modified_time(path)

	var result: Dictionary = ScheduleParser.parse(text, path)
	for err in result["errors"]:
		push_warning("[%s] %s" % [npc_id, err])

	# Resolve scene basenames to full paths inside every entry.
	for block in result["blocks"]:
		for minute in block["entries"]:
			var entry: Dictionary = block["entries"][minute]
			var basename: String = entry.get("scene_path", "")
			if _scene_index.has(basename):
				entry["scene_path"] = _scene_index[basename]
			else:
				push_warning("[%s] unknown scene '%s' (block at line %d)" % [
					npc_id, basename, block["source_line"],
				])

	_blocks[npc_id] = result["blocks"]


# --- Hot reload ---------------------------------------------------------

func _setup_hot_reload() -> void:
	_hot_reload_timer = Timer.new()
	_hot_reload_timer.wait_time = HOT_RELOAD_INTERVAL
	_hot_reload_timer.timeout.connect(_check_for_changes)
	add_child(_hot_reload_timer)
	_hot_reload_timer.start()
	print("[ScheduleDatabase] hot-reload enabled (debug build)")


func _check_for_changes() -> void:
	var changed: bool = false
	for path in _file_mtimes.keys():
		var current: int = FileAccess.get_modified_time(path)
		if current != int(_file_mtimes[path]):
			print("[ScheduleDatabase] %s changed, re-parsing" % path.get_file())
			_load_file(path)
			changed = true
	if changed:
		reloaded.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F6:
			print("[ScheduleDatabase] manual reload (F6)")
			reload()


# --- Lookup -------------------------------------------------------------

# Returns a fresh Schedule wrapping the active block's entries, or null
# if no block matches.
func get_active_schedule(npc_id: String, context: Dictionary) -> Schedule:
	if not _blocks.has(npc_id):
		return null
	var current_tags: Dictionary = _build_current_tags(npc_id, context)

	var best: Dictionary = {}
	var best_specificity: int = -2
	var best_index: int = -1

	var blocks: Array = _blocks[npc_id]
	for i in range(blocks.size()):
		var block: Dictionary = blocks[i]
		if not _block_matches(block, current_tags, npc_id, context):
			continue
		var s: int = block["specificity"]
		if s > best_specificity or (s == best_specificity and i > best_index):
			best = block
			best_specificity = s
			best_index = i

	if best.is_empty():
		return null
	var sch := Schedule.new()
	sch.entries = best["entries"]
	return sch


func has_npc(npc_id: String) -> bool:
	return _blocks.has(npc_id)


# --- Internals (mirror DialogueDatabase) --------------------------------

func _build_current_tags(npc_id: String, context: Dictionary) -> Dictionary:
	var tags: Dictionary = {}
	if context.has("weekday") and context["weekday"] != null:
		tags[String(context["weekday"])] = true
	var dow: int = TimeSystem.day_of_week()
	if dow >= 5:
		tags["weekend"] = true
	else:
		tags["weekday"] = true
	for f in RelationshipSystem.get_npc_flags(npc_id):
		tags[f] = true
	for f in RelationshipSystem.get_global_flags():
		tags[f] = true
	return tags


func _block_matches(block: Dictionary, current_tags: Dictionary, npc_id: String, context: Dictionary) -> bool:
	for tag in block["tags"]:
		if not current_tags.has(tag):
			return false
	for p in block["preconditions"]:
		if not _eval_precondition(p, npc_id, context):
			return false
	return true


func _eval_precondition(p: Dictionary, npc_id: String, context: Dictionary) -> bool:
	match p["kind"]:
		"compare":
			var lhs_val = _resolve_stat(p["lhs"], npc_id, context)
			return _compare(lhs_val, p["op"], p["rhs"])
		"flag":
			var has: bool = _check_flag(p["name"], npc_id, context)
			return (not has) if p["negated"] else has
		"event_done":
			return RelationshipSystem.is_event_done(p["event"])
		"has_item":
			return _player_has_item(p["item"])
	return false


func _resolve_stat(name: String, npc_id: String, context: Dictionary):
	match name:
		"affinity":
			return RelationshipSystem.get_affinity(npc_id)
		"trust":
			return RelationshipSystem.get_trust(npc_id)
		"day":
			return TimeSystem.day_index() + 1
		"dow":
			return TimeSystem.day_of_week()
	if context.has(name):
		return context[name]
	return 0


func _compare(lhs, op: String, rhs) -> bool:
	match op:
		">":  return lhs > rhs
		">=": return lhs >= rhs
		"<":  return lhs < rhs
		"<=": return lhs <= rhs
		"==": return lhs == rhs
		"!=": return lhs != rhs
	return false


func _check_flag(name: String, npc_id: String, context: Dictionary) -> bool:
	if name == "knows":
		return RelationshipSystem.get_knows(npc_id)
	if RelationshipSystem.get_npc_flag(npc_id, name):
		return true
	if RelationshipSystem.get_global_flag(name):
		return true
	if context.has(name) and typeof(context[name]) == TYPE_BOOL:
		return context[name]
	return false


func _player_has_item(item_id: String) -> bool:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	var inv = player.get("inventory")
	if inv == null:
		return false
	if inv.has_method("has_item_id"):
		return inv.has_item_id(StringName(item_id))
	return false
