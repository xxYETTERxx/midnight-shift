extends CanvasLayer

@onready var clock_label: Label = $ClockLabel
@onready var stamina_label: Label = $StaminaLabel
@onready var interact_prompt: Label = $InteractPrompt


func _ready() -> void:
	_refresh_clock()
	TimeSystem.minute_tick.connect(_on_minute_tick)
	var player := get_parent().get_node("Player")
	player.stamina_changed.connect(_on_stamina_changed)
	_on_stamina_changed(player.stamina, player.stamina_max)
	# NEW: interact prompt
	InteractionManager.active_changed.connect(_on_active_changed)
	_on_active_changed(InteractionManager.active)

func _on_active_changed(interactable: Node) -> void:
	if interactable == null:
		interact_prompt.visible = false
		return
	# Read prompt_text from the interactable; fall back to generic text.
	var text := "Interact"
	if "prompt_text" in interactable:
		text = interactable.prompt_text
	interact_prompt.text = "[E] %s" % text
	interact_prompt.visible = true

func _on_minute_tick(_total: int) -> void:
	_refresh_clock()


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
