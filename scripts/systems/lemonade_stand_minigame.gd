extends Node2D

const CUSTOMER_SCENE: PackedScene = preload("res://scenes/components/lemonade_customer.tscn")
const WEED_ITEM_ID: StringName = &"dime_bag_full"

const SPAWN_INTERVAL: float = 6.0
const MAX_CUSTOMERS: int = 2

const PIVOT_DETOUR_TOLERANCE: float = 1.4  

const LEMONADE_ICON: Texture2D = preload("res://art/icons/art_items/lemonade.png")
const WEED_ICON: Texture2D = preload("res://art/icons/art_items/dime_bag_full.png")

var _rng := RandomNumberGenerator.new()
var _spawn_timer: float = 0.0
var _occupied: Dictionary = {}     # slot_index -> customer
var _ended: bool = false

@onready var _edge_points: Node2D = $Markers/EdgePoints
@onready var _pivot: Marker2D = $Markers/Pivot
@onready var _slots: Node2D = $Markers/CounterSpots

@onready var exit_button: Button = $UI/ExitButton
@onready var bank_label: Label = $UI/MarginContainer/VBoxContainer/BankLabel
@onready var cash_label: Label = $UI/MarginContainer/VBoxContainer/CashLabel


func _ready() -> void:
	_rng.seed = Time.get_ticks_usec()
	_spawn_timer = SPAWN_INTERVAL
	exit_button.text = "Close Up"
	exit_button.pressed.connect(_on_exit_pressed)
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		player.input_locked = true
	_refresh_ui()


func _exit_tree() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		player.input_locked = false
		if player.has_method("set_crime_view_active"):
			player.set_crime_view_active(false)


func _process(delta: float) -> void:
	if _ended:
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_INTERVAL
		_try_spawn()


func _try_spawn() -> void:
	var slot_index: int = _first_free_slot()
	if slot_index == -1:
		return
	var counter: Marker2D = _slots.get_child(slot_index)
	var entry_edge := _random_edge()
	var c = CUSTOMER_SCENE.instantiate()
	c.resolved.connect(_on_resolved.bind(slot_index))
	add_child(c)
	c.set_walk_in(_build_walk_in_path(counter, entry_edge))
	c.set_walk_out(_build_walk_out_path(counter, entry_edge))
	var wants_weed: bool = _rng.randf() < LemonadeStandSession.WEED_CUSTOMER_RATIO
	if wants_weed:
		c.setup(&"weed", WEED_ICON, "Serve (Alt)")
	else:
		c.setup(&"lemonade", LEMONADE_ICON, "Serve lemonade (E)")
	_occupied[slot_index] = c

# edge → corner pivot → counter
func _build_walk_in_path(counter: Marker2D, entry_edge: Marker2D) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var start := entry_edge.global_position if entry_edge != null else counter.global_position
	pts.append(start)
	if _route_through_pivot(start, counter.global_position):
		pts.append(_pivot.global_position)
	pts.append(counter.global_position)
	return pts

func _route_through_pivot(start: Vector2, end: Vector2) -> bool:
	if _pivot == null:
		return false
	var direct: float = start.distance_to(end)
	if direct < 1.0:
		return false
	var via: float = start.distance_to(_pivot.global_position) + _pivot.global_position.distance_to(end)
	return via <= direct * PIVOT_DETOUR_TOLERANCE

# counter → corner pivot → a DIFFERENT edge than they came in by

func _build_walk_out_path(counter: Marker2D, entry_edge: Marker2D) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var exit_edge := _other_edge(entry_edge)
	var end := exit_edge.global_position if exit_edge != null else counter.global_position
	pts.append(counter.global_position)
	if _route_through_pivot(counter.global_position, end):
		pts.append(_pivot.global_position)
	pts.append(end)
	return pts

func _edges() -> Array:
	var markers: Array = []
	for child in _edge_points.get_children():
		if child is Marker2D:
			markers.append(child)
	return markers


func _random_edge() -> Marker2D:
	var e := _edges()
	if e.is_empty():
		return null
	return e[_rng.randi() % e.size()]


# Prefer an edge other than the one given; fall back to the same if only one.
func _other_edge(exclude: Marker2D) -> Marker2D:
	var e := _edges()
	if e.is_empty():
		return null
	var choices: Array = []
	for m in e:
		if m != exclude:
			choices.append(m)
	if choices.is_empty():
		return exclude
	return choices[_rng.randi() % choices.size()]



func _first_free_slot() -> int:
	for i in range(_slots.get_child_count()):
		if not _occupied.has(i):
			return i
	return -1


func _on_resolved(served: bool, outcome_kind: StringName, _customer: Node, slot_index: int) -> void:
	_occupied.erase(slot_index)
	var area := LemonadeStandSession.area_id

	if served and outcome_kind == &"lemonade":
		Wallet.add(LemonadeStandSession.LEMONADE_PRICE, Wallet.POOL_CLEAN)
		NotificationSystem.warn("Sold lemonade. +$%d clean" % LemonadeStandSession.LEMONADE_PRICE)
		_refresh_ui()
		return

	if served and outcome_kind == &"weed":
		# Inventory check at settle: need a dime bag to actually deal.
		if not _consume_weed():
			NotificationSystem.warn("Out of product — they walked.")
			return
		Wallet.add(LemonadeStandSession.WEED_PRICE, Wallet.POOL_CASH)
		var pos: Vector2 = _customer.global_position if is_instance_valid(_customer) else Vector2.ZERO
		CrimeSystem.report_instant_crime(&"weed_deal", pos, area)
		HeatSystem.add_heat(area, LemonadeStandSession.WEED_SERVE_HEAT)
		NotificationSystem.warn("Slung a bag. +$%d" % LemonadeStandSession.WEED_PRICE)
		_refresh_ui()
		return

	# Failures:
	if outcome_kind == &"weed_to_innocent":
		HeatSystem.add_heat(area, LemonadeStandSession.WRONG_WEED_HEAT)
		NotificationSystem.warn("They wanted lemonade. That drew attention.")
	elif outcome_kind == &"lemonade_to_buyer":
		# Harmless — they wanted weed, declined the drink.
		pass
	elif outcome_kind == &"timeout":
		NotificationSystem.warn("A customer got tired of waiting.")


func _consume_weed() -> bool:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return false
	var inv = player.get("inventory")
	if inv == null:
		return false
	for i in range(inv.max_slots):
		var stack = inv.get_slot(i)
		if stack != null and stack.item != null and stack.item.id == WEED_ITEM_ID and stack.count > 0:
			inv.consume_from_slot(i, 1)
			return true
	return false


func _on_exit_pressed() -> void:
	if _ended:
		return
	_ended = true
	LemonadeStandSession.end_session()


func _refresh_ui() -> void:
	bank_label.text = "Bank: %s" % Wallet.format_balance(Wallet.POOL_CLEAN)
	cash_label.text = "Cash: %s" % Wallet.format_balance(Wallet.POOL_CASH)
