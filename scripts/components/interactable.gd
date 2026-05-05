class_name Interactable
extends Area2D

# Text shown in the HUD prompt when the player is in range and this
# interactable wins the priority arbitration.
@export var prompt_text: String = "Interact"

# If true, the interactable fires automatically when the player enters
# the zone. Auto-triggers bypass priority arbitration entirely.
@export var auto_trigger: bool = false

# Higher priority wins when multiple overlapping interactables are eligible.
# Suggested scale (rough):
#   100 — harvestable plants / time-sensitive
#    80 — plant slots / planting actions
#    60 — containers (pots, stash boxes)
#    40 — NPC dialogue
#    30 — doorways (when not auto-triggered)
#    20 — lamps and ambient toggles
#    10 — pure decoration / examine
@export var interact_priority: int = 50

# Emitted when the interactable's eligibility (can_interact) might have
# changed. The owning scene fires this when its state changes — e.g.,
# a plant matures, a pot becomes empty, a lamp turns on. InteractionManager
# listens to this and re-arbitrates the winner.
signal state_changed

# Emitted when this interactable is interacted with.
signal interacted(player: Node)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if auto_trigger:
		# Auto-trigger fires immediately, doesn't enter arbitration.
		interacted.emit(body)
	else:
		InteractionManager.register(self)


func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	if auto_trigger:
		return
	InteractionManager.unregister(self)


# Override in subclasses or on owning-scene scripts to make the interactable
# eligible only in certain conditions. Default: always eligible.
func can_interact(_player: Node) -> bool:
	return true


# Called by InteractionManager when the player presses E and this
# interactable wins the arbitration.
func interact(player: Node) -> void:
	interacted.emit(player)

func _player_holds(player: Node, id: StringName) -> bool:
	return player != null and player.has_method("is_holding") and player.is_holding(id)

func _player_holds_category(player: Node, cat: int) -> bool:
	var inv = player.get("inventory") if player else null
	if inv == null: return false
	var stack = inv.get_active_stack()
	return stack != null and stack.item != null and stack.item.category == cat
