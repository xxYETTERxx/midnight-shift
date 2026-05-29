class_name VendorInteractable
extends Node2D

# === Identity ===

# Stable id used for debt tracking, save state, dialogue keying.
# Required for save/load to work — must be unique across all vendors.
@export var vendor_id: StringName = &""

# Display name shown in the panel header.
@export var vendor_name: String = "Vendor"


# === Pricing ===

# Multiplier applied to base_value when the player BUYS from this vendor.
@export_range(0.0, 5.0, 0.05) var buy_multiplier: float = 1.0

# Multiplier applied to base_value when the vendor BUYS from the player.
# 0.0 = vendor won't buy anything.
@export_range(0.0, 5.0, 0.05) var sell_multiplier: float = 0.0


# === Inventory ===

@export var stock_size: int = 24
@export var initial_stock: Array[ItemDef] = []
@export var initial_stock_counts: Array[int] = []

@export var gated_stock: Array[ItemDef] = []
@export var gated_stock_counts: Array[int] = []
@export var gated_stock_min_tier: Array[int] = []


# === Buy filter ===

# What this vendor will buy from the player. Semantics:
#   sell_multiplier <= 0      -> buys nothing (filter ignored)
#   list empty                -> buys all sellable items (generalist)
#   list populated            -> buys only items in the list
@export var will_buy_items: Array[ItemDef] = []


# === Daily cash budget ===

# Max cash the vendor can spend on the player per day.
# 0 = unlimited. Resets to this value on TimeSystem.day_rolled.
@export var daily_buy_budget: int = 0


# === Restock ===

# If true, stock is wiped and refilled from initial_stock each morning.
# If false, stock only refills when fully empty (legacy behavior).
@export var restock_on_day_rolled: bool = true


# === Front (debt-based) offer ===

# When offers_front == true, the panel shows a "Take Front" action that
# gives the player front_offer_item x front_offer_count and incurs a debt
# of front_offer_debt dollars (snapshotted at front time).
@export var offers_front: bool = false
@export var front_offer_item: ItemDef
@export var front_offer_count: int = 1
@export var front_offer_debt: int = 0


# === Runtime ===

var _remaining_buy_budget: int = 0

@onready var interactable: Interactable = $Interactable
@onready var stock: Inventory = $Stock


func _ready() -> void:
	stock.max_slots = stock_size
	stock.slots.clear()
	stock.slots.resize(stock_size)
	interactable.interacted.connect(_on_interacted)
	_remaining_buy_budget = daily_buy_budget
	TimeSystem.day_rolled.connect(_on_day_rolled)

	if vendor_id == &"":
		push_warning("VendorInteractable '%s' has empty vendor_id -- persistence disabled" % vendor_name)
		_populate_initial_stock()
		return

	# Rehydrate same-day state if the store has it; otherwise fresh stock.
	if VendorStateStore.has_state(vendor_id):
		load_state(VendorStateStore.fetch(vendor_id))
	else:
		_populate_initial_stock()

func _exit_tree() -> void:
	# Stash current state centrally so leaving the scene doesn't lose
	# today's stock/budget, and so we're not a dangling SaveSystem entry.
	if vendor_id != &"":
		VendorStateStore.store(vendor_id, save_state())

func _on_interacted(player: Node) -> void:
	var panel := get_tree().get_first_node_in_group("vendor_panel")
	if panel == null:
		push_warning("VendorInteractable: no vendor_panel found in scene")
		return
	panel.open_with_vendor(self, player)


# === Public API: player buys from vendor ===

# Quote how much it would COST the player to buy `count` of `item` here.
func quote_buy_from_vendor(item: ItemDef, count: int) -> int:
	if item == null or count <= 0:
		return 0
	return int(round(item.base_value * buy_multiplier)) * count


# === Public API: vendor buys from player ===

# Does this vendor accept this item type at all?
# Independent of budget -- yes/no based on filter alone.
func will_buy(item: ItemDef) -> bool:
	if item == null:
		return false
	if not item.sellable:
		return false
	if sell_multiplier <= 0:
		return false
	if will_buy_items.is_empty():
		return true  # generalist
	return item in will_buy_items


# Quote how much this vendor would PAY for `count` of `item`.
# Returns 0 if the vendor doesn't accept this item type.
# Does NOT clamp to remaining budget -- callers check that via can_pay().
func quote_sell_to_vendor(item: ItemDef, count: int) -> int:
	if not will_buy(item) or count <= 0:
		return 0
	return int(round(item.base_value * sell_multiplier)) * count


# Does this vendor enforce a daily cash budget?
func has_buy_budget() -> bool:
	return daily_buy_budget > 0


# How much cash this vendor has left to spend today.
# For unlimited-budget vendors returns 0 -- pair with has_buy_budget().
func remaining_buy_budget() -> int:
	if not has_buy_budget():
		return 0
	return _remaining_buy_budget


# Can this vendor afford to pay `amount` right now?
# Always true for unlimited-budget vendors.
func can_pay(amount: int) -> bool:
	if amount <= 0:
		return true
	if not has_buy_budget():
		return true
	return amount <= _remaining_buy_budget


# Called by vendor_panel on confirm to deduct from today's budget.
# No-op for unlimited-budget vendors.
func record_purchase(amount: int) -> void:
	if not has_buy_budget() or amount <= 0:
		return
	_remaining_buy_budget = max(0, _remaining_buy_budget - amount)


# === Front offers ===

func has_valid_front_offer() -> bool:
	return offers_front \
		and front_offer_item != null \
		and front_offer_count > 0 \
		and front_offer_debt > 0


# === Day rollover ===

func _on_day_rolled(_dow: int, _dom: int) -> void:
	_remaining_buy_budget = daily_buy_budget
	if restock_on_day_rolled:
		_restock()
	if vendor_id != &"":
		VendorStateStore.store(vendor_id, save_state())  # persist the restocked state


func _restock() -> void:
	_clear_stock()
	_populate_initial_stock(true)


# === Internals ===

func _populate_initial_stock(force: bool = false) -> void:
	# By default only fills when empty (preserves in-session changes).
	# Pass force=true to refill regardless (used by daily restock).
	if not force and not _stock_is_empty():
		return

	for i in range(initial_stock.size()):
		var item: ItemDef = initial_stock[i]
		var count: int = initial_stock_counts[i] if i < initial_stock_counts.size() else 1
		if item != null and count > 0:
			stock.add(item, count)

	_populate_gated_stock()


# Adds tier-gated items the player has unlocked. Called as part of stock
# population, so gated items appear/refresh on the same restock cadence as
# everything else.
func _populate_gated_stock() -> void:
	var tier: int = DealerExperience.current_tier()
	for i in range(gated_stock.size()):
		var item: ItemDef = gated_stock[i]
		if item == null:
			continue
		var min_tier: int = gated_stock_min_tier[i] if i < gated_stock_min_tier.size() else 0
		if tier < min_tier:
			continue
		var count: int = gated_stock_counts[i] if i < gated_stock_counts.size() else 1
		if count > 0:
			stock.add(item, count)


func _clear_stock() -> void:
	for i in range(stock.max_slots):
		var s := stock.get_slot(i)
		if s != null and s.count > 0:
			stock.consume_from_slot(i, s.count)


func _stock_is_empty() -> bool:
	for i in range(stock.max_slots):
		if stock.get_slot(i) != null:
			return false
	return true


# === Save / Load ===

func save_state() -> Dictionary:
	return {
		"stock": stock.save_state(),
		"remaining_buy_budget": _remaining_buy_budget,
	}


func load_state(data: Dictionary) -> void:
	if data.has("stock"):
		stock.load_state(data["stock"])
	_remaining_buy_budget = data.get("remaining_buy_budget", daily_buy_budget)
