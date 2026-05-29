class_name CraftingStation
extends Node2D

@export var station_tag: StringName = &"counter"

@onready var interactable: Interactable = $Interactable

func _ready() -> void:
	interactable.interacted.connect(_on_interacted)

func _on_interacted(player: Node) -> void:
	var panel := get_tree().get_first_node_in_group("crafting_panel")
	if panel == null:
		push_warning("CraftingStation: no crafting_panel found in scene")
		return
	panel.open_with_station(self, player)
