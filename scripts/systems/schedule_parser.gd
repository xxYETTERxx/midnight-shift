class_name ScheduleParser
extends RefCounted

# Parses a .sched text file into an array of schedule block dictionaries.
# Each block is one variant of an NPC's daily schedule, gated by tags and
# preconditions just like a dialogue entry. ScheduleDatabase picks the
# highest-specificity matching block per context.
#
# Block shape:
# {
#   "tags": Array[String],          # ["mon"], or [] for default/*
#   "specificity": int,             # tags.size(); -1 for "default"
#   "preconditions": Array[Dict],   # same shape as DialogueParser's
#   "entries": Dictionary,          # minute_of_day → entry dict
#   "source_line": int,
#   "source_path": String,
# }
#
# Body line shapes inside a block:
#   HH:MM stand SCENE MARKER [FACING]
#   HH:MM transit SCENE START->END


static func parse(text: String, source_path: String = "") -> Dictionary:
	var lines: PackedStringArray = text.split("\n")
	var blocks: Array = []
	var errors: Array = []
	var i: int = 0

	while i < lines.size():
		var raw: String = lines[i]
		var stripped: String = _strip_comment(raw).strip_edges()
		if stripped.is_empty():
			i += 1
			continue
		var indent: int = _leading_spaces(_strip_comment(raw))
		if indent > 0:
			errors.append("Line %d: indented line with no preceding key" % (i + 1))
			i += 1
			continue
		var block_result: Dictionary = _parse_block(lines, i, source_path)
		if block_result.has("block"):
			blocks.append(block_result["block"])
		if block_result.has("errors"):
			errors.append_array(block_result["errors"])
		i = block_result["next_line"]

	return {"blocks": blocks, "errors": errors}


static func _parse_block(lines: PackedStringArray, start: int, source_path: String) -> Dictionary:
	var key_line: String = _strip_comment(lines[start]).strip_edges()
	var key_parsed: Dictionary = _parse_key_line(key_line)
	var block: Dictionary = {
		"tags": key_parsed["tags"],
		"specificity": key_parsed["specificity"],
		"preconditions": key_parsed["preconditions"],
		"entries": {},
		"source_line": start + 1,
		"source_path": source_path,
	}
	var body_result: Dictionary = _parse_body(lines, start + 1)
	block["entries"] = body_result["entries"]
	return {
		"block": block,
		"next_line": body_result["next_line"],
		"errors": body_result.get("errors", []),
	}


static func _parse_key_line(line: String) -> Dictionary:
	var key_part: String = line
	var cond_part: String = ""
	var pipe_idx: int = line.find("|")
	if pipe_idx >= 0:
		key_part = line.substr(0, pipe_idx).strip_edges()
		cond_part = line.substr(pipe_idx + 1).strip_edges()

	var tags: Array = []
	var specificity: int = 0

	if key_part == "default":
		specificity = -1
	elif key_part == "*":
		specificity = 0
	else:
		for p in key_part.split("."):
			var t: String = p.strip_edges()
			if not t.is_empty():
				tags.append(t)
		specificity = tags.size()

	var preconds: Array = []
	if not cond_part.is_empty():
		for c in cond_part.split(";"):
			var c_str: String = c.strip_edges()
			if c_str.is_empty():
				continue
			var p: Dictionary = _parse_precondition(c_str)
			if not p.is_empty():
				preconds.append(p)

	return {
		"tags": tags,
		"specificity": specificity,
		"preconditions": preconds,
	}


# Mirrors DialogueParser._parse_precondition — same syntax for the same job.
static func _parse_precondition(s: String) -> Dictionary:
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
				"rhs": _coerce_value(rhs_str),
			}
	var parts: PackedStringArray = s.split(" ", false)
	if parts.size() == 2:
		if parts[0] == "event_done":
			return {"kind": "event_done", "event": parts[1]}
		if parts[0] == "has_item":
			return {"kind": "has_item", "item": parts[1]}
	if s.begins_with("!"):
		return {"kind": "flag", "name": s.substr(1).strip_edges(), "negated": true}
	return {"kind": "flag", "name": s, "negated": false}


static func _coerce_value(s: String):
	if s.is_valid_int():
		return s.to_int()
	if s.is_valid_float():
		return s.to_float()
	if s == "true":
		return true
	if s == "false":
		return false
	return s


# --- Body parsing ---

static func _parse_body(lines: PackedStringArray, start: int) -> Dictionary:
	var entries: Dictionary = {}
	var errors: Array = []
	var i: int = start
	var body_indent: int = -1

	while i < lines.size():
		var raw: String = lines[i]
		var stripped: String = _strip_comment(raw).strip_edges()
		if stripped.is_empty():
			i += 1
			continue
		var indent: int = _leading_spaces(_strip_comment(raw))
		if indent == 0:
			break
		if body_indent == -1:
			body_indent = indent
		if indent < body_indent:
			break

		var parsed: Dictionary = _parse_schedule_line(stripped)
		if parsed.has("error"):
			errors.append("Line %d: %s" % [i + 1, parsed["error"]])
		else:
			entries[parsed["minute"]] = parsed["entry"]
		i += 1

	return {"entries": entries, "next_line": i, "errors": errors}


static func _parse_schedule_line(line: String) -> Dictionary:
	var parts: PackedStringArray = line.split(" ", false)
	if parts.size() < 4:
		return {"error": "Too few tokens (need: TIME ACTIVITY SCENE ARGS)"}

	var minute: int = _parse_time(parts[0])
	if minute < 0:
		return {"error": "Invalid time '%s' — expected HH:MM" % parts[0]}

	var activity: String = parts[1]
	var scene: String = parts[2]

	match activity:
		"stand":
			var entry: Dictionary = {
				"activity": "stand",
				"scene_path": scene,
				"marker": StringName(parts[3]),
			}
			if parts.size() >= 5:
				entry["facing"] = parts[4]
			return {"minute": minute, "entry": entry}
		"transit":
			var route_str: String = parts[3]
			var arrow_idx: int = route_str.find("->")
			if arrow_idx < 0:
				return {"error": "Transit route must be START->END"}
			var start_marker: String = route_str.substr(0, arrow_idx).strip_edges()
			var end_marker: String = route_str.substr(arrow_idx + 2).strip_edges()
			return {"minute": minute, "entry": {
				"activity": "transit",
				"scene_path": scene,
				"route": [StringName(start_marker), StringName(end_marker)],
			}}
		_:
			return {"error": "Unknown activity '%s' (expected stand/transit)" % activity}


# "HH:MM" → minute-of-day, or -1 on parse failure.
static func _parse_time(s: String) -> int:
	var parts: PackedStringArray = s.split(":")
	if parts.size() != 2:
		return -1
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return -1
	var h: int = parts[0].to_int()
	var m: int = parts[1].to_int()
	if h < 0 or h > 23 or m < 0 or m > 59:
		return -1
	return h * 60 + m


# --- Helpers (mirror DialogueParser) ---

static func _strip_comment(line: String) -> String:
	var idx: int = line.find("#")
	if idx < 0:
		return line
	return line.substr(0, idx)


static func _leading_spaces(line: String) -> int:
	var n: int = 0
	for ch in line:
		if ch == " ":
			n += 1
		elif ch == "\t":
			n += 4
		else:
			break
	return n
