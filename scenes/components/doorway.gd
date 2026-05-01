extends Area2D

@export_file("*.tscn") var target_room: String = ""
@export var target_spawn: String = "default"

# Optional: prevent re-trigger immediately after spawning into a room
var _enabled: bool = true


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	if not _enabled:
		return
	if not body.is_in_group("player"):
		return
	_enabled = false
	RoomManager.change_room(target_room, target_spawn)
