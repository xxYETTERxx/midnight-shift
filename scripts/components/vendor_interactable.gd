class_name VendorInteractable
extends Node2D

# Stable id used for debt tracking, save state, dialogue keying.
@export var vendor_id: StringName = &""

# Display name shown in the panel header.
@export var vendor_name: String = "Vendor"

# Multiplier applied to base_value when the player BUYS from this vendor.
@export_range(0.0, 5.0, 0.05) var buy_multiplier: float = 1.0

# Multiplier applied to base_value when the player SELLS to this vendor.
@export_range(0.0, 5.0, 0.05) var sell_multiplier: float = 0.6

# Number of slots in the vendor's stock inventory.
@export var stock_size: int = 24

@onready var interactable: Interactable = $Interactable
@onready var stock: Inventory = $Stock

@export var initial_stock: Array[ItemDef] = []
@export var initial_stock_counts: Array[int] = []

# --- Front (debt-based) offer ---
# When offers_front == true, the panel shows a "Take Front" action that
# gives the player front_offer_item x front_offer_count and incurs a debt
# of front_offer_debt dollars (snapshotted at front time).
@export var offers_front: bool = false
@export var front_offer_item: ItemDef
@export var front_offer_count: int = 1
@export var front_offer_debt: int = 0


func _ready() -> void:
	stock.max_slots = stock_size
	stock.slots.clear()
	stock.slots.resize(stock_size)
	interactable.interacted.connect(_on_interacted)
	_populate_initial_stock()


func _on_interacted(player: Node) -> void:
	var panel := get_tree().get_first_node_in_group("vendor_panel")
	if panel == null:
		push_warning("VendorInteractable: no vendor_panel found in scene")
		return
	panel.open_with_vendor(self, player)


# Quote how much this vendor would PAY for `count` of `item`.
func quote_sell_to_vendor(item: ItemDef, count: int) -> int:
	if item == null or count <= 0 or not item.sellable:
		return 0
	return int(round(item.base_value * sell_multiplier)) * count


# Quote how much it would COST the player to buy `count` of `item` here.
func quote_buy_from_vendor(item: ItemDef, count: int) -> int:
	if item == null or count <= 0:
		return 0
	return int(round(item.base_value * buy_multiplier)) * count


func has_valid_front_offer() -> bool:
	return offers_front \
		and front_offer_item != null \
		and front_offer_count > 0 \
		and front_offer_debt > 0


func _populate_initial_stock() -> void:
	if initial_stock.is_empty():
		return
	if not _stock_is_empty():
		return
	for i in range(initial_stock.size()):
		var item: ItemDef = initial_stock[i]
		var count: int = initial_stock_counts[i] if i < initial_stock_counts.size() else 1
		if item != null and count > 0:
			stock.add(item, count)


func _stock_is_empty() -> bool:
	for i in range(stock.max_slots):
		if stock.get_slot(i) != null:
			return false
	return true
