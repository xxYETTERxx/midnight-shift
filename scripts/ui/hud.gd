extends CanvasLayer

@onready var clock_label: Label = $ClockLabel
@onready var stamina_label: Label = $StaminaLabel
@onready var interact_prompt: Label = $InteractPrompt
@onready var cash_label: Label = $CashLabel
@onready var rent_label: Label = $RentDueLabel

var timer: int = 0


func _ready() -> void:
	_refresh_clock()
	TimeSystem.minute_tick.connect(_on_minute_tick)
	Wallet.balance_changed.connect(_on_balance_changed)
	_refresh_cash()
	await get_tree().process_frame
	var player := get_tree().get_first_node_in_group("player")
	player.stamina_changed.connect(_on_stamina_changed)
	_on_stamina_changed(player.stamina, player.stamina_max)
	# UPDATED: was active_changed, now winner_changed
	InteractionManager.winner_changed.connect(_on_winner_changed)
	_on_winner_changed(InteractionManager.active)
	RentSystem.rent_due_warning.connect(_fire_rent_warning)
	rent_label.visible = false

func _on_winner_changed(interactable: Node) -> void:
	if interactable == null:
		interact_prompt.visible = false
		return
	var text := "Interact"
	if "prompt_text" in interactable:
		text = interactable.prompt_text
	interact_prompt.text = "[E] %s" % text
	interact_prompt.visible = true

func _on_minute_tick(_total: int) -> void:
	_refresh_clock()
	if timer > 0:
		timer -= 1
	else:
		rent_label.visible = false
		timer = 0


func _refresh_clock() -> void:
	clock_label.text = "%s\n%s" % [TimeSystem.format_time(), TimeSystem.format_date()]


func _on_stamina_changed(current: float, maximum: float) -> void:
	stamina_label.text = "STA %d/%d" % [int(current), int(maximum)]
	var pct := current / maximum
	if pct <= 0.2:
		stamina_label.modulate = Color(1.0, 0.4, 0.4)  # red
	elif pct <= 0.5:
		stamina_label.modulate = Color(1.0, 0.85, 0.5)  # amber
	else:
		stamina_label.modulate = Color.WHITE

func _refresh_cash() -> void:
	cash_label.text = Wallet.format_balance()

func _on_balance_changed(_pool: String, _new_balance: int) -> void:
	_refresh_cash()
	
func _fire_rent_warning(amount: int) -> void:
	rent_label.visible = true
	timer += 30
