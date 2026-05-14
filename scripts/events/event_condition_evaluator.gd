class_name EventConditionEvaluator
extends RefCounted

# Parses + evaluates the precondition strings on an Event node.
# Syntax mirrors .dlg / .sched preconditions, with an events-only vocabulary
# (no per-npc context, so no `affinity` / `trust` / `knows`).
#
# Supported forms:
#   flag_name             — global flag is set
#   !flag_name            — global flag is NOT set
#   event_done X          — RelationshipSystem.is_event_done(X)
#   npc_in_scene X        — X's current schedule entry points at the current room
#   has_item X            — player carries item with id X (returns false until wired)
#   <stat> OP <int|str>   — compare. stat ∈ {day, dow, hour, room}. OP ∈ >,<,>=,<=,==,!=

static func all_pass(conditions: Array) -> bool:
	for s in conditions:
		var parsed: Dictionary = parse(String(s))
		if parsed.is_empty():
			push_warning("EventCondition: failed to parse '%s' — treating as false" % s)
			return false
		if not evaluate(parsed):
			return false
	return true


static func parse(s_raw: String) -> Dictionary:
	var s: String = s_raw.strip_edges()
	if s.is_empty():
		return {}

	for op in [">=", "<=", "==", "!=", ">", "<"]:
		var idx: int = s.find(op)
		if idx > 0:
			var lhs: String = s.substr(0, idx).strip_edges()
			var rhs_str: String = s.substr(idx + op.length()).strip_edges()
			return {
				"kind": "compare",
				"lhs": lhs,
				"op": op,
				"rhs": _coerce(rhs_str),
			}

	var parts: PackedStringArray = s.split(" ", false)
	if parts.size() == 2:
		match parts[0]:
			"event_done":   return {"kind": "event_done", "event": parts[1]}
			"npc_in_scene": return {"kind": "npc_in_scene", "npc": parts[1]}
			"has_item":     return {"kind": "has_item", "item": parts[1]}

	if s.begins_with("!"):
		return {"kind": "flag", "name": s.substr(1).strip_edges(), "negated": true}
	return {"kind": "flag", "name": s, "negated": false}


static func _coerce(s: String) -> Variant:
	if s.is_valid_int():
		return s.to_int()
	if s.length() >= 2 and s.begins_with("\"") and s.ends_with("\""):
		return s.substr(1, s.length() - 2)
	return s


static func evaluate(p: Dictionary) -> bool:
	match p["kind"]:
		"flag":
			var has: bool = RelationshipSystem.get_global_flag(p["name"])
			return (not has) if p["negated"] else has
		"event_done":
			return RelationshipSystem.is_event_done(p["event"])
		"npc_in_scene":
			if RoomManager.current_room == null:
				return false
			return NPCDirector.is_npc_in_scene(StringName(p["npc"]),
				RoomManager.current_room.scene_file_path)
		"has_item":
			return false
		"compare":
			var lhs: Variant = _resolve_lhs(p["lhs"])
			return _cmp(lhs, p["op"], p["rhs"])
	return false


static func _resolve_lhs(name: String) -> Variant:
	match name:
		"day":  return TimeSystem.day_index() + 1
		"dow":  return TimeSystem.day_of_week()
		"hour": return TimeSystem.current_hour()
		"room":
			if RoomManager.current_room == null:
				return ""
			return RoomManager.current_room.scene_file_path.get_file().get_basename()
	return 0


static func _cmp(lhs: Variant, op: String, rhs: Variant) -> bool:
	match op:
		">":  return lhs > rhs
		">=": return lhs >= rhs
		"<":  return lhs < rhs
		"<=": return lhs <= rhs
		"==": return lhs == rhs
		"!=": return lhs != rhs
	return false
