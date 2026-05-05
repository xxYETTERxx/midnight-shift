extends HBoxContainer

const SLOT_SCENE := preload("res://scenes/ui/hotbar_slot.tscn")
const HOTBAR_DISPLAY_COUNT: int = 12

var _slot_widgets: Array = []  # Array of HotbarSlot instances


func _ready() -> void:
	# Defer one frame so the player and inventory are ready
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_error("Hotbar: no player found")
		return
	var inventory: Inventory = player.inventory
	var display_count: int = min(HOTBAR_DISPLAY_COUNT, inventory.max_slots)
	_build_slots(display_count)
	_render_all(inventory)
	_highlight_active(inventory.active_slot)
	# Listen for changes
	inventory.slot_changed.connect(_on_slot_changed.bind(inventory))
	inventory.active_slot_changed.connect(_on_active_slot_changed)
	inventory.hotbar_offset_changed.connect(_on_hotbar_offset_changed.bind(inventory))


func _build_slots(count: int) -> void:
	# Clear any existing
	for c in get_children():
		c.queue_free()
	_slot_widgets.clear()
	# Build new
	for i in range(count):
		var slot := SLOT_SCENE.instantiate()
		slot.slot_index = i
		add_child(slot)
		_slot_widgets.append(slot)


func _render_all(inventory: Inventory) -> void:
	for i in range(_slot_widgets.size()):
		var world_slot: int = inventory.hotbar_offset + i
		_slot_widgets[i].render(inventory.get_slot(world_slot))


func _on_slot_changed(slot_index: int, inventory: Inventory) -> void:
	# Translate world slot to hotbar widget index
	var widget_index: int = slot_index - inventory.hotbar_offset
	if widget_index < 0 or widget_index >= _slot_widgets.size():
		return
	_slot_widgets[widget_index].render(inventory.get_slot(slot_index))


func _on_active_slot_changed(slot_index: int) -> void:
	_highlight_active(slot_index)


func _highlight_active(active_index: int) -> void:
	for i in range(_slot_widgets.size()):
		_slot_widgets[i].set_active(i == active_index)

func _on_hotbar_offset_changed(_offset: int, inventory: Inventory) -> void:
	_render_all(inventory)
