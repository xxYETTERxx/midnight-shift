class_name ATM
extends Node2D

# Dumb bank terminal. Holds no persistent state — the weekly tally and cap
# live in LaunderingSystem (one bank account, survives room rebuilds + saves).
# This node just opens the panel and forwards.

@onready var interactable: Interactable = $Interactable


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)


func _on_interacted(player: Node) -> void:
	var panel := get_tree().get_first_node_in_group("atm_panel")
	if panel == null:
		push_warning("ATM: no atm_panel in scene")
		return
	panel.open(player)


# Passthroughs for the panel's cap display — read straight from the autoload.
func weekly_cap() -> int:
	return LaunderingSystem.bank_weekly_cap()


func remaining_capacity() -> int:
	return LaunderingSystem.bank_remaining_capacity()
