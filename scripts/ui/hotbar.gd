extends HBoxContainer

const SLOT_SCENE := preload("res://scenes/ui/hotbar_slot.tscn")

var _slot_widgets: Array = []  # Array of HotbarSlot instances


func _ready() -> void:
	# Defer one frame so the player and inventory are ready
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_error("Hotbar: no player found")
		return
	var inventory: Inventory = player.inventory
	_build_slots(inventory.max_slots)
	_render_all(inventory)
	_highlight_active(inventory.active_slot)
	# Listen for changes
	inventory.slot_changed.connect(_on_slot_changed.bind(inventory))
	inventory.active_slot_changed.connect(_on_active_slot_changed)


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
		_slot_widgets[i].render(inventory.get_slot(i))


func _on_slot_changed(slot_index: int, inventory: Inventory) -> void:
	if slot_index < 0 or slot_index >= _slot_widgets.size():
		return
	_slot_widgets[slot_index].render(inventory.get_slot(slot_index))


func _on_active_slot_changed(slot_index: int) -> void:
	_highlight_active(slot_index)


func _highlight_active(active_index: int) -> void:
	for i in range(_slot_widgets.size()):
		_slot_widgets[i].set_active(i == active_index)
