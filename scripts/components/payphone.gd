class_name Payphone
extends Node2D

@onready var interactable: Interactable = $Interactable


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)


func _on_interacted(_player: Node) -> void:
	var panel := get_tree().get_first_node_in_group("callback_panel")
	if panel == null:
		push_warning("Payphone: no callback_panel in scene tree")
		return
	panel.open()
