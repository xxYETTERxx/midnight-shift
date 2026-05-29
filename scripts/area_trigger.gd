extends Area2D

@export var effect: String = ""

# Optional: prevent re-trigger immediately after spawning into a room
var _enabled: bool = true


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exit)


func _on_body_entered(body: Node2D) -> void:
	if not _enabled:
		return
	if not body.is_in_group("player"):
		return
	_enabled = false
	RelationshipSystem.set_global_flag(effect,true)

func _on_body_exit(body: Node2D) -> void:
	if not _enabled:
		return
	if not body.is_in_group("player"):
		return
	_enabled = false
	RelationshipSystem.set_global_flag(effect,false)
