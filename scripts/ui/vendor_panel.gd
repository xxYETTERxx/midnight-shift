extends Control

const SLOT_SCENE := preload("res://scenes/ui/hotbar_slot.tscn")

enum Mode { NORMAL, FRONT_AVAILABLE, DEBT_OWED }

@onready var vendor_title: Label = $PanelContainer/VBoxContainer/VendorTitle
@onready var player_grid: GridContainer = $PanelContainer/VBoxContainer/PlayerGrid
@onready var vendor_grid: GridContainer = $PanelContainer/VBoxContainer/VendorGrid
@onready var info_row: Control = $PanelContainer/VBoxContainer/InfoRow
@onready var button_row: Control = $PanelContainer/VBoxContainer/ButtonRow
@onready var net_label: Label = $PanelContainer/VBoxContainer/ButtonRow/NetLabel
@onready var balance_label: Label = $PanelContainer/VBoxContainer/InfoRow/BalanceLabel
@onready var confirm_button: Button = $PanelContainer/VBoxContainer/ButtonRow/ConfirmButton
@onready var cancel_button: Button = $PanelContainer/VBoxContainer/ButtonRow/CancelButton
@onready var price_label: Label = $PanelContainer/VBoxContainer/InfoRow/PriceLabel

# --- Mode-specific UI nodes (added in vendor_panel.tscn) ---
@onready var front_offer_row: Control = $PanelContainer/VBoxContainer/FrontOfferRow
@onready var front_offer_label: Label = $PanelContainer/VBoxContainer/FrontOfferRow/FrontOfferLabel
@onready var front_offer_button: Button = $PanelContainer/VBoxContainer/FrontOfferRow/FrontOfferButton

@onready var debt_view: Control = $PanelContainer/VBoxContainer/DebtView
@onready var debt_amount_label: Label = $PanelContainer/VBoxContainer/DebtView/DebtAmountLabel
@onready var debt_pay_button: Button = $PanelContainer/VBoxContainer/DebtView/DebtPayButton

var _is_open: bool = false
var _mode: int = Mode.NORMAL
var _vendor: VendorInteractable = null
var _player_inv: Inventory = null

# Shadow inventories — only used in NORMAL / FRONT_AVAILABLE.
var _player_shadow: Inventory = null
var _vendor_shadow: Inventory = null
var _player_original: Dictionary = {}
var _vendor_original: Dictionary = {}

var _player_slot_widgets: Array = []
var _vendor_slot_widgets: Array = []


func _ready() -> void:
	add_to_group("vendor_panel")
	visible = false
	confirm_button.pressed.connect(_on_confirm)
	cancel_button.pressed.connect(_on_cancel)
	front_offer_button.pressed.connect(_on_take_front)
	debt_pay_button.pressed.connect(_on_pay_debt)
	Wallet.balance_changed.connect(_on_wallet_changed)
	DebtSystem.debt_changed.connect(_on_debt_changed)
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
	_mode = _decide_mode()
	_apply_mode()

	_is_open = true
	visible = true
	TimeSystem.pause()


# --- Mode selection ---

func _decide_mode() -> int:
	if DebtSystem.has_debt(_vendor.vendor_id):
		return Mode.DEBT_OWED
	if _vendor.has_valid_front_offer():
		return Mode.FRONT_AVAILABLE
	return Mode.NORMAL


func _apply_mode() -> void:
	match _mode:
		Mode.DEBT_OWED:
			_show_debt_view()
		Mode.FRONT_AVAILABLE:
			_show_trade_view(true)
		Mode.NORMAL:
			_show_trade_view(false)


func _show_debt_view() -> void:
	player_grid.visible = false
	vendor_grid.visible = false
	info_row.visible = false
	button_row.visible = false
	front_offer_row.visible = false
	debt_view.visible = true
	_refresh_debt_view()


func _show_trade_view(with_front_offer: bool) -> void:
	debt_view.visible = false
	player_grid.visible = true
	vendor_grid.visible = true
	info_row.visible = true
	button_row.visible = true
	front_offer_row.visible = with_front_offer
	if with_front_offer:
		_refresh_front_offer()
	_snapshot_originals()
	_build_shadows()
	_build_grids()
	_player_shadow.slot_changed.connect(_on_player_shadow_changed)
	_vendor_shadow.slot_changed.connect(_on_vendor_shadow_changed)
	_render_all()
	_update_net()
	_update_balance()


# --- Front offer ---

func _refresh_front_offer() -> void:
	var item: ItemDef = _vendor.front_offer_item
	var count: int = _vendor.front_offer_count
	var debt: int = _vendor.front_offer_debt
	front_offer_label.text = "Front: %s x%d  (owe $%d)" % [item.display_name, count, debt]
	front_offer_button.text = "Take Front"


func _on_take_front() -> void:
	if _vendor == null or not _vendor.has_valid_front_offer():
		return
	if DebtSystem.has_debt(_vendor.vendor_id):
		return  # shouldn't happen — mode wouldn't be FRONT_AVAILABLE — defensive

	# Try to add to REAL inventory (not shadow). Front is instant-commit;
	# any pending shadow trades are discarded.
	var item: ItemDef = _vendor.front_offer_item
	var count: int = _vendor.front_offer_count
	var snapshot: Dictionary = _player_inv.save_state()
	var leftover: int = _player_inv.add(item, count)
	if leftover > 0:
		# Not enough space — roll back and warn.
		_player_inv.load_state(snapshot)
		NotificationSystem.warn("Not enough space.")
		return

	var ok: bool = DebtSystem.incur(_vendor.vendor_id, _vendor.front_offer_debt, _vendor.vendor_name)
	if not ok:
		# Roll back inventory if debt couldn't be incurred (shouldn't happen).
		_player_inv.load_state(snapshot)
		return

	NotificationSystem.warn("Took %s x%d on credit." % [item.display_name, count])
	_close()


# --- Debt-owed view ---

func _refresh_debt_view() -> void:
	if _vendor == null:
		return
	var owed: int = DebtSystem.amount(_vendor.vendor_id)
	debt_amount_label.text = "You owe %s $%d." % [_vendor.vendor_name, owed]
	debt_pay_button.text = "Pay $%d" % owed
	debt_pay_button.disabled = not Wallet.can_afford(owed)


func _on_pay_debt() -> void:
	if _vendor == null:
		return
	if DebtSystem.pay(_vendor.vendor_id):
		NotificationSystem.warn("Debt to %s settled." % _vendor.vendor_name)
		_close()


func _on_debt_changed(_vendor_id: StringName, _new_amount: int) -> void:
	if _is_open and _mode == Mode.DEBT_OWED:
		_refresh_debt_view()


# --- Shadow setup (NORMAL / FRONT_AVAILABLE only) ---

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


func _on_player_slot_clicked(slot_index: int, _with_shift: bool) -> void:
	var stack := _player_shadow.get_slot(slot_index)
	if stack == null or stack.item == null:
		return
	if not stack.item.sellable:
		return
	var leftover := _vendor_shadow.add(stack.item, stack.count)
	var moved: int = stack.count - leftover
	if moved > 0:
		_player_shadow.consume_from_slot(slot_index, moved)


func _on_vendor_slot_clicked(slot_index: int, _with_shift: bool) -> void:
	var stack := _vendor_shadow.get_slot(slot_index)
	if stack == null or stack.item == null:
		return
	var leftover := _player_shadow.add(stack.item, stack.count)
	var moved: int = stack.count - leftover
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
	var player_lost := _diff_counts(_player_original, player_now)
	var player_gained := _diff_counts(player_now, _player_original)

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
	if not _is_open:
		return
	match _mode:
		Mode.DEBT_OWED:
			_refresh_debt_view()
		_:
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
