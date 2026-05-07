class_name VendorInteractable
extends Node2D

# Display name shown in the panel header.
@export var vendor_name: String = "Vendor"

# Multiplier applied to base_value when the player BUYS from this vendor.
# 1.0 = sells at base, 1.2 = 20% markup, etc.
@export_range(0.0, 5.0, 0.05) var buy_multiplier: float = 1.0

# Multiplier applied to base_value when the player SELLS to this vendor.
# 0.6 = wholesale (Fence), 1.0 = no margin loss, 2.0 = retail premium (pager).
@export_range(0.0, 5.0, 0.05) var sell_multiplier: float = 0.6

# Number of slots in the vendor's stock inventory.
@export var stock_size: int = 24

@onready var interactable: Interactable = $Interactable
@onready var stock: Inventory = $Stock


func _ready() -> void:
	stock.max_slots = stock_size
	interactable.interacted.connect(_on_interacted)


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
