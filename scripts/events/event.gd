class_name Event
extends Node

# The brain node inside an event scene. Sits as a child of the event scene's
# root (a duplicated room). Holds metadata; EventDirector discovers it on
# load by looking for the unique 'Event' group.

@export var id: String = ""
@export var conditions: Array[String] = []
@export var repeatable: bool = false

# When the event finishes, change back to this room with this spawn point.
# If return_room_path is empty, the director uses whatever room the player
# was in before the event fired (the typical case).
@export_file("*.tscn") var return_room_path: String = ""
@export var return_spawn: String = "default"

# If true, the player node is hidden for the event's duration. Default true
# because most cutscenes are puppet shows where the player isn't a participant.
@export var hide_player: bool = true

@export_node_path("Node") var steps_path: NodePath = ^"../Steps"


func _ready() -> void:
	add_to_group("event_brain")


func get_steps_root() -> Node:
	return get_node_or_null(steps_path)
