extends Node

# RelationshipSystem autoload.
#
# Tracks per-NPC and global relationship/world state, plus a per-NPC dialogue
# event queue (the push-stack the design doc mentions).
#
# Per-NPC state:
#   affinity: int [-100, 100]   — how much they like the player
#   trust:    int [0, 100]      — willingness to bet on the player
#   knows:    bool              — aware of the player's criminal activity
#   flags:    set of strings    — arbitrary per-NPC booleans (e.g. "first_meeting")
#   queue:    Array of strings  — pending event names to deliver
#
# Global state:
#   global_flags: set of strings   — world-level flags
#   events_done:  set of strings   — names of completed dialogue events

# npc_id (String) → { affinity, trust, knows, flags, queue }
var _npcs: Dictionary = {}
# flag_name → true (presence = set)
var _global_flags: Dictionary = {}
# event_name → true
var _events_done: Dictionary = {}
# npc_id (String) -> day_index (int) on which they last received a gift
var _last_gift_day: Dictionary = {}

signal affinity_changed(npc_id: String, new_value: int)
signal trust_changed(npc_id: String, new_value: int)
signal knows_changed(npc_id: String, new_value: bool)
signal npc_flag_changed(npc_id: String, flag: String, value: bool)
signal global_flag_changed(flag: String, value: bool)
signal dialogue_queue_changed(npc_id: String)


func _ready() -> void:
	SaveSystem.register_savable("relationships", self)


# --- Internal NPC bookkeeping -----------------------------------------

func _ensure_npc(npc_id: String) -> Dictionary:
	if not _npcs.has(npc_id):
		_npcs[npc_id] = {
			"affinity": 0,
			"trust": 0,
			"knows": false,
			"flags": {},
			"queue": [],
		}
	return _npcs[npc_id]


# --- Affinity ---------------------------------------------------------

func get_affinity(npc_id: String) -> int:
	return int(_ensure_npc(npc_id)["affinity"])

func set_affinity(npc_id: String, value: int) -> void:
	var n: Dictionary = _ensure_npc(npc_id)
	var clamped: int = clampi(value, -100, 100)
	if int(n["affinity"]) == clamped:
		return
	n["affinity"] = clamped
	affinity_changed.emit(npc_id, clamped)

func add_affinity(npc_id: String, delta: int) -> void:
	set_affinity(npc_id, get_affinity(npc_id) + delta)


# --- Trust ------------------------------------------------------------

func get_trust(npc_id: String) -> int:
	return int(_ensure_npc(npc_id)["trust"])

func set_trust(npc_id: String, value: int) -> void:
	var n: Dictionary = _ensure_npc(npc_id)
	var clamped: int = clampi(value, 0, 100)
	if int(n["trust"]) == clamped:
		return
	n["trust"] = clamped
	trust_changed.emit(npc_id, clamped)

func add_trust(npc_id: String, delta: int) -> void:
	set_trust(npc_id, get_trust(npc_id) + delta)


# --- Knows ------------------------------------------------------------

func get_knows(npc_id: String) -> bool:
	return bool(_ensure_npc(npc_id)["knows"])

func set_knows(npc_id: String, value: bool) -> void:
	var n: Dictionary = _ensure_npc(npc_id)
	if bool(n["knows"]) == value:
		return
	n["knows"] = value
	knows_changed.emit(npc_id, value)


# --- Per-NPC flags ----------------------------------------------------

func get_npc_flag(npc_id: String, flag: String) -> bool:
	return _ensure_npc(npc_id)["flags"].has(flag)

func set_npc_flag(npc_id: String, flag: String, value: bool = true) -> void:
	var n: Dictionary = _ensure_npc(npc_id)
	var flags: Dictionary = n["flags"]
	var was: bool = flags.has(flag)
	if value:
		flags[flag] = true
	else:
		flags.erase(flag)
	if was != value:
		npc_flag_changed.emit(npc_id, flag, value)

func get_npc_flags(npc_id: String) -> Array:
	return _ensure_npc(npc_id)["flags"].keys()


# --- Global flags -----------------------------------------------------

func get_global_flag(flag: String) -> bool:
	return _global_flags.has(flag)

func set_global_flag(flag: String, value: bool = true) -> void:
	var was: bool = _global_flags.has(flag)
	if value:
		_global_flags[flag] = true
	else:
		_global_flags.erase(flag)
	if was != value:
		global_flag_changed.emit(flag, value)

func get_global_flags() -> Array:
	return _global_flags.keys()


# --- Events -----------------------------------------------------------

func is_event_done(event_name: String) -> bool:
	return _events_done.has(event_name)

func mark_event_done(event_name: String) -> void:
	_events_done[event_name] = true

func mark_event_undone(event_name: String) -> void:
	_events_done.erase(event_name)

# --- Dialogue queue ---------------------------------------------------
# FIFO of event names. DialogueDatabase peeks/pops when looking up lines.

func push_dialogue(npc_id: String, event_name: String) -> void:
	_ensure_npc(npc_id)["queue"].append(event_name)
	dialogue_queue_changed.emit(npc_id)

func peek_dialogue(npc_id: String) -> String:
	var q: Array = _ensure_npc(npc_id)["queue"]
	if q.is_empty():
		return ""
	return String(q[0])

func pop_dialogue(npc_id: String) -> String:
	var q: Array = _ensure_npc(npc_id)["queue"]
	if q.is_empty():
		return ""
	var v: String = String(q.pop_front())
	dialogue_queue_changed.emit(npc_id)
	return v

func clear_queue(npc_id: String) -> void:
	var q: Array = _ensure_npc(npc_id)["queue"]
	if q.is_empty():
		return
	q.clear()
	dialogue_queue_changed.emit(npc_id)

func queue_size(npc_id: String) -> int:
	return _ensure_npc(npc_id)["queue"].size()

#-----Gifts----------------

func can_receive_gift(npc_id: String) -> bool:
	if not _last_gift_day.has(npc_id):
		return true
	return _last_gift_day[npc_id] != TimeSystem.day_index()


func record_gift(npc_id: String) -> void:
	_last_gift_day[npc_id] = TimeSystem.day_index()

# --- Apply effects helper ---------------------------------------------
# DialogueRuntime (4b) will call this when a response is selected; included
# here so the API is in one place.

func apply_effect(npc_id: String, effect: Dictionary) -> void:
	match effect.get("kind", ""):
		"stat_delta":
			match effect["stat"]:
				"affinity":
					add_affinity(npc_id, int(effect["delta"]))
				"trust":
					add_trust(npc_id, int(effect["delta"]))
				_:
					push_warning("RelationshipSystem: unknown stat '%s' in effect" % effect["stat"])
		"set_flag":
			# Heuristic: NPC-local first, but allow a "global:" prefix to opt in.
			var name: String = effect["name"]
			if name.begins_with("global:"):
				set_global_flag(name.substr(7), bool(effect["value"]))
			else:
				set_npc_flag(npc_id, name, bool(effect["value"]))
		_:
			push_warning("RelationshipSystem: unknown effect kind '%s'" % effect.get("kind", ""))


# --- Save / Load ------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"npcs": _npcs.duplicate(true),
		"global_flags": _global_flags.duplicate(true),
		"events_done": _events_done.duplicate(true),
		"last_day_gift": _last_gift_day.duplicate(true),
	}


func load_state(data: Dictionary) -> void:
	_npcs = data.get("npcs", {}).duplicate(true)
	_global_flags = data.get("global_flags", {}).duplicate(true)
	_events_done = data.get("events_done", {}).duplicate(true)
	_last_gift_day = data.get("last_day_gift", {}).duplicate(true)
