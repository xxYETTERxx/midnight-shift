extends Node2D

# Reusable bus stop. For now its only behaviour: if a court date is confirmed,
# interacting resolves it as attended (the CourtSummons attend effect). Later
# this will open a transit/destination panel; the court branch becomes one
# option on it.

@onready var interactable: Interactable = $Interactable


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)


func _on_interacted(_player: Node) -> void:
	if CourtSummons.can_attend():
		CourtSummons.attend()
		return
	NotificationSystem.info("The bus isn't going anywhere right now.")
