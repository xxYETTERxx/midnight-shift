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

# If this run was started from a peeked queue event, the name lives here so
# we can pop it on natural completion (and leave it alone on abort).
var _queued_event_to_consume: String = ""

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
	_queued_event_to_consume = ""
	if entry.get("is_event", false):
		var ev: String = String(entry.get("event_name", ""))
		if ev != "" and RelationshipSystem.peek_dialogue(npc_id) == ev:
			_queued_event_to_consume = ev
	_display_name = display_name
	_queue = entry["body"].duplicate()
	_current_portrait = "n"

	TimeSystem.pause()
	dialogue_started.emit(npc_id)
	_play_next()

# One-call entry point: resolves this NPC's contextual line and plays it.
# Both NPC interaction and vendor interaction route through here so context
# logic lives in exactly one place. Returns true if a line actually started
# (caller can then `await dialogue_ended`); false if there was no match or
# the runtime was busy.
func trigger(npc_id: String, display_name: String) -> bool:
	if _is_running:
		return false
	if npc_id == "" or not DialogueDatabase.has_npc(npc_id):
		return false
	var entry := DialogueDatabase.get_line(npc_id, _build_context())
	if entry.is_empty():
		return false
	start(npc_id, display_name, entry)
	return true


# Context dict the dialogue lookup uses to filter keys. Add to this as new
# tag types are needed (weather, custom event flags, etc.).
func _build_context() -> Dictionary:
	return {
		"weekday": _weekday_string(),
		"timeofday": _time_of_day_string(),
		"location": _current_location_id(),
	}


func _weekday_string() -> String:
	const NAMES: Array[String] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
	return NAMES[TimeSystem.day_of_week()]


func _time_of_day_string() -> String:
	var h: int = TimeSystem.current_hour()
	if h >= 6 and h < 12:
		return "morning"
	if h >= 12 and h < 18:
		return "afternoon"
	if h >= 18 and h < 22:
		return "evening"
	return "night"


func _current_location_id() -> String:
	if RoomManager.current_room == null:
		return ""
	return RoomManager.current_room.scene_file_path.get_file().get_basename()

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

	# Atomic check: if anything this response demands the player give up
	# isn't available, abort before applying anything. State is untouched,
	# so re-engaging will surface the same line again.
	if not _can_afford_response(response["effects"]):
		NotificationSystem.warn("You don't have that")
		_end(false)
		return

	response_selected.emit(index)

	for effect in response["effects"]:
		_apply_effect(effect)

	_queue.pop_front()
	var follow_up: Array = response.get("follow_up", [])
	for i in range(follow_up.size() - 1, -1, -1):
		_queue.push_front(follow_up[i])

	_play_next()


func close() -> void:
	if _is_running:
		_end(false)


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
			print("[dlg] panel pos=", _box.get_node("PanelContainer").position,
	" size=", _box.get_node("PanelContainer").size,
	" min=", _box.get_node("PanelContainer").get_combined_minimum_size(),
	" offset_top=", _box.get_node("PanelContainer").offset_top)
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
			return _player_has_item(p["item"])
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

func _apply_effect(effect: Dictionary) -> void:
	
	match effect.get("kind", ""):
		"stat_delta", "set_flag":
			RelationshipSystem.apply_effect(_npc_id, effect)
		"wallet_delta":
			Wallet.add(int(effect["delta"]), String(effect["pool"]))
		"item_delta":
			_apply_item_delta(String(effect["item"]), int(effect["delta"]))
		_:
			push_warning("DialogueRuntime: unknown effect kind '%s'" % effect.get("kind", ""))


func _apply_item_delta(item_id: String, delta: int) -> void:
	if delta == 0:
		return
	var item_def: ItemDef = ItemRegistry.get_item(StringName(item_id))
	if item_def == null:
		push_warning("DialogueRuntime: unknown item '%s' in effect" % item_id)
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		push_warning("DialogueRuntime: no player found for item_delta effect")
		return
	var inv: Inventory = _get_player_inventory()
	if inv == null:
		push_warning("DialogueRuntime: no player inventory for effect")
		return

	if delta > 0:
		var leftover: int = inv.add(item_def, delta)
		if leftover > 0:
			push_warning("DialogueRuntime: inventory full, %d of '%s' could not fit" % [leftover, item_id])
	else:
		var needed: int = -delta
		for i in range(inv.slots.size()):
			if needed <= 0:
				break
			var stack: ItemStack = inv.get_slot(i)
			if stack == null or stack.item == null or stack.item.id != item_def.id:
				continue
			var taken: int = min(stack.count, needed)
			inv.consume_from_slot(i, taken)
			needed -= taken
		if needed > 0:
			push_warning("DialogueRuntime: needed %d more of '%s' but inventory ran out" % [needed, item_id])

# Returns true if the player can absorb every loss this response demands.
# Aggregates across effects so `cash -20; cash -30` is checked as $50, and
# `take SEED 2; take SEED 1` as 3 seeds.
func _can_afford_response(effects: Array) -> bool:
	var pool_needed: Dictionary = {}   # pool name → total cash to remove
	var item_needed: Dictionary = {}   # item id   → total count to remove

	for effect in effects:
		match effect.get("kind", ""):
			"wallet_delta":
				var d: int = int(effect["delta"])
				if d < 0:
					var pool: String = String(effect["pool"])
					pool_needed[pool] = int(pool_needed.get(pool, 0)) + (-d)
			"item_delta":
				var d: int = int(effect["delta"])
				if d < 0:
					var id: String = String(effect["item"])
					item_needed[id] = int(item_needed.get(id, 0)) + (-d)

	for pool in pool_needed:
		if not Wallet.can_afford(int(pool_needed[pool]), String(pool)):
			return false

	if not item_needed.is_empty():
		var inv: Inventory = _get_player_inventory()
		if inv == null:
			# Response wants items but there's no inventory — fail closed.
			return false
		for id in item_needed:
			if _inventory_count(inv, StringName(id)) < int(item_needed[id]):
				return false

	return true


func _get_player_inventory() -> Inventory:
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	return player.get("inventory")

func _player_has_item(item_id: String) -> bool:
	var inv: Inventory = _get_player_inventory()
	if inv == null:
		return false
	return inv.has_item(StringName(item_id))

func _inventory_count(inv: Inventory, item_id: StringName) -> int:
	var total: int = 0
	for stack in inv.slots:
		if stack != null and stack.item != null and stack.item.id == item_id:
			total += stack.count
	return total

func _substitute(text: String) -> String:
	# %name → NPC display name. Other substitutions arrive in Step 4 polish.
	return text.replace("%name", _display_name)


func _end(consume_queue: bool = true) -> void:
	if consume_queue and _queued_event_to_consume != "" and _npc_id != "":
		# Pop only if the head still matches what we started with — guards
		# against the (rare) case of something pushing during dialogue.
		if RelationshipSystem.peek_dialogue(_npc_id) == _queued_event_to_consume:
			RelationshipSystem.pop_dialogue(_npc_id)
	_queued_event_to_consume = ""
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
