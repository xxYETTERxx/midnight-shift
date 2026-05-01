extends Node2D

@onready var player: Node2D = $Player

func _ready() -> void:
	RoomManager.register_world(self, player)
