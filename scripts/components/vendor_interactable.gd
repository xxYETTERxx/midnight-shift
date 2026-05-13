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

# If set, the vendor is only open when this NPC is materialized in the same
# room. Leave empty for vendors with no owner (vending machines, dead-drops,
# any "always on" interactable).
@export var vendor_owner: StringName = &""

@onready var interactable: Interactable = $Interactable
@onready var stock: Inventory = $Stock

@export var initial_stock: Array[ItemDef] = []
@export var initial_stock_counts: Array[int] = []


func _ready() -> void:
	stock.max_slots = stock_size
	interactable.interacted.connect(_on_interacted)
	_populate_initial_stock()

	if vendor_owner != &"":
		NPCDirector.npc_materialized.connect(_on_npc_presence_changed)
		NPCDirector.npc_despawned.connect(_on_npc_presence_changed)
		_refresh_open_state()


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


func _populate_initial_stock() -> void:
	if initial_stock.is_empty():
		return
	# Only populate if stock is empty — preserves in-session changes from purchases.
	# (For now, also populates on every load. Restock-on-day-rollover is a future tweak.)
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


# --- Owner gating -------------------------------------------------------

# Re-check open state when our owner spawns or despawns anywhere. We don't
# filter by which NPC — _refresh_open_state checks the live registry, so
# this just acts as a "something changed, look again" trigger.
func _on_npc_presence_changed(_npc_id: StringName) -> void:
	_refresh_open_state()


# Vendor is "open" if its owning NPC is currently materialized in the live
# registry. Since scheduled NPCs only materialize in the player's current
# room, presence in the registry implies presence in this room.
func _refresh_open_state() -> void:
	var owner_present: bool = NPCDirector.is_npc_present(vendor_owner)
	interactable.set_enabled(owner_present) if interactable.has_method("set_enabled") else _toggle_interactable(owner_present)


# Fallback if Interactable doesn't expose a clean enable API.
func _toggle_interactable(enabled: bool) -> void:
	interactable.visible = enabled
	interactable.set_process(enabled)
	interactable.set_physics_process(enabled)
	if interactable.has_node("CollisionShape2D"):
		interactable.get_node("CollisionShape2D").disabled = not enabled
