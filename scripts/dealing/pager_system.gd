extends Node

# Drives the pager loop. Each in-game minute (during waking hours), every
# active customer rolls a small probability of paging, AND every pending
# page ticks down its callback deadline. Pages that hit 0 expire — DEX
# penalty, trust hit, customer flake counter increments.

const SLEEP_WINDOW_START: int = 6
const SLEEP_WINDOW_END: int = 14

const COOLDOWN_MINUTES: int = 60 * 24
const CALLBACK_DEADLINE_HOURS: int = 6

@export var base_page_chance_per_minute: float = 0.01
@export var tier_chance_multiplier: float = 1.15

var _last_page_minute: Dictionary = {}
var _pending: Array[PendingPage] = []
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

signal page_received(page: PendingPage)
signal page_consumed(page: PendingPage)
signal page_expired(page: PendingPage)
signal queue_changed()


func _ready() -> void:
	SaveSystem.register_savable("pager_system", self)
	_rng.seed = Time.get_ticks_usec()
	TimeSystem.minute_tick.connect(_on_minute_tick)


# --- Public API ---

func has_pending() -> bool:
	return _pending.size() > 0


func pending_count() -> int:
	return _pending.size()


func pending_pages() -> Array[PendingPage]:
	return _pending.duplicate()


func consume_page(page: PendingPage) -> void:
	var idx := _pending.find(page)
	if idx == -1:
		return
	_pending.remove_at(idx)
	page_consumed.emit(page)
	queue_changed.emit()


func debug_force_page(customer_id: StringName = &"") -> void:
	var customer: Customer
	if customer_id != &"":
		customer = CustomerRoster.get_customer(customer_id)
	else:
		var active := CustomerRoster.active_customers()
		if active.is_empty():
			print("[Pager] no active customers to page")
			return
		customer = active[_rng.randi() % active.size()]
	if customer == null:
		return
	_create_page(customer)


# --- Tick logic ---

func _on_minute_tick(_total: int) -> void:
	if _is_sleep_window():
		return
	# Tick deadlines first so newly-created pages get the full budget.
	_tick_deadlines()
	_roll_for_new_pages()


func _tick_deadlines() -> void:
	var expired: Array[PendingPage] = []
	for page in _pending:
		page.minutes_remaining -= 1
		if page.minutes_remaining <= 0:
			expired.append(page)
	for page in expired:
		_expire_page(page)


func _roll_for_new_pages() -> void:
	var active := CustomerRoster.active_customers()
	for c in active:
		if _is_on_cooldown(c):
			continue
		var chance: float = base_page_chance_per_minute * pow(tier_chance_multiplier, c.tier)
		if _rng.randf() < chance:
			_create_page(c)


func _expire_page(page: PendingPage) -> void:
	var idx := _pending.find(page)
	if idx == -1:
		return
	_pending.remove_at(idx)
	var customer: Customer = page.get_customer()
	if customer != null:
		customer.times_flaked += 1
		customer.trust = max(customer.trust - 5, -100)
	DealerExperience.penalize_missed_callback()
	print("[Pager] Expired: %s never called back" %
		(customer.display_name if customer else "?"))
	page_expired.emit(page)
	queue_changed.emit()


func _is_sleep_window() -> bool:
	var h := TimeSystem.current_hour()
	return h >= SLEEP_WINDOW_START and h < SLEEP_WINDOW_END


func _is_on_cooldown(c: Customer) -> bool:
	var key := String(c.id)
	if not _last_page_minute.has(key):
		return false
	var last: int = _last_page_minute[key]
	return TimeSystem.total_minutes - last < COOLDOWN_MINUTES


func _create_page(customer: Customer) -> void:
	var page := PendingPage.new()
	page.customer_id = customer.id
	page.received_at_minute = TimeSystem.total_minutes
	page.quantity_requested = _rng.randi_range(customer.quantity_min, customer.quantity_max)
	page.minutes_remaining = CALLBACK_DEADLINE_HOURS * 60
	_pending.append(page)
	_last_page_minute[String(customer.id)] = TimeSystem.total_minutes
	print("[Pager] %s paged for %d (queue=%d)" %
		[customer.display_name, page.quantity_requested, _pending.size()])
	page_received.emit(page)
	queue_changed.emit()


# --- Save/load ---

func save_state() -> Dictionary:
	var pending_data: Array = []
	for p in _pending:
		pending_data.append(p.to_dict())
	return {
		"last_page_minute": _last_page_minute.duplicate(),
		"pending": pending_data,
	}


func load_state(data: Dictionary) -> void:
	_last_page_minute = data.get("last_page_minute", {}).duplicate()
	_pending.clear()
	var pending_data: Array = data.get("pending", [])
	for entry in pending_data:
		_pending.append(PendingPage.from_dict(entry))
	queue_changed.emit()
