extends Node

# Persistent registry of customers the player has been introduced to.
# Customers are generated lazily when DealerExperience unlocks new tiers.
# Once added to the roster, they stay (subject to blacklisting). Save-game
# scoped: each save file has its own roster.

# How many new customers spawn when each tier first unlocks. Tier 0 is the
# starter — seeded explicitly by seed_starter_customer(), not via this array.
const WAVE_SIZE_PER_TIER: Array[int] = [0, 3, 4, 4, 5]

# Hard cap on requested quantity per page, regardless of tier or trust.
const ABSOLUTE_MAX_QUANTITY: int = 100

# id → Customer
var _customers: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_id: int = 1

signal customer_added(customer: Customer)


func _ready() -> void:
	SaveSystem.register_savable("customer_roster", self)
	_rng.seed = Time.get_ticks_usec()
	DealerExperience.tier_unlocked.connect(_on_tier_unlocked)
	PagerSystem.pager_aquired.connect(seed_starter_customer)


# --- Public API ---

# Called once by world.gd._new_game() — seeds the starter customer.
# No-op if the roster already has customers (i.e., a save was just loaded).
func seed_starter_customer() -> void:
	if not _customers.is_empty():
		return
	var starter := _generate_customer(0)
	_add_customer(starter)


func get_customer(id: StringName) -> Customer:
	return _customers.get(id, null)


func all_customers() -> Array:
	return _customers.values()


# Customers eligible to page right now: not blacklisted, and the player's
# current tier meets their gate.
func active_customers() -> Array:
	var current_tier: int = DealerExperience.current_tier()
	var result: Array = []
	for c in _customers.values():
		if c.blacklisted:
			continue
		if c.tier > current_tier:
			continue
		result.append(c)
	return result

# Rolls a page quantity for a customer, scaled by their trust within
# their tier's quantity_min..quantity_max band. Trust 0 always rolls the
# floor; trust 100 unlocks the full range. Capped at ABSOLUTE_MAX_QUANTITY.
func roll_page_quantity(c: Customer, rng: RandomNumberGenerator) -> int:
	var trust_norm: float = clamp(c.trust, 0, 100) / 100.0
	var effective_max: int = int(round(lerp(
		float(c.quantity_min), float(c.quantity_max), trust_norm
	)))
	if effective_max < c.quantity_min:
		effective_max = c.quantity_min
	var rolled: int = rng.randi_range(c.quantity_min, effective_max)
	return min(rolled, ABSOLUTE_MAX_QUANTITY)

# --- Generation ---

func _on_tier_unlocked(tier: int) -> void:
	if tier < 0 or tier >= WAVE_SIZE_PER_TIER.size():
		return
	var wave_size: int = WAVE_SIZE_PER_TIER[tier]
	for i in range(wave_size):
		var c := _generate_customer(tier)
		_add_customer(c)


func _generate_customer(tier: int) -> Customer:
	var c := Customer.new()
	c.id = StringName("cust_%04d" % _next_id)
	_next_id += 1

	var identity: Dictionary = NPCGenerator.generate_customer_identity()
	c.display_name = identity.get("display_name", "")
	c.head_index = identity.get("head_index", -1)
	c.body_index = identity.get("body_index", -1)
	c.default_dialogue = identity.get("dialogue_line", "")

	c.tier = tier
	# Quantity ranges scale modestly with tier — higher tiers want bigger orders.
	var base_min: int = 1 + tier
	c.quantity_min = base_min
	c.quantity_max = base_min + 2 + tier
	c.quality_preference = min(tier, 3)
	c.dialogue_bank = "default"
	return c


func _add_customer(c: Customer) -> void:
	_customers[c.id] = c
	customer_added.emit(c)
	print("[Roster] Added: %s | tier %d | qty %d-%d | head=%d body=%d" %
		[c.display_name, c.tier, c.quantity_min, c.quantity_max,
		c.head_index, c.body_index])

# Public wrapper for spontaneous customer acquisition (e.g., from street
# dealing once the pager is online). Returns the new customer, or null
# if PagerSystem isn't active yet.
func add_random_customer(tier: int = 0) -> Customer:
	if not PagerSystem.has_pager:
		return null
	var c := _generate_customer(tier)
	_add_customer(c)
	return c

# --- Debug ---

func debug_print() -> void:
	print("[Roster] %d customers | DEX=%d (tier %d)" %
		[_customers.size(), DealerExperience.xp, DealerExperience.current_tier()])
	for c in _customers.values():
		print("  %s | tier %d | qty %d-%d | aff %d trust %d | dealt %d flaked %d%s" % [
			c.display_name, c.tier, c.quantity_min, c.quantity_max,
			c.affinity, c.trust, c.times_dealt, c.times_flaked,
			" [BLACKLISTED]" if c.blacklisted else "",
		])


# --- Save/load ---

func save_state() -> Dictionary:
	var data: Array = []
	for c in _customers.values():
		data.append(c.to_dict())
	return {
		"customers": data,
		"next_id": _next_id,
	}


func load_state(data: Dictionary) -> void:
	_customers.clear()
	var saved: Array = data.get("customers", [])
	for entry in saved:
		var c := Customer.from_dict(entry)
		_customers[c.id] = c
		# Rebuild NPCGenerator's claimed-heads set from the persisted roster
		# so future generations don't double up.
		if c.head_index >= 0:
			NPCGenerator.reclaim_head(&"customer", c.head_index)
	_next_id = data.get("next_id", 1)
