class_name FaceStep
extends EventStep

@export_node_path("CutsceneActor") var actor: NodePath
@export_enum("n", "s", "e", "w") var direction: String = "s"


func run(event_root: Node) -> void:
	var a := get_node_or_null(actor) as CutsceneActor
	if a == null:
		return
	a.face(direction)
