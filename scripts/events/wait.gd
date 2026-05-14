class_name WaitStep
extends EventStep

@export var seconds: float = 1.0


func run(event_root: Node) -> void:
	if seconds <= 0.0:
		return
	await event_root.get_tree().create_timer(seconds).timeout
