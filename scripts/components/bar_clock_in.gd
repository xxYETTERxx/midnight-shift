extends Node2D

# Temporary debug trigger to launch a bartending shift. Replace with the real
# employment-gated clock-in later. Modeled on payphone.gd.

@onready var interactable: Interactable = $Interactable

# Where the player returns to after the shift ends.
@export var return_marker: Marker2D


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)


func _on_interacted(_player: Node) -> void:
	var return_pos: Vector2 = return_marker.global_position if return_marker != null \
		else global_position
	BarShiftSession.begin_session(
		1,  # 1-hour shift for fast testing; bump to 4 later
		RoomManager.current_room.scene_file_path,
		return_pos,
	)
