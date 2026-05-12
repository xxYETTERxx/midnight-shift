class_name Waypoint
extends Node2D

# Named position marker used by NPCDirector to place scheduled NPCs.
# Drop instances as children of a "Waypoints" Node2D inside each room.
# The id is referenced from Schedule entries by name; the NPC is positioned
# at this node's global_position when the schedule sends them here.

@export var waypoint_id: StringName = &""
@export_enum("none", "north", "south", "east", "west") var facing: String = "none"


func _ready() -> void:
	if waypoint_id == &"":
		push_warning("Waypoint at %s has no waypoint_id" % get_path())
	add_to_group("waypoints")
