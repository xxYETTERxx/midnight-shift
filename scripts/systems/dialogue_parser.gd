class_name DialogueParser
extends RefCounted


const WALLET_POOLS: Array = ["cash", "clean"]
# Parses a .dlg text file into an array of entry dictionaries.
#
# An "entry" is the AST output for one block of dialogue. Returned dicts are
# pure data (no class instances) so they're trivial to serialize, compare,
# and reload at runtime.
#
# Entry shape:
# {
#   "tags": Array[String],          # ["bodega", "mon"], or [] for default/*
#   "specificity": int,             # tags.size() normally; -1 for "default"
#   "preconditions": Array[Dict],   # see _parse_precondition
#   "is_event": bool,               # true if this is an event:NAME entry
#   "event_name": String,
#   "body": Array[Dict],            # see segment shapes below
#   "source_line": int,             # 1-indexed for error messages
#   "source_path": String,
# }
#
# Body segment shapes:
#   { "kind": "text", "portrait": String, "text": String }
#   { "kind": "page_break" }
#   { "kind": "question", "responses": Array[Dict] }
#
# Response shape:
#   {
#     "text": String,                # what the player sees
#     "preconditions": Array[Dict],
#     "effects": Array[Dict],
#     "follow_up": Array[Dict],      # body segments shown after picking
#   }
#
# Precondition shapes:
#   { "kind": "compare", "lhs": String, "op": String, "rhs": Variant }
#   { "kind": "flag", "name": String, "negated": bool }
#   { "kind": "event_done", "event": String }
#   { "kind": "has_item", "item": String }
#
# Effect shapes:
#   { "kind": "stat_delta",   "stat": String,  "delta": int }   # affinity +5d
#   { "kind": "set_flag",     "name": String,  "value": bool }  # set X / clear X
#   { "kind": "wallet_delta", "pool": String,  "delta": int }   # cash +50 / cash -20
#   { "kind": "item_delta",   "item": String,  "delta": int }   # give X / take X N


# Parses an entire .dlg file. Returns:
#   { "entries": Array, "errors": Array[String] }
static func parse(text: String, source_path: String = "") -> Dictionary:
	var lines: PackedStringArray = text.split("\n")
	var entries: Array = []
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
		# Top-level: this is a key line
		var entry_result: Dictionary = _parse_entry(lines, i, source_path)
		if entry_result.has("entry"):
			entries.append(entry_result["entry"])
		if entry_result.has("errors"):
			errors.append_array(entry_result["errors"])
		i = entry_result["next_line"]

	return {"entries": entries, "errors": errors}


# --- Entry-level ---

static func _parse_entry(lines: PackedStringArray, start: int, source_path: String) -> Dictionary:
	var key_line: String = _strip_comment(lines[start]).strip_edges()
	var key_parsed: Dictionary = _parse_key_line(key_line)
	var entry: Dictionary = {
		"tags": key_parsed["tags"],
		"specificity": key_parsed["specificity"],
		"preconditions": key_parsed["preconditions"],
		"is_event": key_parsed["is_event"],
		"event_name": key_parsed["event_name"],
		"body": [],
		"source_line": start + 1,
		"source_path": source_path,
	}
	var body_result: Dictionary = _parse_body(lines, start + 1, 0)
	entry["body"] = body_result["body"]
	return {
		"entry": entry,
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
	var is_event: bool = false
	var event_name: String = ""

	if key_part == "default":
		specificity = -1
	elif key_part == "*":
		specificity = 0
	elif key_part.begins_with("event:"):
		is_event = true
		event_name = key_part.substr(6).strip_edges()
		specificity = 0
	else:
		var parts: PackedStringArray = key_part.split(".")
		for p in parts:
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
		"is_event": is_event,
		"event_name": event_name,
	}


# --- Precondition / effect parsing ---

static func _parse_precondition(s: String) -> Dictionary:
	if s.is_empty():
		return {}

	# Comparison ops, longest-first so >= isn't matched as >
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

	# Two-word forms: "event_done X", "has_item X"
	var parts: PackedStringArray = s.split(" ", false)
	if parts.size() == 2:
		if parts[0] == "event_done":
			return {"kind": "event_done", "event": parts[1]}
		if parts[0] == "has_item":
			return {"kind": "has_item", "item": parts[1]}

	# Flag check (bare name or !name)
	if s.begins_with("!"):
		return {"kind": "flag", "name": s.substr(1).strip_edges(), "negated": true}
	return {"kind": "flag", "name": s, "negated": false}


static func _try_parse_effect(s: String) -> Dictionary:
	var parts: PackedStringArray = s.split(" ", false)
	var n: int = parts.size()

	if n == 2:
		if parts[0] == "set":
			return {"kind": "set_flag", "name": parts[1], "value": true}
		if parts[0] == "clear":
			return {"kind": "set_flag", "name": parts[1], "value": false}
		if parts[0] == "give":
			return {"kind": "item_delta", "item": parts[1], "delta": 1}
		if parts[0] == "take":
			return {"kind": "item_delta", "item": parts[1], "delta": -1}
		# stat/pool +N or -N
		var amount_str: String = parts[1]
		if amount_str.length() >= 2 and (amount_str[0] == "+" or amount_str[0] == "-"):
			var num_str: String = amount_str.substr(1)
			if num_str.is_valid_int():
				var amt: int = num_str.to_int()
				if amount_str[0] == "-":
					amt = -amt
				if parts[0] in WALLET_POOLS:
					return {"kind": "wallet_delta", "pool": parts[0], "delta": amt}
				return {"kind": "stat_delta", "stat": parts[0], "delta": amt}

	elif n == 3:
		# give ITEM N / take ITEM N
		if parts[0] == "give" or parts[0] == "take":
			var count_str: String = parts[2]
			if count_str.is_valid_int():
				var count: int = count_str.to_int()
				if count < 0:
					return {}  # malformed; let it fall through as a precondition
				if parts[0] == "take":
					count = -count
				return {"kind": "item_delta", "item": parts[1], "delta": count}

	return {}


static func _coerce_value(s: String):
	if s.is_valid_int():
		return s.to_int()
	if s.is_valid_float():
		return s.to_float()
	if s == "true":
		return true
	if s == "false":
		return false
	return s  # bare string


# --- Body parsing ---

# Parses indented body lines following an entry key (or response).
# parent_indent: body lines must be STRICTLY greater than this.
# Returns { "body": Array, "next_line": int, "errors": Array }
static func _parse_body(lines: PackedStringArray, start: int, parent_indent: int) -> Dictionary:
	var body: Array = []
	var errors: Array = []
	var i: int = start
	var body_indent: int = -1
	var current_text: Dictionary = {}

	while i < lines.size():
		var raw: String = lines[i]
		var stripped: String = _strip_comment(raw).strip_edges()

		if stripped.is_empty():
			i += 1
			continue

		var indent: int = _leading_spaces(_strip_comment(raw))

		if indent <= parent_indent:
			break

		if body_indent == -1:
			body_indent = indent

		if indent < body_indent:
			# Dedent within body — terminate
			break

		# Markers
		if stripped == "$b":
			_flush_text(body, current_text)
			current_text = {}
			body.append({"kind": "page_break"})
			i += 1
			continue

		if stripped == "$q":
			_flush_text(body, current_text)
			current_text = {}
			var q_result: Dictionary = _parse_question(lines, i + 1, body_indent)
			body.append({"kind": "question", "responses": q_result["responses"]})
			errors.append_array(q_result.get("errors", []))
			i = q_result["next_line"]
			continue

		if stripped == "$r":
			errors.append("Line %d: $r outside a $q block" % (i + 1))
			i += 1
			continue

		# Text line — may have a portrait code prefix
		var portrait: String = ""
		var text: String = stripped
		if stripped.begins_with("$"):
			# Find the first space to extract the portrait code
			var sp: int = stripped.find(" ")
			var code: String
			if sp > 0:
				code = stripped.substr(1, sp - 1)
				text = stripped.substr(sp + 1).strip_edges()
			else:
				code = stripped.substr(1)
				text = ""
			# A bare $X with nothing after is treated as a portrait switch with empty text;
			# subsequent lines without codes will accumulate into it.
			portrait = code

		if not portrait.is_empty():
			# Portrait code present — start a new text segment.
			_flush_text(body, current_text)
			current_text = {"kind": "text", "portrait": portrait, "text": text}
		else:
			# Continuation — append to current segment, or start a new portrait-less one.
			if current_text.is_empty():
				current_text = {"kind": "text", "portrait": "", "text": text}
			else:
				if current_text["text"].is_empty():
					current_text["text"] = text
				else:
					current_text["text"] += "\n" + text

		i += 1

	_flush_text(body, current_text)
	return {"body": body, "next_line": i, "errors": errors}


static func _flush_text(body: Array, segment: Dictionary) -> void:
	if segment.is_empty():
		return
	# Drop entirely-empty text segments (can happen if a portrait line had no
	# following text, e.g., `$h` on its own line with no continuation).
	if segment.get("kind") == "text" and segment.get("text", "") == "" and segment.get("portrait", "") == "":
		return
	body.append(segment)


# --- Question / response parsing ---

# q_indent: the indent level of the $q line (and its responses, and $r).
# Anything strictly less than q_indent ends the block.
static func _parse_question(lines: PackedStringArray, start: int, q_indent: int) -> Dictionary:
	var responses: Array = []
	var errors: Array = []
	var i: int = start

	while i < lines.size():
		var raw: String = lines[i]
		var stripped: String = _strip_comment(raw).strip_edges()

		if stripped.is_empty():
			i += 1
			continue

		var indent: int = _leading_spaces(_strip_comment(raw))

		if indent < q_indent:
			errors.append("Question block ended without $r before line %d" % (i + 1))
			return {"responses": responses, "next_line": i, "errors": errors}

		if stripped == "$r":
			return {"responses": responses, "next_line": i + 1, "errors": errors}

		if stripped.begins_with("-->"):
			var resp_result: Dictionary = _parse_response(lines, i, q_indent)
			responses.append(resp_result["response"])
			errors.append_array(resp_result.get("errors", []))
			i = resp_result["next_line"]
			continue

		# Anything else inside a $q block is a writer error.
		errors.append("Line %d: unexpected content inside $q block (expected --> or $r)" % (i + 1))
		i += 1

	errors.append("Question block reached end of file without $r")
	return {"responses": responses, "next_line": i, "errors": errors}


static func _parse_response(lines: PackedStringArray, start: int, response_indent: int) -> Dictionary:
	var line: String = _strip_comment(lines[start]).strip_edges()
	# Drop leading -->
	var rest: String = line.substr(3).strip_edges()

	# Response text — quoted preferred, but unquoted (up to |) is tolerated.
	var text: String = ""
	var rest_after_text: String = ""
	if rest.begins_with("\""):
		var end_quote: int = rest.find("\"", 1)
		if end_quote > 0:
			text = rest.substr(1, end_quote - 1)
			rest_after_text = rest.substr(end_quote + 1).strip_edges()
		else:
			text = rest.substr(1)
	else:
		var pipe_idx: int = rest.find("|")
		if pipe_idx >= 0:
			text = rest.substr(0, pipe_idx).strip_edges()
			rest_after_text = rest.substr(pipe_idx).strip_edges()
		else:
			text = rest

	var preconds: Array = []
	var effects: Array = []
	if rest_after_text.begins_with("|"):
		var clauses: PackedStringArray = rest_after_text.substr(1).split(";")
		for c in clauses:
			var c_str: String = c.strip_edges()
			if c_str.is_empty():
				continue
			var eff: Dictionary = _try_parse_effect(c_str)
			if not eff.is_empty():
				effects.append(eff)
			else:
				var pre: Dictionary = _parse_precondition(c_str)
				if not pre.is_empty():
					preconds.append(pre)

	# Follow-up body lives at indent strictly greater than response_indent.
	var body_result: Dictionary = _parse_body(lines, start + 1, response_indent)

	var response: Dictionary = {
		"text": text,
		"preconditions": preconds,
		"effects": effects,
		"follow_up": body_result["body"],
	}
	return {
		"response": response,
		"next_line": body_result["next_line"],
		"errors": body_result.get("errors", []),
	}


# --- Helpers ---

static func _strip_comment(line: String) -> String:
	var idx: int = line.find("#")
	if idx < 0:
		return line
	return line.substr(0, idx)


# Tabs count as 4 spaces (normalized for indent purposes only).
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
