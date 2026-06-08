class_name Front
extends Node2D

@export var front_id: StringName = &""
@export var max_limit: int = 4000
@export var purchase_price: int = 5000   # paid in clean cash (it's a legit asset)
@export var weekly_upkeep: int = 50

const LEMONADE_GAME: String = "res://scenes/minigames/lemonade_minigame.tscn"

@export var unowned_texture: Texture2D
@export var owned_texture: Texture2D



@onready var interactable: Interactable = $Interactable
@onready var sprite: Sprite2D = $Sprite


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)
	interactable.alt_interacted.connect(_on_alt_interacted)
	_refresh_visual()

func _refresh_visual() -> void:
	if LaunderingSystem.owns_front(front_id):
		if owned_texture != null:
			sprite.texture = owned_texture
	else:
		if unowned_texture != null:
			sprite.texture = unowned_texture

func _on_interacted(player: Node) -> void:
	if LaunderingSystem.owns_front(front_id):
		var panel := get_tree().get_first_node_in_group("clean_panel")
		panel.open(player)
	else:
		_offer_purchase(player)
		
func _on_alt_interacted(player: Node) -> void:
	if not LaunderingSystem.owns_front(front_id):
		return
	var room_path: String = ""
	if RoomManager.current_room != null:
		room_path = RoomManager.current_room.scene_file_path
	LemonadeStandSession.begin_session(room_path, player.global_position, &"city_central")

func _offer_purchase(player):
	if not Wallet.spend(purchase_price, "clean"):
		NotificationSystem.info("Not enough clean money.")
		return
	LaunderingSystem.register_front(front_id, max_limit)
	LedgerSystem.set_entry(front_id, &"laundering_upkeep", -weekly_upkeep, "Front upkeep")
	_refresh_visual()
	
	
func _open_clean_panel(player):
	NotificationSystem.info("")
	pass
