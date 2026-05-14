class_name MarkEventDoneStep
extends EventStep

@export var event_id: String = ""


func run(_event_root: Node) -> void:
	if event_id.is_empty():
		return
	RelationshipSystem.mark_event_done(event_id)
