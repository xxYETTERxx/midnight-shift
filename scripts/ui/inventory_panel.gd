extends Control

const SLOT_SCENE := preload("res://scenes/ui/hotbar_slot.tscn")
const HOTBAR_SLOT_COUNT: int = 12
const DROPPED_ITEM_SCENE := preload("res://scenes/components/dropped_item.tscn")

@onready var hotbar_row: HBoxContainer = $PanelContainer/VBoxContainer/HotbarRow
@onready var backpack_grid: GridContainer = $PanelContainer/VBoxContainer/BackpackGrid

@onready var storage_title: Label = $PanelContainer/VBoxContainer/StorageTitle
@onready var storage_grid: GridContainer = $PanelContainer/VBoxContainer/StorageGrid

#const STORAGE_GRID_SCENE := preload("res://scenes/ui/inv_panel.tscn")  # placeholder, see below

var _viewing_container: StorageContainer = null
var _storage_widgets: Array = []

var _slot_widgets: Array = []  # length == inventory.max_slots
var _inventory: Inventory = null
var _is_open: bool = false

var _selected_widget: HotbarSlot = null  # currently highlighted slot widget
var _selected_inventory: Inventory = null  # which inventory the selection is in
var _selected_slot_index: int = -1

# When the player picks up a stack, it lives "on the cursor" until placed.
# null means cursor is empty.
var _cursor_stack: ItemStack = null

# Tracks which Inventory the cursor's stack came from, so we can return it
# on cancel and to disambiguate slot indices across grids.
var _cursor_source_inventory: Inventory = null
var _cursor_source_slot: int = -1

# Visual representation of the held stack — a TextureRect that follows the mouse.
@onready var cursor_visual: TextureRect = $CursorVisual


func _ready() -> void:
	add_to_group("inventory_panel")
	visible = false
	# Defer one frame to find the player (same pattern hotbar.gd uses)
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		push_error("InventoryPanel: no player found")
		return
	_inventory = player.inventory
	_build_slots()
	_render_all()
	# Refresh slots when inventory changes
	_inventory.slot_changed.connect(_on_slot_changed)
	_inventory.active_slot_changed.connect(_on_active_slot_changed)
	_inventory.capacity_changed.connect(_on_capacity_changed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory_toggle"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	
	if not _is_open:
		return  # other inputs only consumed while open
	
	if _cursor_stack != null and event is InputEventMouseButton \
			and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_drop_cursor_into_world()
		get_viewport().set_input_as_handled()
		return
	
	# Cancel — return cursor to source if held, then close
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	
	# Verb actions on the currently-selected slot
	if _selected_widget != null:
		if event.is_action_pressed("interact"):
			_handle_action(_selected_inventory, _selected_slot_index, HotbarSlot.Action.INTERACT)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("inventory_split"):
			_handle_action(_selected_inventory, _selected_slot_index, HotbarSlot.Action.SPLIT)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("inventory_transfer"):
			_handle_action(_selected_inventory, _selected_slot_index, HotbarSlot.Action.TRANSFER)
			get_viewport().set_input_as_handled()
	
	# Eat all other input while panel is open — prevents player movement, etc.
	# Anything not explicitly handled above also gets consumed.
	if event is InputEventKey or event is InputEventJoypadButton or event is InputEventJoypadMotion:
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	TimeSystem.pause()
	_render_all()
	_apply_active_highlight()


func close() -> void:
	if not _is_open:
		return
	# Return cursor item to source if any
	if _cursor_stack != null and _cursor_source_inventory != null:
		_cursor_source_inventory.slots[_cursor_source_slot] = _cursor_stack
		_cursor_source_inventory.slot_changed.emit(_cursor_source_slot)
		_clear_cursor()
	# Notify the container so it can update its open/closed visual.
	if _viewing_container != null:
		if _viewing_container.storage.slot_changed.is_connected(_on_storage_slot_changed):
			_viewing_container.storage.slot_changed.disconnect(_on_storage_slot_changed)
		_viewing_container.notify_panel_closed()
		_viewing_container = null
	storage_title.visible = false
	storage_grid.visible = false
	# Clear storage widgets
	for w in _storage_widgets:
		w.queue_free()
	_storage_widgets.clear()
	_is_open = false
	visible = false
	TimeSystem.resume()


func _build_slots() -> void:
	# Clear any existing
	for c in hotbar_row.get_children():
		c.queue_free()
	for c in backpack_grid.get_children():
		c.queue_free()
	_slot_widgets.clear()
	_slot_widgets.resize(_inventory.max_slots)
	
	# Build hotbar row (slots 0..11)
	for i in range(min(HOTBAR_SLOT_COUNT, _inventory.max_slots)):
		var slot := SLOT_SCENE.instantiate()
		slot.slot_index = i
		hotbar_row.add_child(slot)
		_slot_widgets[i] = slot
		slot.hover_entered.connect(_on_player_slot_hovered)
		slot.clicked.connect(_on_slot_clicked.bind(_inventory))


	# Build backpack grid (slots 12..max)
	for i in range(HOTBAR_SLOT_COUNT, _inventory.max_slots):
		var slot := SLOT_SCENE.instantiate()
		slot.slot_index = i
		backpack_grid.add_child(slot)
		_slot_widgets[i] = slot
		slot.hover_entered.connect(_on_player_slot_hovered)
		slot.clicked.connect(_on_slot_clicked.bind(_inventory))


func _render_all() -> void:
	for i in range(_slot_widgets.size()):
		if _slot_widgets[i] != null:
			_slot_widgets[i].render(_inventory.get_slot(i))


func _on_slot_changed(slot_index: int) -> void:
	if slot_index >= 0 and slot_index < _slot_widgets.size():
		_slot_widgets[slot_index].render(_inventory.get_slot(slot_index))


func _on_active_slot_changed(_slot_index: int) -> void:
	_apply_active_highlight()

func _on_capacity_changed(_new_max: int) -> void:
	_build_slots()
	_render_all()
	if _is_open:
		_apply_active_highlight()

func _on_player_slot_hovered(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _slot_widgets.size():
		return
	_set_selection(_inventory, slot_index, _slot_widgets[slot_index])
	
func _on_storage_slot_hovered(slot_index: int) -> void:
	if _viewing_container == null:
		return
	if slot_index < 0 or slot_index >= _storage_widgets.size():
		return
	_set_selection(_viewing_container.storage, slot_index, _storage_widgets[slot_index])
	
func _set_selection(inv: Inventory, slot_index: int, widget: HotbarSlot) -> void:
	if _selected_widget != null:
		_selected_widget.set_hovered(false)
	_selected_widget = widget
	_selected_inventory = inv
	_selected_slot_index = slot_index
	widget.set_hovered(true)

func _on_slot_clicked(slot_index: int, action: int, inv: Inventory) -> void:
	_handle_action(inv, slot_index, action)
	
func _handle_action(inv: Inventory, slot_index: int, action: int) -> void:
	match action:
		HotbarSlot.Action.INTERACT:
			_handle_interact(inv, slot_index)
		HotbarSlot.Action.SPLIT:
			_handle_split(inv, slot_index)
		HotbarSlot.Action.TRANSFER:
			var other: Inventory = _other_inventory(inv)
			if other != null:
				_handle_transfer(inv, slot_index, other)
		HotbarSlot.Action.MOVE_ONE:
			_handle_move_one_pickup(inv, slot_index)


func _other_inventory(inv: Inventory) -> Inventory:
	if _viewing_container == null:
		return null
	if inv == _inventory:
		return _viewing_container.storage
	return _inventory

func _apply_active_highlight() -> void:
	var active_world_slot: int = _inventory.active_world_slot()
	for i in range(_slot_widgets.size()):
		if _slot_widgets[i] == null:
			continue
		_slot_widgets[i].set_active(i == active_world_slot)

func open_with_container(container: StorageContainer) -> void:
	# In open_with_container, after _build_storage_slots:
	container.storage.slot_changed.connect(_on_storage_slot_changed)
	_viewing_container = container
	_build_storage_slots()
	_render_storage_all()
	storage_title.visible = true
	storage_grid.visible = true
	open()  # opens the player inventory side too

func _build_storage_slots() -> void:
	for c in storage_grid.get_children():
		c.queue_free()
	_storage_widgets.clear()
	if _viewing_container == null:
		return
	for i in range(_viewing_container.storage.max_slots):
		var slot := SLOT_SCENE.instantiate()
		slot.slot_index = i
		storage_grid.add_child(slot)
		_storage_widgets.append(slot)
		slot.clicked.connect(_on_slot_clicked.bind(_viewing_container.storage))
		slot.hover_entered.connect(_on_storage_slot_hovered)

func _render_storage_all() -> void:
	if _viewing_container == null:
		return
	for i in range(_storage_widgets.size()):
		_storage_widgets[i].render(_viewing_container.storage.get_slot(i))
		
func _on_storage_slot_changed(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= _storage_widgets.size():
		return
	_storage_widgets[slot_index].render(_viewing_container.storage.get_slot(slot_index))


# Core pickup-place-swap logic.
func _handle_interact(inv: Inventory, slot_index: int) -> void:
	var slot_stack: ItemStack = inv.get_slot(slot_index)

	if _cursor_stack == null:
		# Cursor empty → pick up the slot's contents (if any)
		if slot_stack == null:
			return  # clicked empty slot with nothing held; do nothing
		_cursor_stack = slot_stack
		_cursor_source_inventory = inv
		_cursor_source_slot = slot_index
		inv.slots[slot_index] = null
		inv.slot_changed.emit(slot_index)
		_update_cursor_visual()
	else:
		# Cursor has something → place / stack / swap
		if slot_stack == null:
			# Empty slot: place
			inv.slots[slot_index] = _cursor_stack
			inv.slot_changed.emit(slot_index)
			_clear_cursor()
		elif slot_stack.item == _cursor_stack.item:
			# Same item: stack as much as possible
			var space := slot_stack.space_remaining()
			var to_move: int = min(space, _cursor_stack.count)
			slot_stack.count += to_move
			_cursor_stack.count -= to_move
			inv.slot_changed.emit(slot_index)
			if _cursor_stack.count <= 0:
				_clear_cursor()
			else:
				_update_cursor_visual()
		else:
			# Different item: swap
			inv.slots[slot_index] = _cursor_stack
			_cursor_stack = slot_stack
			# source is now whichever slot we just clicked
			_cursor_source_inventory = inv
			_cursor_source_slot = slot_index
			inv.slot_changed.emit(slot_index)
			_update_cursor_visual()


# Shift+click: transfer the whole stack to the other inventory.
func _handle_transfer(from_inv: Inventory, slot_index: int, to_inv: Inventory) -> void:
	if to_inv == null or _cursor_stack != null:
		return  # no target, or cursor in use
	var stack: ItemStack = from_inv.get_slot(slot_index)
	if stack == null:
		return
	var leftover := to_inv.add(stack.item, stack.count)
	if leftover < stack.count:
		# Some moved; remove what was taken
		from_inv.consume_from_slot(slot_index, stack.count - leftover)
	# If leftover > 0, partial transfer; the source still has the leftover.

func _handle_split(inv: Inventory, slot_index: int) -> void:
	# If cursor is empty, split the slot's stack in half — cursor takes ceil(half).
	# If cursor holds something, drop one of the held stack into the slot.
	var slot_stack := inv.get_slot(slot_index)
	
	if _cursor_stack == null:
		if slot_stack == null or slot_stack.count <= 1:
			return  # nothing to split
		var taken: int = (slot_stack.count + 1) / 2  # ceil(half)
		_cursor_stack = ItemStack.new(slot_stack.item, taken)
		_cursor_source_inventory = inv
		_cursor_source_slot = slot_index
		slot_stack.count -= taken
		if slot_stack.count <= 0:
			inv.slots[slot_index] = null
		inv.slot_changed.emit(slot_index)
		_update_cursor_visual()
	else:
		# Drop one onto the slot
		if slot_stack == null:
			inv.slots[slot_index] = ItemStack.new(_cursor_stack.item,_cursor_stack.count)
			_cursor_stack.count -= 1
			inv.slot_changed.emit(slot_index)
		elif slot_stack.item == _cursor_stack.item and not slot_stack.is_full():
			slot_stack.count += 1
			_cursor_stack.count -= 1
			inv.slot_changed.emit(slot_index)
		# else: different item or full slot → no-op
		if _cursor_stack.count <= 0:
			_clear_cursor()
		else:
			_update_cursor_visual()
			
func _handle_move_one_pickup(inv: Inventory, slot_index: int) -> void:
	var slot_stack := inv.get_slot(slot_index)
	
	if _cursor_stack == null:
		if slot_stack == null:
			return
		_cursor_stack = ItemStack.new(slot_stack.item, 1)
		_cursor_source_inventory = inv
		_cursor_source_slot = slot_index
		slot_stack.count -= 1
		if slot_stack.count <= 0:
			inv.slots[slot_index] = null
		inv.slot_changed.emit(slot_index)
		_update_cursor_visual()
	else:
		# Drop one onto the slot (same as split's drop branch).
		if slot_stack == null:
			inv.slots[slot_index] = ItemStack.new(_cursor_stack.item, 1)
			_cursor_stack.count -= 1
			inv.slot_changed.emit(slot_index)
		elif slot_stack.item == _cursor_stack.item and not slot_stack.is_full():
			slot_stack.count += 1
			_cursor_stack.count -= 1
			inv.slot_changed.emit(slot_index)
		# else: different item, full slot — no-op (don't swap on a single click)
		if _cursor_stack.count <= 0:
			_clear_cursor()
		else:
			_update_cursor_visual()

func _drop_cursor_into_world() -> void:
	if _cursor_stack == null or _cursor_stack.item == null:
		return
	var player := get_tree().get_first_node_in_group("player")
	var room := RoomManager.current_room
	if player == null or room == null:
		return

	var dropped_item: ItemDef = _cursor_stack.item
	var dropped_count: int = _cursor_stack.count

	var drop := DROPPED_ITEM_SCENE.instantiate()
	var jitter := Vector2(randf_range(-8.0, 8.0), randf_range(-8.0, 8.0))
	var parent: Node = room.get_node_or_null("DroppedItems")
	if parent == null:
		parent = room
	parent.add_child(drop)
	drop.global_position = player.global_position + jitter
	drop.setup(dropped_item, dropped_count)

	var area_id := StringName(room.scene_file_path.get_file().get_basename())
	CrimeSystem.report_timed_crime(&"littering", player.global_position, area_id, 3.0)

	_clear_cursor()
	NotificationSystem.info("Dropped %d %s." % [dropped_count, dropped_item.display_name])

func _clear_cursor() -> void:
	_cursor_stack = null
	_cursor_source_inventory = null
	_cursor_source_slot = -1
	cursor_visual.visible = false


func _update_cursor_visual() -> void:
	if _cursor_stack == null or _cursor_stack.item == null:
		cursor_visual.visible = false
		return
	cursor_visual.texture = _cursor_stack.item.icon
	cursor_visual.visible = true


func _process(_delta: float) -> void:
	if _cursor_stack != null:
		# Follow mouse
		cursor_visual.global_position = get_global_mouse_position() - cursor_visual.size / 2
