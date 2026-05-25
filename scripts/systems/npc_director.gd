extends Node

# Owns NPC presence in the world. For each registered NPC, every minute
# tick (and on room changes) it queries ScheduleDatabase for the currently
# active entry under current context, materializes a ScheduledNPC in the
# current room if appropriate, or despawns one that no longer belongs.
#
# Schedule data is authored in res://data/schedules/<npc_id>.sched.

# npc_id (as String) → { scene: PackedScene, display_name: String }
var _registry: Dictionary = {}

# npc_id (as String) → currently-effective window dict from Schedule.entry_window_at.
var _current_windows: Dictionary = {}

# npc_id (as String) → live ScheduledNPC node, or absent if not materialized.
var _live_npcs: Dictionary = {}

signal npc_materialized(npc_id: StringName)
signal npc_despawned(npc_id: StringName)


func _ready() -> void:
	SaveSystem.register_savable("npc_director", self)
	TimeSystem.minute_tick.connect(_on_minute_tick)
	RoomManager.room_changed.connect(_on_room_changed)
	ScheduleDatabase.reloaded.connect(_on_schedules_reloaded)
	_register_all_npcs()


# --- Registration -------------------------------------------------------

func register_npc(npc_id: StringName, scene: PackedScene, display_name: String = "") -> void:
	if npc_id == &"":
		push_warning("NPCDirector: refusing to register NPC with empty id")
		return
	if scene == null:
		push_warning("NPCDirector: missing scene for %s" % npc_id)
		return
	if not ScheduleDatabase.has_npc(String(npc_id)):
		push_warning("NPCDirector: no .sched file for %s" % npc_id)
		return
	_registry[String(npc_id)] = {
		"scene": scene,
		"display_name": display_name,
	}
	_current_windows[String(npc_id)] = _compute_window(npc_id)


func _register_all_npcs() -> void:
	var oliver_scene: PackedScene = load("res://scenes/npcs/oliver.tscn")
	var erik_scene: PackedScene = load("res://scenes/npcs/erik.tscn")
	var felix_scene: PackedScene = load("res://scenes/npcs/felix.tscn")
	var hank_scene: PackedScene = load("res://scenes/npcs/hank.tscn")
	register_npc(&"oliver", oliver_scene, "Oliver")
	register_npc(&"erik", erik_scene, "Erik")
	register_npc(&"felix", felix_scene, "Felix")
	register_npc(&"hank", hank_scene, "Hank")


# --- Schedule queries ---------------------------------------------------

func _compute_window(npc_id: StringName) -> Dictionary:
	var context := _build_context()
	var schedule: Schedule = ScheduleDatabase.get_active_schedule(String(npc_id), context)
	if schedule == null:
		return {}
	return schedule.entry_window_at(_current_minute_of_day())


func _build_context() -> Dictionary:
	return {"weekday": _weekday_string()}


func _weekday_string() -> String:
	const NAMES: Array[String] = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
	return NAMES[TimeSystem.day_of_week()]


# TimeSystem.total_minutes == 0 represents 14:00 Mon Day 1. Convert to a
# calendar minute-of-day (0..1439).
func _current_minute_of_day() -> int:
	return (TimeSystem.total_minutes + 14 * 60) % 1440


func get_current_entry(npc_id: StringName) -> Dictionary:
	return _current_windows.get(String(npc_id), {}).get("entry", {})


# --- Tick / room reconciliation ----------------------------------------

func _on_minute_tick(_total: int) -> void:
	for key in _registry.keys():
		var npc_id := StringName(key)
		var new_window := _compute_window(npc_id)
		var old_window: Dictionary = _current_windows.get(key, {})
		if not _windows_equivalent(old_window, new_window):
			_current_windows[key] = new_window
			_reconcile_npc(npc_id)


func _on_room_changed(_room_path: String) -> void:
	for key in _registry.keys():
		_reconcile_npc(StringName(key))


# A schedule file edit (hot reload) or a flag/event change can swap which
# block is active without a minute boundary. Re-evaluate everyone.
func _on_schedules_reloaded() -> void:
	for key in _registry.keys():
		var npc_id := StringName(key)
		var new_window := _compute_window(npc_id)
		if not _windows_equivalent(_current_windows.get(key, {}), new_window):
			_current_windows[key] = new_window
			_reconcile_npc(npc_id)


func _reconcile_npc(npc_id: StringName) -> void:
	var key := String(npc_id)
	var window: Dictionary = _current_windows.get(key, {})
	var entry: Dictionary = window.get("entry", {})
	var should_exist: bool = _entry_is_in_current_room(entry)
	var is_live: bool = _live_npcs.has(key)

	if not should_exist:
		if is_live:
			_despawn(npc_id)
		return

	if not is_live:
		_materialize(npc_id, window)
	else:
		var npc: ScheduledNPC = _live_npcs[key]
		# Cops (and anyone else that opts into override) drive their own
		# pose during pursuit/investigate. Skip schedule updates for them.
		if npc.has_method("is_overridden") and npc.call("is_overridden"):
			return
		_apply_pose(npc, entry, window)


func _entry_is_in_current_room(entry: Dictionary) -> bool:
	if entry.is_empty():
		return false
	var room: Node = RoomManager.current_room
	if room == null:
		return false
	return entry.get("scene_path", "") == room.scene_file_path


# --- Spawn / pose / despawn --------------------------------------------

func _materialize(npc_id: StringName, window: Dictionary) -> void:
	var key := String(npc_id)
	var info: Dictionary = _registry.get(key, {})
	if info.is_empty():
		return
	var scene: PackedScene = info["scene"]
	var room: Node = RoomManager.current_room
	if scene == null or room == null:
		return

	var npc: ScheduledNPC = scene.instantiate()
	npc.npc_id = String(npc_id)

	var parent: Node = room.get_node_or_null("NPCs")
	if parent == null:
		parent = room
	parent.add_child(npc)

	# Cops emit state_changed when pursuit ends; re-push their pose so the
	# schedule picks back up at the correct waypoint without waiting for
	# the next minute tick.
	if npc.has_signal("state_changed"):
		npc.state_changed.connect(_on_cop_state_changed.bind(npc_id))

	_apply_pose(npc, window.get("entry", {}), window)

	_live_npcs[key] = npc
	npc_materialized.emit(npc_id)
	print("[NPCDirector] %s materialized (%s)" % [
		npc_id, window.get("entry", {}).get("activity", "stand"),
	])


func _apply_pose(npc: ScheduledNPC, entry: Dictionary, window: Dictionary) -> void:
	var kind: String = entry.get("kind", "stationary")
	var room: Node = RoomManager.current_room
	if room == null:
		return

	if kind == "transit":
		var route: Array = entry.get("route", [])
		if route.size() < 2:
			push_warning("NPCDirector: transit entry needs at least 2 waypoints")
			return
		var positions: Array[Vector2] = []
		for marker in route:
			var pos = _resolve_waypoint_position(room, StringName(marker))
			if pos == null:
				push_warning("NPCDirector: missing waypoint '%s' for transit" % marker)
				return
			positions.append(pos)
		npc.set_transit(
			positions,
			window.get("start_minute", 0),
			window.get("end_minute", 0),
			entry.get("animation", "walk"),
		)
	else:
		var pos = _resolve_waypoint_position(room, entry.get("marker", &""))
		if pos == null:
			push_warning("NPCDirector: waypoint '%s' not found in %s" % [
				entry.get("marker", &""), room.scene_file_path,
			])
			return
		npc.set_stationary(
			pos,
			entry.get("animation", "idle"),
			entry.get("facing", "south"),
		)


func _despawn(npc_id: StringName) -> void:
	var key := String(npc_id)
	if not _live_npcs.has(key):
		return
	var raw = _live_npcs[key]   # untyped read first
	_live_npcs.erase(key)
	if raw == null or not is_instance_valid(raw):
		# already gone — fire signal anyway in case listeners track presence
		npc_despawned.emit(npc_id)
		return
	var npc: ScheduledNPC = raw
	npc.queue_free()
	npc_despawned.emit(npc_id)


func _resolve_waypoint_position(room: Node, waypoint_id: StringName):
	if room == null or waypoint_id == &"":
		return null
	var container: Node = room.get_node_or_null("Waypoints")
	if container != null:
		for child in container.get_children():
			if child is Waypoint and child.waypoint_id == waypoint_id:
				return child.global_position
	var found := _find_waypoint_in_subtree(room, waypoint_id)
	return found.global_position if found != null else null


func _find_waypoint_in_subtree(node: Node, waypoint_id: StringName) -> Waypoint:
	if node is Waypoint and node.waypoint_id == waypoint_id:
		return node
	for child in node.get_children():
		var hit := _find_waypoint_in_subtree(child, waypoint_id)
		if hit != null:
			return hit
	return null


# --- Helpers ------------------------------------------------------------

# Two windows are equivalent only if they represent the same block at the
# same start_minute with the same content. Same start_minute alone isn't
# enough — a schedule swap can produce a different entry at that minute.
func _windows_equivalent(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() and b.is_empty():
		return true
	if a.is_empty() or b.is_empty():
		return false
	if a.get("start_minute", -1) != b.get("start_minute", -1):
		return false
	var ea: Dictionary = a.get("entry", {})
	var eb: Dictionary = b.get("entry", {})
	if ea.get("kind", "") != eb.get("kind", ""):
		return false
	if ea.get("animation", "") != eb.get("animation", ""):
		return false
	if ea.get("scene_path", "") != eb.get("scene_path", ""):
		return false
	if ea.get("marker", &"") != eb.get("marker", &""):
		return false
	if ea.get("route", []) != eb.get("route", []):
		return false
	return true
	
func is_npc_present(npc_id: StringName) -> bool:
	return _current_windows.has(String(npc_id)) \
		and _entry_is_in_current_room(get_current_entry(npc_id))

func is_npc_in_scene(npc_id: StringName, scene_path: String) -> bool:
	var entry: Dictionary = get_current_entry(npc_id)
	if entry.is_empty():
		return false
	return entry.get("scene_path", "") == scene_path


func _on_cop_state_changed(_new_state: int, npc_id: StringName) -> void:
	# When a cop returns to ROUTINE, immediately re-apply its schedule pose
	# so it teleports back to where the schedule says it should be. Without
	# this, the cop would stand in place until the next minute tick.
	var key := String(npc_id)
	if not _live_npcs.has(key):
		return
	var npc: ScheduledNPC = _live_npcs[key]
	if npc.has_method("is_overridden") and npc.call("is_overridden"):
		return
	var window: Dictionary = _current_windows.get(key, {})
	_apply_pose(npc, window.get("entry", {}), window)

# --- Save / load --------------------------------------------------------


func save_state() -> Dictionary:
	return {}


func load_state(_data: Dictionary) -> void:
	call_deferred("_resync_after_load")


func _resync_after_load() -> void:
	for key in _registry.keys():
		_current_windows[key] = _compute_window(StringName(key))
		_reconcile_npc(StringName(key))
