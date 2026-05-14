class_name DialogueStep
extends EventStep

# Plays an inline dialogue sequence. Carries its own text + portraits.
# Speaker is a CutsceneActor in the scene — its dialogue_npc_id and
# display_name auto-fill the dialogue box header when set.

@export_node_path("CutsceneActor") var speaker: NodePath
@export_multiline var text: String = ""
@export var portrait_override: String = ""


func run(event_root: Node) -> void:
	if text.is_empty():
		return
	var npc_id: String = ""
	var display_name: String = ""
	var portrait: String = portrait_override
	var actor := get_node_or_null(speaker) as CutsceneActor
	if actor != null:
		npc_id = actor.dialogue_npc_id
		display_name = actor.display_name
		if portrait.is_empty():
			portrait = actor.default_portrait
	if portrait.is_empty():
		portrait = "n"
	var entry := {
		"body": [
			{"kind": "text", "portrait": portrait, "text": text},
		]
	}
	DialogueRuntime.start(npc_id, display_name, entry)
	await DialogueRuntime.dialogue_ended
