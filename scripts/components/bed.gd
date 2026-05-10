extends Node2D



@onready var interactable: Interactable = $Interactable
@onready var wake_spot: Marker2D = $WakeSpot


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)


func _on_interacted(player: Node) -> void:
	# Connect one-shot so we only handle this specific skip
	TimeSkipSystem.time_skipped.connect(_on_time_skipped, CONNECT_ONE_SHOT)
	var wake_minute: int = player.call("_next_wake_minute")
	TimeSkipSystem.skip_to(wake_minute, {
		"kind": "sleep",
		"safe": true,
		"voluntary": true,
	})


func _on_time_skipped(_from: int, _to: int, _context: Dictionary) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player:
		player.global_position = wake_spot.global_position
