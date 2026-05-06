extends Node

# DialogueDatabase autoload.
#
# Owns parsed .dlg content for every NPC. Provides the key-lookup that picks
# which dialogue line an NPC says given the current world context.
#
# Hot-reload: in debug builds, polls .dlg file modification times once per
# second and re-parses any that have changed. F5 forces a full reload
# (which also catches new or deleted files).

const DIALOGUE_FOLDER: String = "res://data/dialogue/"
const HOT_RELOAD_INTERVAL: float = 1.0

# npc_id (String) → Array of entry dicts (file order)
var _entries: Dictionary = {}
# npc_id → { event_name: entry_dict }
var _events: Dictionary = {}
# absolute path → last-known modification time (for hot-reload polling)
var _file_mtimes: Dictionary = {}

var _hot_reload_timer: Timer = null

signal reloaded()


func _ready() -> void:
	reload()
	if OS.is_debug_build():
		_setup_hot_reload()
	if _SELF_TEST_ON_READY:
		call_deferred("_print_self_test")


# --- Loading ---

func reload() -> void:
	_entries.clear()
	_events.clear()
	_file_mtimes.clear()

	var dir: DirAccess = DirAccess.open(DIALOGUE_FOLDER)
	if dir == null:
		push_warning("DialogueDatabase: folder %s not found" % DIALOGUE_FOLDER)
		return

	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".dlg"):
			_load_file(DIALOGUE_FOLDER + name)
		name = dir.get_next()
	dir.list_dir_end()

	print("[DialogueDatabase] loaded %d NPC dialogue file(s)" % _entries.size())
	reloaded.emit()


func _load_file(path: String) -> void:
	var npc_id: String = path.get_file().get_basename()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DialogueDatabase: failed to open %s" % path)
		return
	var text: String = file.get_as_text()
	file.close()

	_file_mtimes[path] = FileAccess.get_modified_time(path)

	var result: Dictionary = DialogueParser.parse(text, path)

	for err in result["errors"]:
		push_warning("[%s] %s" % [npc_id, err])

	var regular: Array = []
	var events: Dictionary = {}
	for entry in result["entries"]:
		if entry["is_event"]:
			events[entry["event_name"]] = entry
		else:
			regular.append(entry)

	_entries[npc_id] = regular
	_events[npc_id] = events


# --- Hot reload ---

func _setup_hot_reload() -> void:
	_hot_reload_timer = Timer.new()
	_hot_reload_timer.wait_time = HOT_RELOAD_INTERVAL
	_hot_reload_timer.timeout.connect(_check_for_changes)
	add_child(_hot_reload_timer)
	_hot_reload_timer.start()
	print("[DialogueDatabase] hot-reload enabled (debug build)")


func _check_for_changes() -> void:
	# Walk a copy of keys so we don't mutate while iterating.
	for path in _file_mtimes.keys():
		var current: int = FileAccess.get_modified_time(path)
		if current != int(_file_mtimes[path]):
			print("[DialogueDatabase] %s changed, re-parsing" % path.get_file())
			_reload_one(path)


# Reload a single file in place — doesn't touch other NPCs' data, doesn't
# pick up newly-added files. Use reload() (F5) for that.
func _reload_one(path: String) -> void:
	var npc_id: String = path.get_file().get_basename()
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DialogueDatabase: failed to reopen %s" % path)
		return
	var text: String = file.get_as_text()
	file.close()

	_file_mtimes[path] = FileAccess.get_modified_time(path)

	var result: Dictionary = DialogueParser.parse(text, path)
	for err in result["errors"]:
		push_warning("[%s] %s" % [npc_id, err])

	var regular: Array = []
	var events: Dictionary = {}
	for entry in result["entries"]:
		if entry["is_event"]:
			events[entry["event_name"]] = entry
		else:
			regular.append(entry)

	_entries[npc_id] = regular
	_events[npc_id] = events
	reloaded.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			print("[DialogueDatabase] manual reload (F5)")
			reload()


# --- Lookup ---

func get_line(npc_id: String, context: Dictionary) -> Dictionary:
	# 1) Queued event takes priority — fire it and pop.
	var queued: String = RelationshipSystem.peek_dialogue(npc_id)
	if queued != "":
		var npc_events: Dictionary = _events.get(npc_id, {})
		if npc_events.has(queued):
			RelationshipSystem.pop_dialogue(npc_id)
			return npc_events[queued]
		else:
			push_warning("DialogueDatabase: queued event '%s' for NPC '%s' has no matching entry; dropping" % [queued, npc_id])
			RelationshipSystem.pop_dialogue(npc_id)

	if not _entries.has(npc_id):
		push_warning("DialogueDatabase: no entries loaded for NPC '%s'" % npc_id)
		return {}

	var entries: Array = _entries[npc_id]
	var current_tags: Dictionary = _build_current_tags(npc_id, context)

	var best: Dictionary = {}
	var best_specificity: int = -2
	var best_index: int = -1

	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		if not _entry_matches(entry, current_tags, npc_id, context):
			continue
		var s: int = entry["specificity"]
		if s > best_specificity or (s == best_specificity and i > best_index):
			best = entry
			best_specificity = s
			best_index = i

	return best


func get_event(npc_id: String, event_name: String) -> Dictionary:
	var npc_events: Dictionary = _events.get(npc_id, {})
	if not npc_events.has(event_name):
		return {}
	return npc_events[event_name]


func has_npc(npc_id: String) -> bool:
	return _entries.has(npc_id)


# --- Internals ---

func _build_current_tags(npc_id: String, context: Dictionary) -> Dictionary:
	var tags: Dictionary = {}

	for key in ["weekday", "timeofday", "weather", "location"]:
		if context.has(key) and context[key] != null:
			tags[String(context[key])] = true

	if RelationshipSystem.get_knows(npc_id):
		tags["knows"] = true
	else:
		tags["!knows"] = true

	for f in RelationshipSystem.get_npc_flags(npc_id):
		tags[f] = true
	for f in RelationshipSystem.get_global_flags():
		tags[f] = true

	for k in context.keys():
		if k in ["weekday", "timeofday", "weather", "location"]:
			continue
		if typeof(context[k]) == TYPE_BOOL and context[k]:
			tags[String(k)] = true

	return tags


func _entry_matches(entry: Dictionary, current_tags: Dictionary, npc_id: String, context: Dictionary) -> bool:
	if entry.get("is_event", false):
		return false

	for tag in entry["tags"]:
		if not current_tags.has(tag):
			return false

	for p in entry["preconditions"]:
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
		"hour":
			return TimeSystem.current_hour()
	if context.has(name):
		return context[name]
	push_warning("DialogueDatabase: unknown stat '%s', defaulting to 0" % name)
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


# --- Debug / self-test ---

const _SELF_TEST_ON_READY: bool = true

func _print_self_test() -> void:
	print("\n=== DialogueDatabase self-test ===")
	var test_npc: String = "mira"
	if not _entries.has(test_npc):
		print("  no entries for '%s' — drop sample mira.dlg into res://data/dialogue/" % test_npc)
		print("=== self-test done ===\n")
		return

	var pre_aff: int = RelationshipSystem.get_affinity(test_npc)
	var pre_kn: bool = RelationshipSystem.get_knows(test_npc)

	var scenarios: Array = [
		{"label": "Mon afternoon, anywhere", "ctx": {"weekday": "mon", "timeofday": "afternoon"}},
		{"label": "Fri evening at bodega",   "ctx": {"weekday": "fri", "timeofday": "evening", "location": "bodega"}},
		{"label": "Tue at apartment",        "ctx": {"weekday": "tue", "location": "apartment"}},
		{"label": "Sat (no special key)",    "ctx": {"weekday": "sat"}},
	]
	for s in scenarios:
		_print_match(test_npc, s["label"], s["ctx"])

	print("  --- bumping affinity to 50 ---")
	RelationshipSystem.set_affinity(test_npc, 50)
	_print_match(test_npc, "Fri w/ affinity 50", {"weekday": "fri"})

	print("  --- setting knows=true ---")
	RelationshipSystem.set_knows(test_npc, true)
	_print_match(test_npc, "Mon w/ knows=true", {"weekday": "mon"})

	print("  --- pushing event 'bodega_intro' ---")
	RelationshipSystem.push_dialogue(test_npc, "bodega_intro")
	_print_match(test_npc, "queued event takes over", {"weekday": "mon"})

	RelationshipSystem.set_affinity(test_npc, pre_aff)
	RelationshipSystem.set_knows(test_npc, pre_kn)
	RelationshipSystem.clear_queue(test_npc)
	print("=== self-test done ===\n")


func _print_match(npc_id: String, label: String, ctx: Dictionary) -> void:
	var e: Dictionary = get_line(npc_id, ctx)
	if e.is_empty():
		print("  [%s]  →  (no match)" % label)
		return
	var key_str: String
	if e.get("is_event", false):
		key_str = "event:%s" % e["event_name"]
	elif e["tags"].is_empty():
		key_str = "default" if e["specificity"] == -1 else "*"
	else:
		key_str = ".".join(e["tags"])
	print("  [%s]  →  %s   (line %d, specificity %d)" %
		[label, key_str, e["source_line"], e["specificity"]])
	for seg in e["body"]:
		match seg["kind"]:
			"text":
				var portrait_marker: String = ("$" + seg["portrait"] + " ") if seg["portrait"] != "" else ""
				print("      %s%s" % [portrait_marker, seg["text"].replace("\n", " | ")])
			"page_break":
				print("      [$b]")
			"question":
				print("      [$q with %d responses]" % seg["responses"].size())
				for r in seg["responses"]:
					print("        --> \"%s\"" % r["text"])
