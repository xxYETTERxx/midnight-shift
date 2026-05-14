class_name ChoiceStep
extends EventStep

# Presents a dialogue question and runs the matching Branch child's steps.
# Authoring: drop Branch nodes as direct children, set each one's `label`,
# fill each Branch with the EventSteps for that outcome.

@export_node_path("CutsceneActor") var speaker: NodePath
@export_multiline var prompt: String = ""
@export var portrait_override: String = ""

var _picked_index: int = -1


func _on_response_selected(idx: int) -> void:
	_picked_index = idx


func run(event_root: Node) -> void:
	var branches: Array[Branch] = []
	for child in get_children():
		if child is Branch:
			branches.append(child)
	if branches.is_empty():
		push_warning("ChoiceStep: no Branch children authored")
		return

	var portrait: String = portrait_override
	var npc_id: String = ""
	var display_name: String = ""
	var actor := get_node_or_null(speaker) as CutsceneActor
	if actor != null:
		npc_id = actor.dialogue_npc_id
		display_name = actor.display_name
		if portrait.is_empty():
			portrait = actor.default_portrait
	if portrait.is_empty():
		portrait = "n"

	var question_responses: Array = []
	for b in branches:
		question_responses.append({
			"text": b.label,
			"preconditions": [],
			"effects": [],
			"follow_up": [],
		})

	var entry := {
		"body": [
			{"kind": "text", "portrait": portrait, "text": prompt},
			{"kind": "question", "portrait": portrait, "text": "", "responses": question_responses},
		],
	}

	_picked_index = -1
	DialogueRuntime.response_selected.connect(_on_response_selected)
	DialogueRuntime.start(npc_id, display_name, entry)
	await DialogueRuntime.dialogue_ended
	DialogueRuntime.response_selected.disconnect(_on_response_selected)

	if _picked_index < 0 or _picked_index >= branches.size():
		push_warning("ChoiceStep: invalid pick index %d" % _picked_index)
		return

	var chosen: Branch = branches[_picked_index]
	for child in chosen.get_children():
		if child is EventStep:
			await child.run(event_root)
