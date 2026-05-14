extends Node

# Watches for event triggers via room_changed + minute_tick. When an event's
# conditions pass, swaps to that event's scene via the existing RoomManager
# plumbing (so we get the same fade + WorldState handling as doorways).
#
# Events live as standalone .tscn files in res://data/events/. Each event
# scene contains an Event node (in the "event_brain" group, registered in
# event.gd._ready). The director peeks each event's metadata by instancing
# it once at boot.

const EVENTS_DIR: String = "res://scenes/events/"

const _GAMEPLAY_ACTIONS: Array[StringName] = [
	&"interact", &"alt_interact", &"vault",
	&"hotbar_prev", &"hotbar_next", &"hotbar_cycle_row",
]

# Cached event metadata: { id: { path, conditions, repeatable } }
var _registry: Dictionary = {}
var _running_event_id: String = ""
var _return_room: String = ""
var _return_spawn: String = "default"
var _return_position: Vector2 = Vector2.ZERO

signal event_started(event_id: String)
signal event_finished(event_id: String)


func _ready() -> void:
	_load_registry()
	TimeSystem.minute_tick.connect(_on_minute_tick)
	RoomManager.room_changed.connect(_on_room_changed)


func is_running() -> bool:
	return _running_event_id != ""


# --- Registry ---

func _load_registry() -> void:
	_registry.clear()
	var dir := DirAccess.open(EVENTS_DIR)
	if dir == null:
		push_warning("EventDirector: %s not found — no events loaded" % EVENTS_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tscn"):
			_register_scene(EVENTS_DIR + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	print("[EventDirector] registered %d event(s)" % _registry.size())


func _register_scene(path: String) -> void:
	var packed: PackedScene = load(path)
	if packed == null:
		
		return
	var probe: Node = packed.instantiate()
	var brain: Event = _find_brain(probe)
	if brain == null:
		push_warning("EventDirector: %s has no Event node — skipped" % path)
		probe.queue_free()
		return
	if brain.id.is_empty():
		push_warning("EventDirector: %s has empty event id — skipped" % path)
		probe.queue_free()
		return
	_registry[brain.id] = {
		"path": path,
		"conditions": brain.conditions.duplicate(),
		"repeatable": brain.repeatable,
	}
	probe.queue_free()


func _find_brain(scene_root: Node) -> Event:
	if scene_root is Event:
		return scene_root
	for child in scene_root.get_children():
		if child is Event:
			return child
	return null


# --- Trigger evaluation ---

func _on_minute_tick(_total: int) -> void:
	_try_fire_eligible()


func _on_room_changed(_room_name: String) -> void:
	call_deferred("_try_fire_eligible")


func _try_fire_eligible() -> void:
	if is_running():
		return
	# Don't trigger events while inside an event scene's room.
	if RoomManager.current_room != null \
			and _find_brain(RoomManager.current_room) != null:
		return
	for event_id in _registry.keys():
		if _is_eligible(event_id):
			_fire(String(event_id))
			return


func _is_eligible(event_id: String) -> bool:
	var info: Dictionary = _registry[event_id]
	if not info["repeatable"] and RelationshipSystem.is_event_done(event_id):
		return false
	return EventConditionEvaluator.all_pass(info["conditions"])


# --- Run ---

func _fire(event_id: String) -> void:
	_running_event_id = event_id
	var info: Dictionary = _registry[event_id]

	# Remember where to return to. Player position too — change_room
	# repositions to a spawn point, but the room itself is what matters.
	var pre_room := RoomManager.current_room
	_return_room = pre_room.scene_file_path if pre_room != null else ""
	_return_position = _get_player_position()

	TimeSystem.pause()
	event_started.emit(event_id)

	# Swap to event scene under cover of fade.
	await ScreenFade.cover(func() -> void:
		RoomManager.change_room(info["path"], "default")
	)

	var event_root: Node = RoomManager.current_room
	var brain: Event = _find_brain(event_root)
	if brain == null:
		push_error("EventDirector: scene '%s' has no Event brain at runtime" % info["path"])
		_running_event_id = ""
		TimeSystem.resume()
		return

	if brain.hide_player:
		_set_player_active(false)

	# Override return target if the event specifies one.
	if not brain.return_room_path.is_empty():
		_return_room = brain.return_room_path
		_return_spawn = brain.return_spawn

	await _run_steps(event_root, brain)
	await _finish(event_id, brain)


func _run_steps(event_root: Node, brain: Event) -> void:
	var steps_root := brain.get_steps_root()
	if steps_root == null:
		push_warning("EventDirector: event has no Steps container")
		return
	for child in steps_root.get_children():
		if child is EventStep:
			await child.run(event_root)


func _finish(event_id: String, brain: Event) -> void:
	if not brain.repeatable:
		RelationshipSystem.mark_event_done(event_id)

	# Restore player visibility before the swap so it's visible during fade-in.
	_set_player_active(true)

	# Swap back to the originating room under cover of fade.
	if not _return_room.is_empty():
		var return_pos := _return_position
		var spawn := _return_spawn
		await ScreenFade.cover(func() -> void:
			RoomManager.change_room(_return_room, spawn)
			# RoomManager places the player at the spawn; if the event used
			# the default return path (came from gameplay), prefer the exact
			# pre-event position over the room's spawn point.
			if brain.return_room_path.is_empty():
				_set_player_position(return_pos)
		)

	TimeSystem.resume()
	_running_event_id = ""
	event_finished.emit(event_id)
	call_deferred("_try_fire_eligible")


# --- Player helpers (we don't hold a direct ref — find via RoomManager) ---

func _get_player_node() -> Node2D:
	var world: Node = RoomManager.get("_world")
	if world == null:
		return null
	return world.get_node_or_null("Player") as Node2D


func _get_player_position() -> Vector2:
	var p := _get_player_node()
	return p.global_position if p != null else Vector2.ZERO


func _set_player_position(pos: Vector2) -> void:
	var p := _get_player_node()
	if p != null:
		p.global_position = pos


func _set_player_active(active: bool) -> void:
	var p := _get_player_node()
	if p == null:
		return
	p.visible = active
	p.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED


# --- Input gating ---

func _unhandled_input(event: InputEvent) -> void:
	if not is_running():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc: int = event.keycode
		if kc >= KEY_1 and kc <= KEY_9:
			get_viewport().set_input_as_handled()
			return
	for action in _GAMEPLAY_ACTIONS:
		if event.is_action_pressed(action) or event.is_action_released(action):
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_accept") and DialogueRuntime.get("_active") == false:
		get_viewport().set_input_as_handled()


# --- Debug ---

func force_fire(event_id: String) -> bool:
	if is_running():
		push_warning("EventDirector: can't force-fire while another event runs")
		return false
	if not _registry.has(event_id):
		push_warning("EventDirector: no event with id '%s'" % event_id)
		return false
	_fire(event_id)
	return true


func reload() -> void:
	if is_running():
		push_warning("EventDirector: reload requested while event running — deferred")
		await event_finished
	_load_registry()
