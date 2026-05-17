extends Node

# Listens to meeting lifecycle signals and manages live CustomerNPC instances
# in the world. NPCs only physically exist while their meeting's window is
# open AND the player is in the spot's room. Cross-room meetings (player in
# apartment while buyer waits on the street) are handled by hooking room
# changes — when the player enters a room with an active meeting, the NPC
# is materialized then.

const NPC_SCENE: PackedScene = preload("res://scenes/npcs/customer_npc.tscn")

# meeting_id (as String) → CustomerNPC instance currently in the scene tree.
# Absent if the NPC isn't currently spawned (window closed, or wrong room).
var _live_npcs: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	MeetingManager.meeting_spawning.connect(_on_meeting_started)
	MeetingManager.meeting_started.connect(_on_meeting_started)
	MeetingManager.meeting_completed.connect(_on_meeting_ended)
	MeetingManager.meeting_missed.connect(_on_meeting_ended)
	RoomManager.room_changed.connect(_on_room_changed)


# --- Signal handlers ---

func _on_meeting_started(meeting: Meeting) -> void:
	if _live_npcs.has(String(meeting.id)):
		return  # already spawned
	_try_spawn(meeting)


func _on_meeting_ended(meeting: Meeting) -> void:
	var key: String = String(meeting.id)
	var npc: Node = _live_npcs.get(key)
	_live_npcs.erase(key)
	if npc == null or not is_instance_valid(npc):
		return
	if npc.has_method("walk_away"):
		npc.walk_away()
	else:
		npc.queue_free()


func _on_room_changed(_room_path: String) -> void:
	# Despawn any live NPCs whose meetings aren't in this new room. Then
	# spawn any active meetings whose spots ARE in this new room.
	for meeting_id in _live_npcs.keys():
		var m: Meeting = MeetingManager.get_meeting(StringName(meeting_id))
		if m == null or not _spot_is_in_current_room(m.spot_id):
			_despawn(StringName(meeting_id))
	for m in MeetingManager.visible_meetings_now():
		if _live_npcs.has(String(m.id)):
			continue
		_try_spawn(m)


# --- Spawn / despawn ---

func _try_spawn(meeting: Meeting) -> void:
	if not _spot_is_in_current_room(meeting.spot_id):
		return
	var room: Node = RoomManager.current_room
	if room == null:
		return
	var spot_info: Dictionary = MeetingManager.get_spot_info(meeting.spot_id)
	if spot_info.is_empty():
		push_warning("MeetingSpawner: spot info missing for %s" % meeting.spot_id)
		return

	var npc: CustomerNPC = NPC_SCENE.instantiate()
	var parent: Node = room.get_node_or_null("NPCs")
	if parent == null:
		parent = room
	parent.add_child(npc)
	npc.bind_to_meeting(meeting)
	_live_npcs[String(meeting.id)] = npc

	var spot_pos := Vector2(spot_info.get("x", 0.0), spot_info.get("y", 0.0))
	var full_route: Array[Vector2] = _resolve_route(room, meeting.route_waypoints, spot_pos)

	# Figure out where along the route this customer should currently be,
	# given how many game-minutes have elapsed since their spawn_minute.
	var now_minute: int = TimeSystem.total_minutes
	var elapsed_game_minutes: int = max(0, now_minute - meeting.spawn_minute)
	var elapsed_real_seconds: float = elapsed_game_minutes * TimeSystem.real_seconds_per_minute
	var elapsed_distance: float = elapsed_real_seconds * CustomerNPC.WALK_SPEED

	var partial_route: Array[Vector2] = _advance_route(full_route, elapsed_distance)
	npc.walk_route(partial_route)

	var customer: Customer = meeting.get_customer()
	print("[Spawner] %s spawned (%d gmin into walk, %d wp remaining)" % [
		customer.display_name if customer else "?",
		elapsed_game_minutes,
		partial_route.size(),
	])


# Returns the route starting from the position reached after walking the
# given distance from the first waypoint. The remaining waypoints are
# whatever came after. If elapsed_distance >= total path length, returns
# [spot_position] — customer should already be parked at the spot.
func _advance_route(points: Array[Vector2], elapsed_distance: float) -> Array[Vector2]:
	if points.size() <= 1 or elapsed_distance <= 0.0:
		return points

	var remaining: float = elapsed_distance
	for i in range(1, points.size()):
		var seg_len: float = points[i - 1].distance_to(points[i])
		if remaining < seg_len:
			# Customer is partway along this segment.
			var t: float = remaining / seg_len
			var here: Vector2 = points[i - 1].lerp(points[i], t)
			var result: Array[Vector2] = [here]
			for j in range(i, points.size()):
				result.append(points[j])
			return result
		remaining -= seg_len

	# Walked the whole route — customer should be at the destination.
	return [points[-1]]


# Resolves a saved waypoint-id chain to positions. Falls back to teleport
# at spot_pos on any failure.
func _resolve_route(room: Node, waypoint_ids: Array, spot_pos: Vector2) -> Array[Vector2]:
	if waypoint_ids.is_empty():
		return [spot_pos]
	var points: Array[Vector2] = []
	for wp_id in waypoint_ids:
		var pos = _resolve_waypoint(room, wp_id)
		if pos == null:
			push_warning("MeetingSpawner: waypoint '%s' no longer resolves — teleporting" % wp_id)
			return [spot_pos]
		points.append(pos)
	return points


func _resolve_waypoint(room: Node, waypoint_id: StringName):
	if room == null:
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


func _despawn(meeting_id: StringName) -> void:
	var key := String(meeting_id)
	if not _live_npcs.has(key):
		return
	var npc: CustomerNPC = _live_npcs[key]
	_live_npcs.erase(key)
	if is_instance_valid(npc):
		npc.queue_free()


func _spot_is_in_current_room(spot_id: StringName) -> bool:
	var room: Node = RoomManager.current_room
	if room == null:
		return false
	var spot_info: Dictionary = MeetingManager.get_spot_info(spot_id)
	if spot_info.is_empty():
		return false
	return spot_info.get("scene_path", "") == room.scene_file_path
