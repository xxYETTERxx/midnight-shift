class_name MeetSpot
extends Node2D

# A location a customer can be sent to for a deal. Drop instances of this
# in the street/world scenes; they self-register with MeetingManager on _ready.

@export var spot_id: StringName = ""
@export var display_name: String = "Meet Spot"


func _ready() -> void:
	if spot_id == &"":
		push_warning("MeetSpot: spot_id is empty, skipping registration")
		return
	var scene_path := ""
	if owner != null and owner.scene_file_path != "":
		scene_path = owner.scene_file_path
	MeetingManager.register_spot(spot_id, display_name, scene_path, global_position)
