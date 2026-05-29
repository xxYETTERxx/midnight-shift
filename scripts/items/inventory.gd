class_name Inventory
extends Node

@export var max_slots: int = 6
@export var initial_slots: int = 6  # currently unused, kept for compatibility



const HOTBAR_SLOT_COUNT: int = 12
var hotbar_offset: int = 0  # 0 = first row is hotbar, 12 = second row is hotbar

signal hotbar_offset_changed(offset: int)

# Array of ItemStack-or-null, length == max_slots.
var slots: Array = []
var active_slot: int = 0

# Emitted when a specific slot's contents changed.
signal slot_changed(slot_index: int)

# Emitted when the active hotbar selection changes.
signal active_slot_changed(slot_index: int)

signal capacity_changed(new_max: int)


func _ready() -> void:
	# Reconcile starting size against earned strength progression. Handles
	# the case where the player loads into the scene after their strength
	# level should have already granted more slots (signal won't re-fire
	# retroactively).
	var expected: int = PlayerSkills.inventory_slot_count()
	if expected > max_slots:
		max_slots = expected
	slots.resize(max_slots)
	for i in range(max_slots):
		slots[i] = null
	PlayerSkills.level_up.connect(_on_skill_level_up)


# --- Querying ---

func get_slot(slot: int) -> ItemStack:
	if slot < 0 or slot >= slots.size():
		return null
	return slots[slot]


func get_active_stack() -> ItemStack:
	return get_slot(active_world_slot())

func has_item(item_id: StringName) -> bool:
	for stack in slots:
		if stack != null and stack.item != null and stack.item.id == item_id:
			return true
	return false

func is_full() -> bool:
	# True if no slot can accept any more of any item.
	for stack in slots:
		if stack == null:
			return false
		if not stack.is_full():
			return false
	return true
	
func get_size() -> int:
	return max_slots


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
		slots[i] = ItemStack.new(item, to_add, item.initial_stack_data())
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
	return consume_from_slot(active_world_slot(), count)


# --- Hotbar selection ---

func set_active_slot(slot: int) -> void:
	if slot < 0 or slot >= HOTBAR_SLOT_COUNT:
		return
	if slot == active_slot:
		return
	active_slot = slot
	active_slot_changed.emit(active_slot)


func cycle_active_slot(direction: int) -> void:
	# direction: +1 = next, -1 = previous. Wraps around.
	var new_slot := (active_slot + direction) % HOTBAR_SLOT_COUNT
	if new_slot < 0:
		new_slot += HOTBAR_SLOT_COUNT
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

func cycle_hotbar_row() -> void:
	# Cycle through available rows.
	var rows: int = max_slots / HOTBAR_SLOT_COUNT  # integer division
	if rows <= 1:
		return
	hotbar_offset = (hotbar_offset + HOTBAR_SLOT_COUNT) % max_slots
	# active_slot is a 0-11 *within* the active row, so it stays as-is.
	# But the *effective* active slot in world terms changes — re-emit so listeners react.
	hotbar_offset_changed.emit(hotbar_offset)
	active_slot_changed.emit(active_slot)

func active_world_slot() -> int:
	return hotbar_offset + active_slot

func filled_slot_count() -> int:
	var count: int = 0
	for stack in slots:
		if stack != null:
			count += 1
	return count


func expand_slots(new_max: int) -> void:
	if new_max <= max_slots:
		return
	var old_max: int = max_slots
	max_slots = new_max
	slots.resize(max_slots)
	for i in range(old_max, max_slots):
		slots[i] = null
		slot_changed.emit(i)
	capacity_changed.emit(max_slots)


func _on_skill_level_up(skill_id: StringName, _new_level: int) -> void:
	if skill_id != &"strength":
		return
	var new_count: int = PlayerSkills.inventory_slot_count()
	if new_count > max_slots:
		expand_slots(new_count)


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
	# max_slots reconciles between saved size and PlayerSkills-derived size.
	# Larger wins so earned strength slots are never lost AND vendor/storage
	# inventories (which can be far larger than the player's) aren't clamped
	# to the player's carrying capacity.
	var saved_max: int = data.get("max_slots", 6)
	var expected: int = PlayerSkills.inventory_slot_count()
	max_slots = max(saved_max, expected)
	slots.resize(max_slots)
	var saved_slots: Array = data.get("slots", [])
	for i in range(max_slots):
		if i < saved_slots.size() and saved_slots[i] != null:
			slots[i] = ItemStack.from_dict(saved_slots[i])
		else:
			slots[i] = null
		slot_changed.emit(i)
	capacity_changed.emit(max_slots)
	active_slot = data.get("active_slot", 0)
	active_slot_changed.emit(active_slot)

func add_with_data(item: ItemDef, count: int, data: Dictionary) -> int:
	var remaining := count
	for i in range(slots.size()):
		if remaining <= 0:
			break
		if slots[i] != null:
			continue
		var to_add: int = min(item.max_stack, remaining)
		slots[i] = ItemStack.new(item, to_add, data.duplicate(true))
		remaining -= to_add
		slot_changed.emit(i)
	return remaining
	
