extends Control

const SLOT_SCENE := preload("res://scenes/ui/hotbar_slot.tscn")

@onready var vendor_title: Label = $PanelContainer/VBoxContainer/VendorTitle
@onready var player_grid: GridContainer = $PanelContainer/VBoxContainer/PlayerGrid
@onready var vendor_grid: GridContainer = $PanelContainer/VBoxContainer/VendorGrid
@onready var net_label: Label = $PanelContainer/VBoxContainer/ButtonRow/NetLabel
@onready var balance_label: Label = $PanelContainer/VBoxContainer/InfoRow/BalanceLabel
@onready var confirm_button: Button = $PanelContainer/VBoxContainer/ButtonRow/ConfirmButton
@onready var cancel_button: Button = $PanelContainer/VBoxContainer/ButtonRow/CancelButton
@onready var price_label: Label = $PanelContainer/VBoxContainer/InfoRow/PriceLabel

var _is_open: bool = false
var _vendor: VendorInteractable = null
var _player_inv: Inventory = null

# Shadow inventories — full duplicates the player manipulates freely.
# On confirm we apply them to the real inventories; on cancel we discard.
var _player_shadow: Inventory = null
var _vendor_shadow: Inventory = null

# Snapshots taken at open, used to diff against shadows for net cash.
var _player_original: Dictionary = {}
var _vendor_original: Dictionary = {}

var _player_slot_widgets: Array = []
var _vendor_slot_widgets: Array = []


func _ready() -> void:
	add_to_group("vendor_panel")
	visible = false
	confirm_button.pressed.connect(_on_confirm)
	cancel_button.pressed.connect(_on_cancel)
	Wallet.balance_changed.connect(_on_wallet_changed)
	price_label.text = ""


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()


func open_with_vendor(vendor: VendorInteractable, player: Node) -> void:
	if _is_open:
		return
	_vendor = vendor
	_player_inv = player.inventory
	vendor_title.text = vendor.vendor_name

	_snapshot_originals()
	_build_shadows()
	_build_grids()
	_player_shadow.slot_changed.connect(_on_player_shadow_changed)
	_vendor_shadow.slot_changed.connect(_on_vendor_shadow_changed)
	_render_all()
	_update_net()
	_update_balance()

	_is_open = true
	visible = true
	TimeSystem.pause()


# --- Shadow setup ---

func _snapshot_originals() -> void:
	_player_original = _player_inv.save_state()
	_vendor_original = _vendor.stock.save_state()


func _build_shadows() -> void:
	_clear_shadows()

	_player_shadow = Inventory.new()
	_player_shadow.max_slots = _player_inv.max_slots
	add_child(_player_shadow)
	_player_shadow.load_state(_player_original)

	_vendor_shadow = Inventory.new()
	_vendor_shadow.max_slots = _vendor.stock.max_slots
	add_child(_vendor_shadow)
	_vendor_shadow.load_state(_vendor_original)


func _clear_shadows() -> void:
	if _player_shadow != null:
		_player_shadow.queue_free()
		_player_shadow = null
	if _vendor_shadow != null:
		_vendor_shadow.queue_free()
		_vendor_shadow = null


# --- Grid building ---

func _build_grids() -> void:
	for c in player_grid.get_children():
		c.queue_free()
	for c in vendor_grid.get_children():
		c.queue_free()
	_player_slot_widgets.clear()
	_vendor_slot_widgets.clear()

	for i in range(_player_shadow.max_slots):
		var slot := SLOT_SCENE.instantiate()
		slot.slot_index = i
		player_grid.add_child(slot)
		_player_slot_widgets.append(slot)
		slot.clicked.connect(_on_player_slot_clicked)
		slot.hovered.connect(_on_player_slot_hovered)
		slot.unhovered.connect(_on_slot_unhovered)

	for i in range(_vendor_shadow.max_slots):
		var slot := SLOT_SCENE.instantiate()
		slot.slot_index = i
		vendor_grid.add_child(slot)
		_vendor_slot_widgets.append(slot)
		slot.clicked.connect(_on_vendor_slot_clicked)
		slot.hovered.connect(_on_vendor_slot_hovered)
		slot.unhovered.connect(_on_slot_unhovered)


func _render_all() -> void:
	for i in range(_player_slot_widgets.size()):
		_player_slot_widgets[i].render(_player_shadow.get_slot(i))
	for i in range(_vendor_slot_widgets.size()):
		_vendor_slot_widgets[i].render(_vendor_shadow.get_slot(i))


# --- Slot interaction ---

func _on_player_shadow_changed(i: int) -> void:
	if i < _player_slot_widgets.size():
		_player_slot_widgets[i].render(_player_shadow.get_slot(i))
	_update_net()


func _on_vendor_shadow_changed(i: int) -> void:
	if i < _vendor_slot_widgets.size():
		_vendor_slot_widgets[i].render(_vendor_shadow.get_slot(i))
	_update_net()


# Click on a player-side slot → stage a sell (move stack to vendor shadow).
func _on_player_slot_clicked(slot_index: int, action: int) -> void:
	var stack := _player_shadow.get_slot(slot_index)
	if stack == null or stack.item == null:
		return
	if not stack.item.sellable:
		return
	var to_move: int = 1 if action == HotbarSlot.Action.MOVE_ONE else stack.count
	var leftover := _vendor_shadow.add(stack.item, to_move)
	var moved: int = to_move - leftover
	if moved > 0:
		_player_shadow.consume_from_slot(slot_index, moved)


# Click on a vendor-side slot → stage a buy (move stack to player shadow).
func _on_vendor_slot_clicked(slot_index: int, action: int) -> void:
	var stack := _vendor_shadow.get_slot(slot_index)
	if stack == null or stack.item == null:
		return
	var to_move: int = 1 if action == HotbarSlot.Action.MOVE_ONE else stack.count
	var leftover := _player_shadow.add(stack.item, to_move)
	var moved: int = to_move - leftover
	if moved > 0:
		_vendor_shadow.consume_from_slot(slot_index, moved)

func _on_player_slot_hovered(slot_index: int) -> void:
	var stack := _player_shadow.get_slot(slot_index)
	if stack == null or stack.item == null:
		price_label.text = ""
		return
	if not stack.item.sellable or _vendor.sell_multiplier <= 0:
		price_label.text = "%s — won't buy" % stack.item.display_name
		return
	var unit_price := _vendor.quote_sell_to_vendor(stack.item, 1)
	price_label.text = "%s — sells for $%d" % [stack.item.display_name, unit_price]


func _on_vendor_slot_hovered(slot_index: int) -> void:
	var stack := _vendor_shadow.get_slot(slot_index)
	if stack == null or stack.item == null:
		price_label.text = ""
		return
	var unit_price := _vendor.quote_buy_from_vendor(stack.item, 1)
	price_label.text = "%s — costs $%d" % [stack.item.display_name, unit_price]


func _on_slot_unhovered(_slot_index: int) -> void:
	price_label.text = ""


# --- Net calculation ---

func _compute_net() -> int:
	var player_now := _player_shadow.save_state()
	var player_lost := _diff_counts(_player_original, player_now)   # sold
	var player_gained := _diff_counts(player_now, _player_original) # bought

	var revenue := 0
	for item_id in player_lost:
		var item := ItemRegistry.get_item(StringName(item_id))
		if item == null:
			continue
		revenue += _vendor.quote_sell_to_vendor(item, player_lost[item_id])

	var cost := 0
	for item_id in player_gained:
		var item := ItemRegistry.get_item(StringName(item_id))
		if item == null:
			continue
		cost += _vendor.quote_buy_from_vendor(item, player_gained[item_id])

	return revenue - cost


# Returns {item_id: positive_delta} where delta = a_counts[id] - b_counts[id].
func _diff_counts(a_state: Dictionary, b_state: Dictionary) -> Dictionary:
	var a_counts := _count_items(a_state)
	var b_counts := _count_items(b_state)
	var result := {}
	for id in a_counts:
		var diff: int = a_counts[id] - b_counts.get(id, 0)
		if diff > 0:
			result[id] = diff
	return result


func _count_items(inv_state: Dictionary) -> Dictionary:
	var result := {}
	var slot_data: Array = inv_state.get("slots", [])
	for entry in slot_data:
		if entry == null:
			continue
		var id: String = entry.get("id", "")
		var count: int = entry.get("count", 0)
		if id == "" or count <= 0:
			continue
		result[id] = result.get(id, 0) + count
	return result


# --- Display ---

func _update_net() -> void:
	var net := _compute_net()
	if net > 0:
		net_label.text = "Net: +$%d" % net
		net_label.modulate = Color(0.6, 1.0, 0.6)
	elif net < 0:
		net_label.text = "Net: -$%d" % -net
		net_label.modulate = Color(1.0, 0.6, 0.6) if Wallet.can_afford(-net) else Color(1.0, 0.3, 0.3)
	else:
		net_label.text = "Net: $0"
		net_label.modulate = Color.WHITE
	confirm_button.disabled = (net < 0 and not Wallet.can_afford(-net))


func _update_balance() -> void:
	balance_label.text = "Cash: %s" % Wallet.format_balance()


func _on_wallet_changed(_pool: String, _new_balance: int) -> void:
	if _is_open:
		_update_balance()
		_update_net()


# --- Confirm / Cancel ---

func _on_confirm() -> void:
	var net := _compute_net()
	if net < 0 and not Wallet.can_afford(-net):
		return
	if net > 0:
		Wallet.add(net)
	elif net < 0:
		Wallet.spend(-net)
	_player_inv.load_state(_player_shadow.save_state())
	_vendor.stock.load_state(_vendor_shadow.save_state())
	_close()


func _on_cancel() -> void:
	_close()


func _close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	_clear_shadows()
	_vendor = null
	_player_inv = null
	TimeSystem.resume()
