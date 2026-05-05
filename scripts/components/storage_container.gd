class_name StorageContainer
extends Placeable

const STORAGE_SIZE: int = 24

@export var closed_texture: Texture2D
@export var open_texture: Texture2D

@onready var sprite: Sprite2D = $ContainerSprite
@onready var interactable: Interactable = $Interactable

# Each storage container has its own Inventory child.
@onready var storage: Inventory = $Inventory

var is_open: bool = false


func _ready() -> void:
	print("[StorageContainer] _ready called, instance: ", get_instance_id())
	storage.max_slots = STORAGE_SIZE
	interactable.interacted.connect(_on_interacted)
	print("[StorageContainer] connections: ", interactable.interacted.get_connections())
	_refresh_visual()


func _on_interacted(player: Node) -> void:
	# Toggle open state and request the UI to display.
	print("[StorageContainer] _on_interacted fired")
	if is_open:
		_close()
	else:
		_open(player)


func _open(player: Node) -> void:
	is_open = true
	_refresh_visual()
	# Tell the inventory panel to enter container mode with this container.
	var panel := _find_inventory_panel()
	if panel != null:
		panel.open_with_container(self)


func _close() -> void:
	is_open = false
	_refresh_visual()
	var panel := _find_inventory_panel()
	if panel != null:
		panel.close()


func _refresh_visual() -> void:
	if is_open and open_texture != null:
		sprite.texture = open_texture
	elif closed_texture != null:
		sprite.texture = closed_texture


# Called by InventoryPanel when it closes externally (e.g., player presses Tab).
# Lets the container reset its visual without re-entering the close handler.
func notify_panel_closed() -> void:
	is_open = false
	_refresh_visual()


func _find_inventory_panel() -> Node:
	# The panel lives at World/HUD/InventoryPanel. Group lookup is more robust.
	return get_tree().get_first_node_in_group("inventory_panel")


# --- Save/load ---

func save_state() -> Dictionary:
	var data := super.save_state()
	data["storage"] = storage.save_state()
	# Don't persist is_open — containers always restore as closed.
	return data


func load_state(data: Dictionary) -> void:
	super.load_state(data)
	if data.has("storage"):
		storage.load_state(data["storage"])
	is_open = false  # always start closed
	_refresh_visual()
