class_name MoveStep
extends EventStep

@export_node_path("CutsceneActor") var actor: NodePath
@export_node_path("Marker2D") var target: NodePath
@export var speed: float = 60.0


func run(event_root: Node) -> void:
	var a := get_node_or_null(actor) as CutsceneActor
	var t := get_node_or_null(target) as Marker2D
	if a == null or t == null:
		push_warning("MoveStep: missing actor or target")
		return
	await a.walk_to(t.global_position, speed)
