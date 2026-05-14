class_name AnimationStep
extends EventStep

@export_node_path("CutsceneActor") var actor: NodePath
@export var animation_name: String = ""
@export var await_finish: bool = false


func run(event_root: Node) -> void:
	var a := get_node_or_null(actor) as CutsceneActor
	if a == null or animation_name.is_empty():
		return
	await a.play_animation(animation_name, await_finish)
