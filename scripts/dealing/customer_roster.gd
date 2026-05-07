extends Node

# Persistent registry of customers the player has been introduced to.
# Customers are generated lazily when DealerExperience unlocks new tiers.
# Once added to the roster, they stay (subject to blacklisting). Save-game
# scoped: each save file has its own roster.

# Random name pools. Keep small for now, expand during worldbuilding.
const FIRST_NAMES: Array[String] = [
	"Marco", "Tonya", "Dee", "Kev", "Reggie", "Sam", "Tasha", "Vince",
	"Lou", "Cynthia", "Marcus", "Trish", "Ed", "Lonnie", "Janelle", "Curtis",
]
const LAST_NAMES: Array[String] = [
	"P.", "M.", "T.", "B.", "Z.", "C.", "R.", "K.",
]

# How many new customers spawn when each tier first unlocks. Tier 0 is the
# starter — seeded explicitly by seed_starter_customer(), not via this array.
const WAVE_SIZE_PER_TIER: Array[int] = [0, 3, 4, 4, 5]

# id → Customer
var _customers: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_id: int = 1

signal customer_added(customer: Customer)


func _ready() -> void:
	SaveSystem.register_savable("customer_roster", self)
	_rng.seed = Time.get_ticks_usec()
	DealerExperience.tier_unlocked.connect(_on_tier_unlocked)


# --- Public API ---

# Called once by world.gd._new_game() — seeds the starter customer.
# No-op if the roster already has customers (i.e., a save was just loaded).
func seed_starter_customer() -> void:
	if not _customers.is_empty():
		return
	var starter := _generate_customer(0)
	starter.display_name = "Dee P."
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
	c.display_name = "%s %s" % [
		FIRST_NAMES[_rng.randi() % FIRST_NAMES.size()],
		LAST_NAMES[_rng.randi() % LAST_NAMES.size()],
	]
	c.tier = tier
	# Quantity ranges scale modestly with tier — higher tiers want bigger orders.
	var base_min: int = 1 + tier
	c.quantity_min = base_min
	c.quantity_max = base_min + 2 + tier
	c.quality_preference = min(tier, 3)
	c.sprite_id = "buyer_%d" % (_rng.randi() % 8)  # placeholder; resolve in chunk 4
	c.dialogue_bank = "default"
	return c


func _add_customer(c: Customer) -> void:
	_customers[c.id] = c
	customer_added.emit(c)
	print("[Roster] Added: %s | tier %d | qty %d-%d" %
		[c.display_name, c.tier, c.quantity_min, c.quantity_max])


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
	_next_id = data.get("next_id", 1)
