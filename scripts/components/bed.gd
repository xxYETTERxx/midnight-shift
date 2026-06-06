extends Node2D



@onready var interactable: Interactable = $Interactable
@onready var wake_spot: Marker2D = $WakeSpot

@export var restore_to: float = -1.0   # -1 = full (bed); set 80 for a bedroll


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)


func _on_interacted(player: Node) -> void:
	TimeSkipSystem.time_skipped.connect(_on_time_skipped, CONNECT_ONE_SHOT)
	var wake_minute: int = player.call("_next_wake_minute")
	var cap: float = restore_to if restore_to >= 0.0 else StaminaSystem.maximum()
	TimeSkipSystem.skip_to(wake_minute, {
		"kind": "sleep",
		"safe": true,
		"voluntary": true,
		"restore_to": cap,
	})


func _on_time_skipped(_from: int, _to: int, _context: Dictionary) -> void:
	if not is_inside_tree():
		return
	print("[bed] time_skipped handler, in_tree=", is_inside_tree())
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = wake_spot.global_position
