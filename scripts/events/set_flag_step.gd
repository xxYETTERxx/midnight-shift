class_name SetFlagStep
extends EventStep

@export var flag_name: String = ""
@export var npc_id: String = ""
@export var value: bool = true


func run(_event_root: Node) -> void:
	if flag_name.is_empty():
		return
	if npc_id.is_empty():
		RelationshipSystem.set_global_flag(flag_name, value)
	else:
		RelationshipSystem.set_npc_flag(npc_id, flag_name, value)
