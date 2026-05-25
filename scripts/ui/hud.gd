extends CanvasLayer

@onready var clock_label: Label = $ClockLabel
@onready var interact_prompt: Label = $InteractPrompt
@onready var cash_label: Label = $CashLabel
@onready var rent_label: Label = $RentDueLabel
@onready var skill_debug: Label = $SkillDebug

@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var hunger_bar: ProgressBar = $HungerBar
@onready var thirst_bar: ProgressBar = $ThirstBar

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

	HungerSystem.hunger_changed.connect(_on_hunger_changed)
	HungerSystem.threshold_crossed.connect(_on_hunger_threshold)
	_on_hunger_changed(HungerSystem.current_value(), HungerSystem.MAX_VALUE)

	ThirstSystem.thirst_changed.connect(_on_thirst_changed)
	ThirstSystem.threshold_crossed.connect(_on_thirst_threshold)
	_on_thirst_changed(ThirstSystem.current_value(), ThirstSystem.MAX_VALUE)

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
	stamina_bar.max_value = maximum
	stamina_bar.value = current
	# Color the fill via modulate based on band.
	var pct := current / maximum
	if pct <= 0.2:
		stamina_bar.modulate = Color(1.0, 0.4, 0.4)
	elif pct <= 0.5:
		stamina_bar.modulate = Color(1.0, 0.85, 0.5)
	else:
		stamina_bar.modulate = Color.WHITE

func _on_hunger_changed(current: float, maximum: float) -> void:
	hunger_bar.max_value = maximum
	hunger_bar.value = current
	var pct := current / maximum
	if pct <= 0.1:
		hunger_bar.modulate = Color(1.0, 0.3, 0.3)
	elif pct <= 0.25:
		hunger_bar.modulate = Color(1.0, 0.6, 0.3)
	elif pct <= 0.5:
		hunger_bar.modulate = Color(1.0, 0.9, 0.5)
	else:
		hunger_bar.modulate = Color.WHITE


func _on_hunger_threshold(band: String) -> void:
	match band:
		"peckish": NotificationSystem.warn("You're getting hungry.")
		"hungry": NotificationSystem.warn("You should eat.")
		"starving": NotificationSystem.warn("You need to eat NOW.")


func _on_thirst_changed(current: float, maximum: float) -> void:
	thirst_bar.max_value = maximum
	thirst_bar.value = current
	var pct := current / maximum
	if pct <= 0.1:
		thirst_bar.modulate = Color(0.5, 0.3, 1.0)
	elif pct <= 0.25:
		thirst_bar.modulate = Color(0.6, 0.5, 1.0)
	elif pct <= 0.5:
		thirst_bar.modulate = Color(0.7, 0.7, 1.0)
	else:
		thirst_bar.modulate = Color.WHITE


func _on_thirst_threshold(band: String) -> void:
	match band:
		"parched": NotificationSystem.warn("You're getting thirsty.")
		"thirsty": NotificationSystem.warn("You need a drink.")
		"dehydrated": NotificationSystem.warn("You're dehydrated!")

func _refresh_cash() -> void:
	cash_label.text = Wallet.format_balance()

func _on_balance_changed(_pool: String, _new_balance: int) -> void:
	_refresh_cash()
	
func _fire_rent_warning(amount: int) -> void:
	rent_label.visible = true
	timer += 30

func _on_skill_debug_refresh(_skill_id: StringName, _new_xp: int) -> void:
	_refresh_skill_debug()


func _refresh_skill_debug() -> void:
	if not skill_debug.visible:
		return
	skill_debug.text = "ATH xp=%d L=%d mult=%.3f  |  STR xp=%d L=%d slots=%d  |  LCK xp=%d L=%d mult=%.2f" % [
		PlayerSkills.value(&"athletics"),
		PlayerSkills.tier(&"athletics"),
		PlayerSkills.speed_multiplier(),
		PlayerSkills.value(&"strength"),
		PlayerSkills.tier(&"strength"),
		PlayerSkills.inventory_slot_count(),
		PlayerSkills.value(&"lockpicking"),
		PlayerSkills.tier(&"lockpicking"),
		PlayerSkills.lockpick_duration_multiplier(),
	]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F10:
			skill_debug.visible = not skill_debug.visible
			_refresh_skill_debug()
