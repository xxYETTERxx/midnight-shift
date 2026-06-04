extends Control

# ATM panel: deposit dirty cash -> bank (clean) THROUGH the ATM channel
# (capped, suspicion on overage); withdraw bank -> cash directly (unmetered).

@onready var amount_field: LineEdit = $PanelContainer/VBoxContainer/AmountField
@onready var deposit_button: Button = $PanelContainer/VBoxContainer/DepositButton
@onready var withdraw_button: Button = $PanelContainer/VBoxContainer/WithdrawButton
@onready var cancel_button: Button = $PanelContainer/VBoxContainer/CancelButton
@onready var cash_label: Label = $PanelContainer/VBoxContainer/CashLabel
@onready var bank_label: Label = $PanelContainer/VBoxContainer/BankLabel
@onready var feedback_label: Label = $PanelContainer/VBoxContainer/FeedbackLabel

var _is_open: bool = false
var _atm: ATM = null


func _ready() -> void:
	add_to_group("atm_panel")
	visible = false
	deposit_button.pressed.connect(_on_deposit)
	withdraw_button.pressed.connect(_on_withdraw)
	cancel_button.pressed.connect(_on_cancel)
	amount_field.text_changed.connect(_on_amount_changed)
	Wallet.balance_changed.connect(_on_wallet_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()


func open(_player: Node, atm: ATM) -> void:
	if _is_open:
		return
	_is_open = true
	_atm = atm
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
	if _atm == null:
		return
	var amount := _parse_amount()
	if amount <= 0:
		feedback_label.text = "Enter a valid amount."
		return
	if not Wallet.can_afford(amount, Wallet.POOL_CASH):
		feedback_label.text = "Not enough cash on hand."
		return

	# Route through the channel — it moves the money, tracks the weekly cap,
	# and reports any overage to SuspicionSystem.
	var result: Dictionary = _atm.clean(amount)
	if not result["ok"]:
		feedback_label.text = "Deposit failed."
		return

	amount_field.text = ""
	if result["overage"] > 0:
		# Diegetic, fuzzy — no number, no meter. The player feels it.
		feedback_label.text = "The teller eyes the stack a little long."
		NotificationSystem.info("Deposited $%d. That's a lot to bank at once." % amount)
	else:
		feedback_label.text = "Deposited $%d." % amount
		NotificationSystem.info("Deposited $%d to the bank." % amount)
	_refresh()


func _on_withdraw() -> void:
	var amount := _parse_amount()
	if amount <= 0:
		feedback_label.text = "Enter a valid amount."
		return
	if not Wallet.can_afford(amount, Wallet.POOL_CLEAN):
		feedback_label.text = "Not enough in the bank."
		return
	if Wallet.withdraw(amount):
		feedback_label.text = "Withdrew $%d." % amount
		amount_field.text = ""
		NotificationSystem.info("Withdrew $%d from the bank." % amount)
	_refresh()


func _on_amount_changed(_new_text: String) -> void:
	feedback_label.text = ""


func _on_cancel() -> void:
	if not _is_open:
		return
	_is_open = false
	_atm = null
	visible = false
	TimeSystem.resume()


# --- Display ---

func _on_wallet_changed(_pool: String, _new_balance: int) -> void:
	if _is_open:
		_refresh()


func _refresh() -> void:
	cash_label.text = "Cash: %s" % Wallet.format_balance(Wallet.POOL_CASH)
	bank_label.text = "Bank: %s" % Wallet.format_balance(Wallet.POOL_CLEAN)
	if _atm != null:
		feedback_label.text = "Weekly deposit limit: $%d ($%d left). Exceeding may flag your account." % [
			_atm.weekly_cap(), _atm.remaining_capacity(),
		]
