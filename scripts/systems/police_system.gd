extends Node

# Owns the active set of cops in the world. Listens for crimes; when one
# fires, picks a witnessing cop and pushes them into pursuit. Listens for
# room changes to end pursuit cleanly (the pawn-shop dodge).
#
# Cops register themselves on _ready and unregister on _exit_tree, so this
# works for both schedule-driven cops (Reggie) and any future dynamic-spawn
# cops without special-casing.
const PATROL_COP_SCENES: Array[PackedScene] = [
	preload("res://scenes/npcs/cop_patrol.tscn"),
]

const PATROL_TICK_INTERVAL: int = 30

# Cops on patrol per heat band [0,1,2,3]. Doc placeholder; tune.
const PATROL_COUNT_BY_BAND: Array[int] = [1, 2, 3, 4]

var _patrol_cops: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


signal pursuit_started(cop: CopNPC)
signal pursuit_ended(cop: CopNPC)
signal player_caught(cop: CopNPC)

# Live CopNPC instances, keyed by instance_id for stable removal.
var _cops: Dictionary = {}

# Subset of _cops currently in PURSUIT or INVESTIGATE.
var _pursuers: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	RoomManager.room_changed.connect(_on_room_changed)
	TimeSystem.minute_tick.connect(_on_minute_tick)


# --- Registration -------------------------------------------------------

func register_cop(cop: CopNPC) -> void:
	if cop == null:
		return
	var id := cop.get_instance_id()
	_cops[id] = cop
	cop.state_changed.connect(_on_cop_state_changed.bind(cop))
	cop.player_caught.connect(_on_player_caught.bind(cop))
	cop.backup_requested.connect(_on_backup_requested.bind(cop))


func unregister_cop(cop: CopNPC) -> void:
	if cop == null:
		return
	var id := cop.get_instance_id()
	_cops.erase(id)
	_pursuers.erase(id)



# --- Pursuit lifecycle --------------------------------------------------

func _on_cop_state_changed(new_state: int, cop: CopNPC) -> void:
	var id := cop.get_instance_id()
	if new_state == CopNPC.State.ROUTINE:
		if _pursuers.has(id):
			_pursuers.erase(id)
			pursuit_ended.emit(cop)
	else:
		if not _pursuers.has(id):
			_pursuers[id] = cop
			pursuit_started.emit(cop)


func _on_player_caught(cop: CopNPC) -> void:
	CrimeSystem.execute_bust(&"pursuit", &"", cop)
	player_caught.emit(cop)


func _on_backup_requested(_position: Vector2, _cop: CopNPC) -> void:
	pass
	# Dynamic-spawn join-pursuit lands in a later chunk. Log for now so
	# we can see it firing during dev.


# --- Room changes -------------------------------------------------------

# Player entered a new room (most often an interior). All active pursuits
# drop immediately — the pawn-shop dodge. NPCDirector will reconcile cops
# back into their schedules on the next minute tick.
func _on_room_changed(room_name: String) -> void:
	# End any active pursuits — the pawn-shop dodge.
	if not _pursuers.is_empty():

		var to_end: Array = _pursuers.values()
		for cop in to_end:
			if is_instance_valid(cop):
				cop.end_pursuit()

	# Patrol cops are room-scoped for now — old ones die with the previous
	# room, populate fresh ones for the new area if it has routes.
	_patrol_cops.clear()
	_populate_patrols_for_current_area()


func _populate_patrols_for_current_area() -> void:
	var room: Node = RoomManager.current_room
	if room == null:
		return
	var area_id: StringName = StringName(room.scene_file_path.get_file().get_basename())
	if PatrolRoutes.get_routes(area_id).is_empty():
		return

	var band: int = HeatSystem.get_heat_band(area_id)
	band = clamp(band, 0, PATROL_COUNT_BY_BAND.size() - 1)
	var target_count: int = PATROL_COUNT_BY_BAND[band]

	for i in range(target_count):
		_spawn_patrol_cop(room, area_id)


func _spawn_patrol_cop(room: Node, area_id: StringName) -> void:
	if PATROL_COP_SCENES.is_empty():
		return
	var route_ids: Array = PatrolRoutes.pick_random_route(area_id, _rng)
	if route_ids.size() < 2:
		return

	var points: Array[Vector2] = []
	for wp_id in route_ids:
		var pos = _resolve_waypoint(room, wp_id)
		if pos == null:
			return
		points.append(pos)


	var scene: PackedScene = PATROL_COP_SCENES[_rng.randi() % PATROL_COP_SCENES.size()]
	var cop: CopNPC = scene.instantiate()
	var parent: Node = room.get_node_or_null("NPCs")
	if parent == null:
		parent = room
	parent.add_child(cop)
	# CopNPC._ready already registered this cop via PoliceSystem.register_cop.

	cop.set_patrol(points)
	cop.patrol_finished.connect(_on_patrol_finished.bind(cop))
	_patrol_cops[cop.get_instance_id()] = cop


func _on_patrol_finished(cop: CopNPC) -> void:
	# Cop reached the end of their route — despawn.
	if not is_instance_valid(cop):
		return
	_patrol_cops.erase(cop.get_instance_id())
	cop.queue_free()


# Walks the room's Waypoints container looking for the given id.
# Mirrors NPCDirector's resolver — could be extracted to a shared utility
# later if a third caller shows up.
func _resolve_waypoint(room: Node, waypoint_id: StringName):
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
	
func _on_minute_tick(total_minutes: int) -> void:
	if total_minutes % PATROL_TICK_INTERVAL != 0:
		return
	_top_up_patrols_for_current_area()


# Re-evaluates the cop count for the player's current area and spawns one
# additional patrol if we're below the heat-band target. Runs every
# PATROL_TICK_INTERVAL minutes; complements the one-shot population that
# happens on room_changed.
func _top_up_patrols_for_current_area() -> void:
	var room: Node = RoomManager.current_room
	if room == null:
		return
	var area_id: StringName = StringName(room.scene_file_path.get_file().get_basename())
	if PatrolRoutes.get_routes(area_id).is_empty():
		return

	var band: int = HeatSystem.get_heat_band(area_id)
	band = clamp(band, 0, PATROL_COUNT_BY_BAND.size() - 1)
	var target_count: int = PATROL_COUNT_BY_BAND[band]
	var current_count: int = _count_live_patrols()

	if current_count >= target_count:
		return

	_spawn_patrol_cop(room, area_id)


# Counts non-freed patrol cops. Lazily prunes invalid refs from the dict —
# cops queue_free themselves on patrol_finished, but the dict entry is
# only erased in _on_patrol_finished. Stale entries are harmless either
# way; this counter ignores them.
func _count_live_patrols() -> int:
	var n: int = 0
	for cop in _patrol_cops.values():
		if is_instance_valid(cop):
			n += 1
	return n
	


# Called by CrimeSystem after try_witness returns a cop. Pushes that
# specific cop into pursuit. Idempotent — if the cop is already pursuing,
# this is a no-op.
func dispatch_pursuit(cop: CopNPC) -> void:
	if cop == null or not is_instance_valid(cop):
		return
	if cop.state != CopNPC.State.ROUTINE:
		return
	var player: Node2D = RoomManager.get_player()
	if player == null:
		return
	cop.begin_pursuit(player)
