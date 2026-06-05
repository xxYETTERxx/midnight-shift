extends Control

# ATM panel: deposit dirty cash -> bank (clean) THROUGH the ATM channel
# (capped, suspicion on overage); withdraw bank -> cash directly (unmetered).

@onready var amount_field: LineEdit = $PanelContainer/VBoxContainer/AmountField
@onready var clean_button: Button = $PanelContainer/VBoxContainer/CleanButton
@onready var cancel_button: Button = $PanelContainer/VBoxContainer/CancelButton
@onready var cash_label: Label = $PanelContainer/VBoxContainer/CashLabel
@onready var bank_label: Label = $PanelContainer/VBoxContainer/BankLabel
@onready var feedback_label: Label = $PanelContainer/VBoxContainer/FeedbackLabel

var _is_open: bool = false


func _ready() -> void:
	add_to_group("clean_panel")
	visible = false
	clean_button.pressed.connect(_on_deposit)
	cancel_button.pressed.connect(_on_cancel)
	amount_field.text_changed.connect(_on_amount_changed)
	Wallet.balance_changed.connect(_on_wallet_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()


func open(_player: Node) -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	amount_field.text = ""
	feedback_label.text = ""
	_refresh()
	amount_field.grab_focus()
	TimeSystem.pause()


# --- Actions ---

func _parse_amount() -> int:
	var t := amount_field.text.strip_edges()
	if not t.is_valid_int():
		return -1
	return t.to_int()


func _on_deposit() -> void:
	var amount := _parse_amount()
	if amount <= 0:
		feedback_label.text = "Enter a valid amount."
		return
	if not Wallet.can_afford(amount, Wallet.POOL_CASH):
		feedback_label.text = "Not enough cash on hand."
		return

	var result: Dictionary = LaunderingSystem.clean_through_front("lemonade_stand",amount)
	if not result["ok"]:
		feedback_label.text = "Deposit failed."
		return

	amount_field.text = ""
	if result["overage"] > 0:
		NotificationSystem.info("Deposited $%d. That's a lot to clean at once." % amount)
	else:
		feedback_label.text = "Deposited $%d." % amount
		NotificationSystem.info("Deposited $%d to the bank." % amount)
	_refresh()


func _on_amount_changed(_new_text: String) -> void:
	feedback_label.text = ""


func _on_cancel() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	TimeSystem.resume()


# --- Display ---

func _on_wallet_changed(_pool: String, _new_balance: int) -> void:
	if _is_open:
		_refresh()


func _refresh() -> void:
	cash_label.text = "Cash: %s" % Wallet.format_balance(Wallet.POOL_CASH)
	bank_label.text = "Bank: %s" % Wallet.format_balance(Wallet.POOL_CLEAN)
	feedback_label.text = "Weekly deposit limit: $%d (%d left). Exceeding may flag your account." % [
		LaunderingSystem.front_cap("lemonade_stand"), LaunderingSystem.front_remaining_capacity("lemonade_stand"),
	]
