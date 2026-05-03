class_name Interactable
extends Area2D

# Text shown in the HUD prompt when the player is in range.
# E.g., "Sleep", "Talk to Mira", "Harvest", "Pick lock".
@export var prompt_text: String = "Interact"

# If true, the interactable fires automatically when the player
# enters the zone, no E press required. Used by the bed.
@export var auto_trigger: bool = false

# Emitted when this interactable's interact() should run.
# The owning scene (bed, fence, etc.) connects to this signal
# and does the actual work.
signal interacted(player: Node)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if auto_trigger:
		# Skip the "active" path entirely — fire immediately
		interacted.emit(body)
	else:
		InteractionManager.set_active(self)


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if auto_trigger:
		return
	InteractionManager.clear_active(self)


# Called by InteractionManager when the player presses E.
func interact(player: Node) -> void:
	interacted.emit(player)
