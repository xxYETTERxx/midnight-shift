extends Node2D

# Temporary debug trigger to launch a bartending shift. Replace with the real
# employment-gated clock-in later. Modeled on payphone.gd.

@onready var interactable: Interactable = $Interactable

# Where the player returns to after the shift ends.
@export var return_marker: Marker2D


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)


func _on_interacted(_player: Node) -> void:
	if not EmploymentSystem.can_clock_in():
		NotificationSystem.warn("No shift to clock into right now.")
		return
	EmploymentSystem.clock_in()
	var return_pos: Vector2 = return_marker.global_position if return_marker != null \
		else global_position
	BarShiftSession.begin_session(
		EmploymentSystem.SHIFT_LENGTH_HOURS,
		RoomManager.current_room.scene_file_path,
		return_pos,
	)
