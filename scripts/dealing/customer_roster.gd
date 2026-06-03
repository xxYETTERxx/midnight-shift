extends Node

# Persistent registry of customers the player has been introduced to.
# Customers are generated lazily when DealerExperience unlocks new tiers.
# Once added to the roster, they stay (subject to blacklisting). Save-game
# scoped: each save file has its own roster.

# How many new customers spawn when each tier first unlocks. Tier 0 is the
# starter — seeded explicitly by seed_starter_customer(), not via this array.
const WAVE_SIZE_PER_TIER: Array[int] = [0, 1, 1, 1, 1]

# Trust a customer must reach to refer a new buyer into the roster (one-shot).
const REFERRAL_TRUST_THRESHOLD: int = 45

# Referral chain caps here. Beyond this, escalation is the wholesale track
# (oz-based, gated separately via Hank) — not this grams chain.
const MAX_REFERRAL_TIER: int = 4

# Per-tier requested-quantity bands (grams). Indexed by Customer.tier.
# Tiers past the end clamp to the last entry.
const QUANTITY_BANDS: Array[Vector2i] = [
	Vector2i(1, 3),    # tier 0
	Vector2i(2, 5),    # tier 1
	Vector2i(3, 8),    # tier 2
	Vector2i(5, 11),   # tier 3
	Vector2i(7, 14),   # tier 4
]

# Hard cap on requested quantity per page, regardless of tier or trust.
const ABSOLUTE_MAX_QUANTITY: int = 100

const MAX_ROSTER_SIZE: int = 12

# Trust thresholds at which a customer may refer a new buyer to the player.
# Each customer pays out at most once per band (tracked via referrals_given),
# so a single relationship can yield at most this many referrals.
const REFERRAL_THRESHOLDS: Array[int] = [25, 50, 75]

# Chance a crossed threshold actually produces a referral. <1.0 keeps growth
# from being perfectly deterministic — sometimes a buyer just doesn't know
# anyone right now.
const REFERRAL_CHANCE: float = 0.6

# id → Customer
var _customers: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_id: int = 1

signal customer_added(customer: Customer)
signal customer_removed(customer: Customer)


func _ready() -> void:
	SaveSystem.register_savable("customer_roster", self)
	_rng.seed = Time.get_ticks_usec()


# --- Public API ---


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

func roster_size() -> int:
	return _customers.size()

# --- Generation ---



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
	var band: Vector2i = _quantity_band_for_tier(tier)
	c.quantity_min = band.x
	c.quantity_max = band.y
	c.quality_preference = min(tier, 3)
	c.dialogue_bank = "default"
	return c

func _quantity_band_for_tier(tier: int) -> Vector2i:
	var idx: int = clamp(tier, 0, QUANTITY_BANDS.size() - 1)
	return QUANTITY_BANDS[idx]

func _add_customer(c: Customer) -> void:
	_customers[c.id] = c
	customer_added.emit(c)
	print("[Roster] Added: %s | tier %d | qty %d-%d | head=%d body=%d" %
		[c.display_name, c.tier, c.quantity_min, c.quantity_max,
		c.head_index, c.body_index])
	_enforce_cap()

# Checks whether `c` has crossed any new referral threshold and, if so,
# may generate a referred customer. Call after any trust increase. Safe to
# call repeatedly; pays out at most one band per call, and never the same
# band twice (referrals_given guards it).
func check_referral(c: Customer) -> void:
	if not PagerSystem.has_pager:
		return
	if c.blacklisted:
		return
	# Find the highest threshold the customer now meets but hasn't paid yet.
	var newly_crossed: int = 0
	for t in REFERRAL_THRESHOLDS:
		if c.trust >= t and t > c.referrals_given:
			newly_crossed = t
	if newly_crossed == 0:
		return
	# Mark it consumed regardless of the chance roll, so a failed roll doesn't
	# keep re-rolling the same band on every subsequent deal.
	c.referrals_given = newly_crossed
	if _rng.randf() >= REFERRAL_CHANCE:
		return
	# Referred customer enters at the referrer's tier — a trusted buyer knows
	# people in their own circle, not strangers above your station.
	var referred := _generate_customer(c.tier)
	_add_customer(referred)
	NotificationSystem.warn("%s put you onto %s." % [c.display_name, referred.display_name])

# Public wrapper for spontaneous customer acquisition (e.g., from street
# dealing once the pager is online). Returns the new customer, or null
# if PagerSystem isn't active yet.
func add_random_customer(tier: int = 0) -> Customer:
	if not PagerSystem.has_pager:
		return null
	var c := _generate_customer(tier)
	_add_customer(c)
	return c

# Called after a customer's trust increases (on a completed deal). If this
# customer has crossed the referral threshold and hasn't referred anyone yet,
# it spawns one new customer at referrer.tier + 1 (clamped to MAX_REFERRAL_TIER)
# and flips the one-shot flag. Returns the new customer, or null if no
# referral fired.
func try_referral_from(referrer: Customer) -> Customer:
	if referrer == null:
		return null
	if referrer.has_referred:
		return null
	if referrer.trust < REFERRAL_TRUST_THRESHOLD:
		return null

	referrer.has_referred = true
	var new_tier: int = min(referrer.tier + 1, MAX_REFERRAL_TIER)
	var c := _generate_customer(new_tier)
	_add_customer(c)
	print("[Roster] Referral: %s (tier %d, trust %d) -> %s (tier %d)" % [
		referrer.display_name, referrer.tier, referrer.trust,
		c.display_name, c.tier,
	])
	return c
# If the roster is over capacity, drop the weakest contact: lowest tier
# first, then lowest trust as the tiebreak. The just-added customer is a
# candidate too — a fresh trust-0 pickup landing in a full roster of
# established contacts will be the one dropped, so the add cleanly no-ops.
func _enforce_cap() -> void:
	while _customers.size() > MAX_ROSTER_SIZE:
		var weakest: Customer = _find_weakest()
		if weakest == null:
			return  # shouldn't happen, but never loop forever
		_remove_customer(weakest)


func _find_weakest() -> Customer:
	var weakest: Customer = null
	for c in _customers.values():
		if weakest == null or _is_weaker(c, weakest):
			weakest = c
	return weakest


# Strict weakness ordering: lower tier loses; on equal tier, lower trust
# loses; on equal trust, lower times_dealt loses; final tiebreak on id so
# the result is deterministic (no RNG, stable across saves).
func _is_weaker(a: Customer, b: Customer) -> bool:
	if a.tier != b.tier:
		return a.tier < b.tier
	if a.trust != b.trust:
		return a.trust < b.trust
	if a.times_dealt != b.times_dealt:
		return a.times_dealt < b.times_dealt
	return String(a.id) < String(b.id)


func _remove_customer(c: Customer) -> void:
	if not _customers.has(c.id):
		return
	_customers.erase(c.id)
	# Free the head index back to NPCGenerator so future customers can reuse
	# the appearance (mirrors the reclaim on load).
	if c.head_index >= 0 and NPCGenerator.has_method("release_head"):
		NPCGenerator.release_head(&"customer", c.head_index)
	print("[Roster] Dropped (cap): %s | tier %d | trust %d" % [
		c.display_name, c.tier, c.trust,
	])
	customer_removed.emit(c)


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
