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


func _ready() -> void:
	MeetingManager.meeting_started.connect(_on_meeting_started)
	MeetingManager.meeting_completed.connect(_on_meeting_ended)
	MeetingManager.meeting_missed.connect(_on_meeting_ended)
	# Re-evaluate spawns when the player changes rooms.
	RoomManager.room_changed.connect(_on_room_changed)


# --- Signal handlers ---

func _on_meeting_started(meeting: Meeting) -> void:
	if _live_npcs.has(String(meeting.id)):
		return  # already spawned
	_try_spawn(meeting)


func _on_meeting_ended(meeting: Meeting) -> void:
	_despawn(meeting.id)


func _on_room_changed(_room_path: String) -> void:
	# Despawn any live NPCs whose meetings aren't in this new room. Then
	# spawn any active meetings whose spots ARE in this new room.
	for meeting_id in _live_npcs.keys():
		var m: Meeting = MeetingManager.get_meeting(StringName(meeting_id))
		if m == null or not _spot_is_in_current_room(m.spot_id):
			_despawn(StringName(meeting_id))
	for m in MeetingManager.active_meetings_now():
		if _live_npcs.has(String(m.id)):
			continue
		_try_spawn(m)


# --- Spawn / despawn ---

func _try_spawn(meeting: Meeting) -> void:
	if not _spot_is_in_current_room(meeting.spot_id):
		# Spot is in a different room — wait for the player to walk there.
		return
	var room: Node = RoomManager.current_room
	if room == null:
		return
	var spot_info: Dictionary = MeetingManager.get_spot_info(meeting.spot_id)
	if spot_info.is_empty():
		push_warning("MeetingSpawner: spot info missing for %s" % meeting.spot_id)
		return

	var npc: CustomerNPC = NPC_SCENE.instantiate()
	# Find or use a Placeables-style container if the room has one; otherwise
	# add directly to the room.
	var parent: Node = room.get_node_or_null("NPCs")
	if parent == null:
		parent = room
	parent.add_child(npc)
	npc.global_position = Vector2(spot_info.get("x", 0.0), spot_info.get("y", 0.0))
	npc.bind_to_meeting(meeting)
	_live_npcs[String(meeting.id)] = npc
	var customer: Customer = meeting.get_customer()
	print("[Spawner] %s arrived at %s" % [
		customer.display_name if customer else "?",
		MeetingManager.get_spot_display_name(meeting.spot_id),
	])


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
