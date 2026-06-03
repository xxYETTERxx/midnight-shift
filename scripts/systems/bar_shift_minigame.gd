extends Node2D

# Mock bartending shift. Step 1 skeleton: enters, runs the shift clock on
# game-time, exits on timer-expiry (completed) or player exit (incomplete).
# Customers, stations, tips come in later steps.
const CUSTOMER_SCENE: PackedScene = preload("res://scenes/components/bar_customer.tscn")
const DRINK_TYPES: Array[StringName] = [&"beer", &"whiskey", &"cocktail"]
const SHIFT_TIME_SCALE: float = 2.0
const SHIFT_LENGTH: int = 4

# Seconds between spawn attempts. Tune to taste.
const SPAWN_INTERVAL: float = 5.0

# Tips accrue as float across the shift; rounded and deposited once on exit.
var _tips_accrued: float = 0.0
var _served_count: int = 0

# Flat tip ceiling per perfect (full-patience) serve. Tip scales down with how
# little patience remained at delivery.
const MAX_TIP_PER_DRINK: float = 4.0

var _rng := RandomNumberGenerator.new()
var _spawn_timer: float = 0.0
# slot_index -> customer node (or absent if free)
var _occupied: Dictionary = {}

var _speed_pushed: bool = false

@onready var _slots: Node2D = $CounterSlots


@onready var clock_label: Label = $UI/MarginContainer/VBoxContainer/ClockLabel
@onready var exit_button: Button = $UI/ExitButton
@onready var drink_label: Label = $UI/MarginContainer/VBoxContainer/DrinkLabel

const DRINK_NAMES: Dictionary = {
	&"beer": "Beer",
	&"whiskey": "Whiskey",
	&"cocktail": "Cocktail",
}

const DRINK_ICONS: Dictionary = {
	&"beer": preload("res://art/icons/beer.png"),
	&"whiskey": preload("res://art/icons/whiskey.png"),
	&"cocktail": preload("res://art/icons/cocktail.png"),
}

var _ended: bool = false


func _ready() -> void:
	add_to_group("bar_shift")
	TimeSystem.push_speed(SHIFT_TIME_SCALE)
	_speed_pushed = true
	exit_button.text = "Clock Out"
	exit_button.pressed.connect(_on_exit_pressed)
	_rng.seed = Time.get_ticks_usec()
	_spawn_timer = SPAWN_INTERVAL
	_update_drink_indicator()
	_refresh_ui()



func _process(delta: float) -> void:
	if _ended:
		return
	if TimeSystem.total_minutes >= BarShiftSession.end_minute():
		_finish(true)
		return
	_refresh_ui()

	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_INTERVAL
		_try_spawn_customer()


func _on_exit_pressed() -> void:
	# Player bailing before the clock runs out — incomplete shift.
	_finish(false)

func _try_spawn_customer() -> void:
	var slot_index: int = _first_free_slot()
	if slot_index == -1:
		return

	var slot: Marker2D = _slots.get_child(slot_index)
	var c = CUSTOMER_SCENE.instantiate()
	var drink: StringName = DRINK_TYPES[_rng.randi() % DRINK_TYPES.size()]
	c.set_order(drink, DRINK_ICONS.get(drink, null))
	c.resolved.connect(_on_customer_resolved.bind(slot_index))
	add_child(c)
	c.global_position = slot.global_position
	_occupied[slot_index] = c


func _first_free_slot() -> int:
	for i in range(_slots.get_child_count()):
		if not _occupied.has(i):
			return i
	return -1


func _on_customer_resolved(served: bool, _customer: Node, slot_index: int) -> void:
	_occupied.erase(slot_index)
	# Step 4 will tally served/lost and tips here. For now, just feedback.
	if served:
		NotificationSystem.warn("Served.")
	else:
		NotificationSystem.warn("A customer stormed out.")
		_tips_accrued -= 1

func try_deliver_to(customer: Node) -> void:
	if not is_holding_drink():
		NotificationSystem.warn("You're not carrying anything.")
		return
	if customer.wants() != _held_drink:
		NotificationSystem.warn("That's not what they ordered.")
		return

	# Correct drink — tip scales with patience remaining at delivery.
	var tip: float = MAX_TIP_PER_DRINK * customer.patience_fraction()
	_tips_accrued += tip
	_served_count += 1
	clear_held_drink()
	customer.serve()
	NotificationSystem.warn("Served! +$%.2f tip" % tip)
	
func _unhandled_input(event: InputEvent) -> void:
	if _ended:
		return
	if event.is_action_pressed("alt_interact") and is_holding_drink():
		clear_held_drink()
		NotificationSystem.warn("Dumped the drink.")
		get_viewport().set_input_as_handled()


func _finish(completed: bool) -> void:
	if _ended:
		return
	_ended = true
	var payout: int = int(ceil(_tips_accrued))
	if payout > 0:
		Wallet.add(payout,"clean")

	if completed:
		Wallet.add(40, "clean")
		SuspicionSystem.report_legit_work(SHIFT_LENGTH)
		NotificationSystem.warn("Shift over. %d served, $%d in tips. $%d in wages" % [_served_count, payout, 40])
	else:
		EmploymentSystem.record_strike()
		NotificationSystem.warn("Clocked out early. %d served, $%d in tips." % [_served_count, payout])

	BarShiftSession.end_session(completed)


func _refresh_ui() -> void:
	var remaining: int = max(0, BarShiftSession.end_minute() - TimeSystem.total_minutes)
	var h: int = remaining / 60
	var m: int = remaining % 60
	clock_label.text = "Shift ends in %d:%02d" % [h, m]


  # --- Held drink (one at a time) ---

# &"" means empty-handed.
var _held_drink: StringName = &""


func is_holding_drink() -> bool:
	return _held_drink != &""


func held_drink() -> StringName:
	return _held_drink


func set_held_drink(drink_type: StringName) -> void:
	_held_drink = drink_type
	_update_drink_indicator()
	InteractionManager.notify_player_state_changed()


func clear_held_drink() -> void:
	_held_drink = &""
	_update_drink_indicator()
	InteractionManager.notify_player_state_changed()


func _update_drink_indicator() -> void:
	if _held_drink == &"":
		drink_label.text = "Empty-handed"
	else:
		var pretty: String = DRINK_NAMES.get(_held_drink, String(_held_drink))
		drink_label.text = "Carrying: %s" % pretty
		
func _exit_tree() -> void:
	if _speed_pushed:
		TimeSystem.pop_speed()
		_speed_pushed = false
		
