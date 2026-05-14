extends Node

# DialogueRuntime autoload (Step 3 of 4b — choices wired into the UI).

const DIALOGUE_BOX_SCENE: String = "res://scenes/ui/dialogue_box.tscn"

# --- State ---

var _is_running: bool = false
var _started_frame: int = -1
var _npc_id: String = ""
var _display_name: String = ""

var _queue: Array = []
var _current_portrait: String = "n"

var _box: CanvasLayer = null

signal dialogue_started(npc_id: String)

signal dialogue_ended()
signal response_selected(index: int)


# --- Lifecycle ---

func _ready() -> void:
	var scene: PackedScene = load(DIALOGUE_BOX_SCENE)
	if scene == null:
		push_error("DialogueRuntime: failed to load %s" % DIALOGUE_BOX_SCENE)
		return
	_box = scene.instantiate()
	add_child(_box)
	_box.clear()
	_box.choice_picked.connect(_on_box_choice_picked)


# --- Public API ---

func start(npc_id: String, display_name: String, entry: Dictionary) -> void:
	if _is_running:
		push_warning("DialogueRuntime: already running, ignoring start")
		return
	if entry.is_empty() or not entry.has("body"):
		push_warning("DialogueRuntime: empty entry, nothing to play")
		return

	_is_running = true
	_started_frame = Engine.get_process_frames()
	_npc_id = npc_id
	_display_name = display_name
	_queue = entry["body"].duplicate()
	_current_portrait = "n"

	TimeSystem.pause()
	dialogue_started.emit(npc_id)
	_play_next()


func advance() -> void:
	if not _is_running:
		return
	if _queue.is_empty():
		_end()
		return
	var head: Dictionary = _queue[0]
	if head["kind"] == "question":
		# Player must pick a response, not just advance.
		return
	_play_next()


func select_response(index: int) -> void:
	if not _is_running:
		return
	if _queue.is_empty():
		return
	var head: Dictionary = _queue[0]
	if head["kind"] != "question":
		return

	var eligible: Array = _eligible_responses(head["responses"])
	if index < 0 or index >= eligible.size():
		return

	var response: Dictionary = eligible[index]
	response_selected.emit(index)

	for effect in response["effects"]:
		RelationshipSystem.apply_effect(_npc_id, effect)

	_queue.pop_front()
	var follow_up: Array = response.get("follow_up", [])
	for i in range(follow_up.size() - 1, -1, -1):
		_queue.push_front(follow_up[i])

	_play_next()


func close() -> void:
	if _is_running:
		_end()


# --- Internals ---

func _play_next() -> void:
	if _queue.is_empty():
		_end()
		return

	var seg: Dictionary = _queue[0]
	match seg["kind"]:
		"text":
			var portrait_code: String = seg["portrait"]
			if portrait_code != "":
				_current_portrait = portrait_code
			_box.show_text(_npc_id, _display_name, _current_portrait, _substitute(seg["text"]))
			_queue.pop_front()
			# Wait for advance().
			if not _queue.is_empty() and _queue[0]["kind"] == "question":
				_play_next()

		"page_break":
			# Silently consumed; jump to the next segment.
			_queue.pop_front()
			_play_next()

		"question":
			var eligible: Array = _eligible_responses(seg["responses"])
			if eligible.is_empty():
				# All responses gated out — skip rather than softlocking.
				push_warning("DialogueRuntime: question with no eligible responses, skipping")
				_queue.pop_front()
				_play_next()
				return
			var texts: Array = []
			for r in eligible:
				texts.append(r["text"])
			_box.show_choices(texts)
			# Wait for choice_picked from the box (or a 1-9 keypress fallback).


func _on_box_choice_picked(index: int) -> void:
	select_response(index)


func _eligible_responses(responses: Array) -> Array:
	var out: Array = []
	for r in responses:
		var ok: bool = true
		for p in r.get("preconditions", []):
			if not _eval_precondition(p):
				ok = false
				break
		if ok:
			out.append(r)
	return out


func _eval_precondition(p: Dictionary) -> bool:
	match p["kind"]:
		"compare":
			var lhs = _resolve_stat(p["lhs"])
			return _compare(lhs, p["op"], p["rhs"])
		"flag":
			var has: bool = _check_flag(p["name"])
			return (not has) if p["negated"] else has
		"event_done":
			return RelationshipSystem.is_event_done(p["event"])
		"has_item":
			return false
	return false


func _resolve_stat(name: String):
	match name:
		"affinity": return RelationshipSystem.get_affinity(_npc_id)
		"trust":    return RelationshipSystem.get_trust(_npc_id)
		"day":      return TimeSystem.day_index() + 1
		"hour":     return TimeSystem.current_hour()
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


func _check_flag(name: String) -> bool:
	if name == "knows":
		return RelationshipSystem.get_knows(_npc_id)
	if RelationshipSystem.get_npc_flag(_npc_id, name):
		return true
	if RelationshipSystem.get_global_flag(name):
		return true
	return false


func _substitute(text: String) -> String:
	# %name → NPC display name. Other substitutions arrive in Step 4 polish.
	return text.replace("%name", _display_name)


func _end() -> void:
	_is_running = false
	_queue.clear()
	_npc_id = ""
	_display_name = ""
	_current_portrait = "n"
	if _box != null:
		_box.clear()
	TimeSystem.resume()
	dialogue_ended.emit()


# --- Input ---

func _unhandled_input(event: InputEvent) -> void:
	if not _is_running:
		return
	if Engine.get_process_frames() == _started_frame:
		return  # don't let the keypress that opened dialogue also advance it

	# Number keys 1-9 still pick choices as a keyboard fallback.
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.keycode
		if kc >= KEY_1 and kc <= KEY_9:
			select_response(kc - KEY_1)
			get_viewport().set_input_as_handled()
			return

	# E (interact): activate focused choice during a question, otherwise advance.
	if event.is_action_pressed("interact"):
		if not _queue.is_empty() and _queue[0]["kind"] == "question":
			if _box.activate_focused_choice():
				get_viewport().set_input_as_handled()
			return
		advance()
		get_viewport().set_input_as_handled()
		return

	# Enter/Space: Buttons handle this natively when focused (during a question).
	# When no choice is showing, treat it as advance.
	if event.is_action_pressed("ui_accept"):
		if _queue.is_empty() or _queue[0]["kind"] != "question":
			advance()
			get_viewport().set_input_as_handled()
		return
