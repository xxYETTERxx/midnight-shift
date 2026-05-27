extends Node

# Routes player collapse events (exhaustion, hunger zero, thirst zero) to a
# shared "lose stuff and wake up tomorrow at 16:00" flow. Per-cause penalties
# differ; the wake location and time are the same for now.

# IDs of items considered "drugs" — confiscated on hospital collapse.
const DRUG_ITEM_IDS: Array[StringName] = [&"weed_buds"]

# Apartment exterior wake position. Filled in once via set_wake_anchor() or
# pulled from the scene by group on collapse. For now, hardcoded fallback
# stays in WAKE_FALLBACK below — wire your actual anchor at boot.
const WAKE_ROOM_PATH: String = "res://scenes/rooms/city_central.tscn"
const WAKE_DOOR_GROUP: StringName = &"apartment_exterior_anchor"
const WAKE_FALLBACK: Vector2 = Vector2.ZERO

enum Cause { EXHAUSTION, HUNGER, THIRST }

signal collapsed(cause: int, summary: String)


func _ready() -> void:
	HungerSystem.collapsed.connect(_on_hunger_collapsed)
	ThirstSystem.collapsed.connect(_on_thirst_collapsed)
	StaminaSystem.collapsed.connect(_on_stamina_collapsed)


func _on_stamina_collapsed() -> void:
	_collapse(Cause.EXHAUSTION)

# --- Entry points -------------------------------------------------------


func _on_hunger_collapsed() -> void:
	_collapse(Cause.HUNGER)


func _on_thirst_collapsed() -> void:
	_collapse(Cause.THIRST)


# --- Core flow ---------------------------------------------------------

func _collapse(cause: int) -> void:
	var penalties: Array[String] = _apply_penalties(cause)
	var summary: String = _build_summary(cause, penalties)

	# Skip to tomorrow 16:00 — TimeSkipSystem handles fade + advance.
	TimeSkipSystem.skip_to(_next_wake_minute(), {
		"kind": "sleep",  # treated as sleep so survival decay halves
		"safe": false,
		"voluntary": false,
	})

	# After the skip resolves, place the player and restore stats.
	# skip_to runs synchronously through its own fade; by the time the
	# next line runs the world has advanced.
	_place_player_at_wake()
	_restore_post_collapse(cause)

	NotificationSystem.warn(summary)
	collapsed.emit(cause, summary)


# Tomorrow at 16:00 in total_minutes.
func _next_wake_minute() -> int:
	var minutes_per_day: int = 24 * 60
	var current: int = TimeSystem.total_minutes
	var days_passed: int = current / minutes_per_day
	return (days_passed + 1) * minutes_per_day + (16 * 60)


# --- Penalties ---------------------------------------------------------

func _apply_penalties(cause: int) -> Array[String]:
	var lost: Array[String] = []
	match cause:
		Cause.EXHAUSTION:
			var cash_taken: int = int(Wallet.balance("cash") * 0.10)
			if cash_taken > 0:
				Wallet.spend(cash_taken)
				lost.append("$%d" % cash_taken)
		Cause.HUNGER, Cause.THIRST:
			var cash_taken: int = int(Wallet.balance("cash") * 0.20)
			if cash_taken > 0:
				Wallet.spend(cash_taken)
				lost.append("$%d" % cash_taken)
			var drugs_lost: int = _confiscate_drugs()
			if drugs_lost > 0:
				lost.append("%dg of product" % drugs_lost)
	return lost


func _confiscate_drugs() -> int:
	var player := _get_player()
	if player == null:
		return 0
	var inv: Inventory = player.inventory
	var total: int = 0
	for id in DRUG_ITEM_IDS:
		for i in range(inv.max_slots):
			var stack: ItemStack = inv.get_slot(i)
			if stack == null or stack.item == null:
				continue
			if stack.item.id == id:
				total += stack.count
				inv.consume_from_slot(i, stack.count)
	return total


# --- Restore stats + position ------------------------------------------

func _restore_post_collapse(cause: int) -> void:
	var player := _get_player()
	if player == null:
		return

	match cause:
		Cause.EXHAUSTION:
			StaminaSystem.set_value(StaminaSystem.maximum() * 0.5)
		Cause.HUNGER, Cause.THIRST:
			# Hospital topped you up — full bars.
			StaminaSystem.set_value(StaminaSystem.maximum() * 0.5)
			HungerSystem.restore(HungerSystem.MAX_VALUE)
			ThirstSystem.restore(ThirstSystem.MAX_VALUE)


func _place_player_at_wake() -> void:
	var player := _get_player()
	if player == null:
		return

	# Move to the apartment exterior. If we're not already in that room,
	# change rooms; the room will need a node in WAKE_DOOR_GROUP to anchor.
	if RoomManager.current_room == null or RoomManager.current_room.scene_file_path != WAKE_ROOM_PATH:
		RoomManager.change_room(WAKE_ROOM_PATH, "default")

	var anchor: Node = get_tree().get_first_node_in_group(WAKE_DOOR_GROUP)
	var pos: Vector2 = anchor.global_position if anchor != null else WAKE_FALLBACK
	player.global_position = pos


func _get_player() -> Node:
	return get_tree().get_first_node_in_group("player")


# --- Summary text -------------------------------------------------------

func _build_summary(cause: int, lost: Array[String]) -> String:
	var prefix: String = ""
	match cause:
		Cause.EXHAUSTION:
			prefix = "Erik found you collapsed."
		Cause.HUNGER:
			prefix = "You collapsed from hunger. Woke up at the hospital."
		Cause.THIRST:
			prefix = "You collapsed from dehydration. Woke up at the hospital."

	if lost.is_empty():
		return prefix
	return "%s Lost: %s." % [prefix, ", ".join(lost)]
