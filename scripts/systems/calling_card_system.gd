extends Node

# CallingCardSystem — central API for spending calling card minutes.
#
# Cards live in the player's inventory as ItemStacks of CallingCardDef items
# with {"minutes": N} per-stack data. This system finds the right card to
# spend from and handles depletion / out-of-minutes notifications.
#
# Selection policy: lowest-minutes card that still covers the cost. Keeps
# bigger cards intact and burns near-empty ones first.

signal minutes_changed(total: int)
signal card_depleted()


func _player_inventory() -> Inventory:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return null
	return player.inventory


# Attempt to spend `cost` minutes. Returns true on success, false if no
# single card has enough. Caller should not proceed if false.
func try_spend(cost: int) -> bool:
	if cost <= 0:
		return true
	var inv := _player_inventory()
	if inv == null:
		return false
	var slot_idx := _find_best_card(inv, cost)
	if slot_idx < 0:
		NotificationSystem.warn("Need more minutes — buy a card at the bodega.")
		return false
	var stack := inv.get_slot(slot_idx)
	stack.data["minutes"] = int(stack.data.get("minutes", 0)) - cost
	if int(stack.data["minutes"]) <= 0:
		inv.slots[slot_idx] = null
		NotificationSystem.info("Card used up.")
		card_depleted.emit()
	inv.slot_changed.emit(slot_idx)
	minutes_changed.emit(total_minutes())
	return true


# Total minutes across all cards. For HUD display.
func total_minutes() -> int:
	var inv := _player_inventory()
	if inv == null:
		return 0
	var total := 0
	for stack in inv.slots:
		if stack != null and stack.item is CallingCardDef:
			total += int(stack.data.get("minutes", 0))
	return total


func card_count() -> int:
	var inv := _player_inventory()
	if inv == null:
		return 0
	var n := 0
	for stack in inv.slots:
		if stack != null and stack.item is CallingCardDef:
			n += 1
	return n


# Find the calling card with the lowest remaining minutes that's still >= cost.
# -1 if no card qualifies.
func _find_best_card(inv: Inventory, cost: int) -> int:
	var best_idx := -1
	var best_minutes := -1
	for i in range(inv.slots.size()):
		var stack: ItemStack = inv.slots[i]
		if stack == null or not (stack.item is CallingCardDef):
			continue
		var m: int = int(stack.data.get("minutes", 0))
		if m < cost:
			continue
		if best_idx < 0 or m < best_minutes:
			best_idx = i
			best_minutes = m
	return best_idx
