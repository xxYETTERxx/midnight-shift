class_name Inventory
extends Node

@export var max_slots: int = 12
@export var initial_slots: int = 12  # currently unlocked slots

# Array of ItemStack-or-null, length == max_slots.
var slots: Array = []
var active_slot: int = 0

# Emitted when a specific slot's contents changed.
signal slot_changed(slot_index: int)

# Emitted when the active hotbar selection changes.
signal active_slot_changed(slot_index: int)


func _ready() -> void:
	# Initialize all slots to null
	slots.resize(max_slots)
	for i in range(max_slots):
		slots[i] = null


# --- Querying ---

func get_slot(slot: int) -> ItemStack:
	if slot < 0 or slot >= slots.size():
		return null
	return slots[slot]


func get_active_stack() -> ItemStack:
	return get_slot(active_slot)


func is_full() -> bool:
	# True if no slot can accept any more of any item.
	for stack in slots:
		if stack == null:
			return false
		if not stack.is_full():
			return false
	return true


# --- Adding items ---

# Tries to add `count` copies of `item` to the inventory.
# Returns the number that COULD NOT fit (0 = all added successfully).
func add(item: ItemDef, count: int) -> int:
	var remaining := count
	# Pass 1: merge into existing stacks of the same item
	for i in range(slots.size()):
		if remaining <= 0:
			break
		var stack: ItemStack = slots[i]
		if stack == null or stack.item != item:
			continue
		var space := stack.space_remaining()
		if space <= 0:
			continue
		var to_add: int = min(space, remaining)
		stack.count += to_add
		remaining -= to_add
		slot_changed.emit(i)
	# Pass 2: place overflow into empty slots
	for i in range(slots.size()):
		if remaining <= 0:
			break
		if slots[i] != null:
			continue
		var to_add: int = min(item.max_stack, remaining)
		slots[i] = ItemStack.new(item, to_add)
		remaining -= to_add
		slot_changed.emit(i)
	return remaining


# --- Removing items ---

# Decrements the stack at `slot` by 1 (or `count`).
# If it hits 0, the slot becomes null.
# Returns true if the requested count was removed.
func consume_from_slot(slot: int, count: int = 1) -> bool:
	var stack: ItemStack = get_slot(slot)
	if stack == null or stack.count < count:
		return false
	stack.count -= count
	if stack.count <= 0:
		slots[slot] = null
	slot_changed.emit(slot)
	return true


# Active-slot convenience: consume one of whatever is held.
func consume_active(count: int = 1) -> bool:
	return consume_from_slot(active_slot, count)


# --- Hotbar selection ---

func set_active_slot(slot: int) -> void:
	if slot < 0 or slot >= max_slots:
		return
	if slot == active_slot:
		return
	active_slot = slot
	active_slot_changed.emit(active_slot)


func cycle_active_slot(direction: int) -> void:
	# direction: +1 = next, -1 = previous. Wraps around.
	var new_slot := (active_slot + direction) % max_slots
	if new_slot < 0:
		new_slot += max_slots
	set_active_slot(new_slot)


# --- Slot management (for future drag-drop) ---

func swap_slots(a: int, b: int) -> void:
	if a < 0 or a >= max_slots or b < 0 or b >= max_slots:
		return
	if a == b:
		return
	var tmp = slots[a]
	slots[a] = slots[b]
	slots[b] = tmp
	slot_changed.emit(a)
	slot_changed.emit(b)


# --- Saving ---

func save_state() -> Dictionary:
	var slot_data: Array = []
	for stack in slots:
		if stack == null:
			slot_data.append(null)
		else:
			slot_data.append(stack.to_dict())
	return {
		"slots": slot_data,
		"active_slot": active_slot,
		"max_slots": max_slots,
	}


func load_state(data: Dictionary) -> void:
	max_slots = data.get("max_slots", 12)
	slots.resize(max_slots)
	var saved_slots: Array = data.get("slots", [])
	for i in range(max_slots):
		if i < saved_slots.size() and saved_slots[i] != null:
			slots[i] = ItemStack.from_dict(saved_slots[i])
		else:
			slots[i] = null
		slot_changed.emit(i)
	active_slot = data.get("active_slot", 0)
	active_slot_changed.emit(active_slot)
