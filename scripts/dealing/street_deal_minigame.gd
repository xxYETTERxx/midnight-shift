extends Node2D

# The "ducked-out-of-the-world" dealing minigame scene. Reads session data
# from StreetDealSession on _ready, runs the spawn loop, tallies per-deal
# cash, applies heat on refusals, calls back on exit.

const STREET_CUSTOMER_SCENE: PackedScene = preload("res://scenes/npcs/street_customer.tscn")
const COP_PATROL_SCENE: PackedScene = preload("res://scenes/npcs/cop_patrol.tscn")
const CASH_PER_GRAM: int = 15   # raw bud price
const CASH_PER_BAG: int = 15    # dime bag price (same number, different unit)

# Eyeball tax: per accepted sale, 0-15% of the grams sold is "wasted" by
# imprecise measurement. Accumulates across the session; deducted from
# leftover bud on exit.
const EYEBALL_TAX_MAX_PCT: float = 0.40


# Cop spawn chance follows a saturating curve:
#   chance = COP_CHANCE_MAX * (1 - exp(-COP_CHANCE_GROWTH * recent_deals))
# Each deal adds less than the last, easing toward the cap instead of
# slamming into it. Lower growth = gentler ramp.
const COP_CHANCE_GROWTH: float = 0.06
const COP_CHANCE_MAX: float = 0.6

# Chance per accepted sale that a new pager customer is gained. Only fires
# if the player has the pager.
const NEW_CUSTOMER_CHANCE_ON_ACCEPT: float = 0.03

const IDLE_SPEEDUP_MULT: float = 5.0

# Dealer XP tier at which archetype identification kicks in.
# Below this, all archetypes use a generic sprite (visual only — odds still apply).
const ARCHETYPE_REVEAL_TIER: int = 1

var _cop_spawn_timer: float = 0.0
var _live_cops: Array = []

# Notice window: seconds a cop must hold LOS on an in-progress deal before
# it busts. Mirrors CopProfile.notice_delay — a per-encounter threshold is
# rolled in [0, delay], so the exact window varies. Read from the cop's
# profile when present; this is the fallback.
const COP_NOTICE_DELAY_FALLBACK: float = 2.5
const NOTICE_MIN: float = 1.0

# cop instance_id -> { "elapsed": float, "threshold": float }
var _cop_notice: Dictionary = {}
var _busted: bool = false

# Spawn / customer-odds table by time-of-day window.
# spawn_minutes is in GAME minutes — actual real-time elapsed depends on
# whether speed-up is engaged.
var _windows: Array = [
	{ "start": 22, "end": 28, "spawn_minutes": 20.0, "customer_pct": 0.25 },  # late night
	{ "start": 4,  "end": 10, "spawn_minutes": 25.0, "customer_pct": 0.15 },  # early morning
	{ "start": 10, "end": 16, "spawn_minutes": 12.0, "customer_pct": 0.35 },  # day
	{ "start": 16, "end": 22, "spawn_minutes": 8.0,  "customer_pct": 0.45 },  # evening
]


# Concurrent customer cap to avoid screen crowding.
const MAX_LIVE_CUSTOMERS: int = 2

# Heat applied on refusal: uniform [0, 5].
const REFUSAL_HEAT_MIN: float = 0.0
const REFUSAL_HEAT_MAX: float = 5.0

# --- Scene refs ---
@onready var paths_root: Node2D = $Paths
@onready var customer_layer: Node2D = $CustomerLayer
@onready var bud_label: Label = $UI/MarginContainer/VBoxContainer/BudLabel
@onready var cash_label: Label = $UI/MarginContainer/VBoxContainer/CashLabel
@onready var exit_button: Button = $UI/ExitButton

# --- Session state ---
var _bud_left: int = 0
var _cash_earned: int = 0
var _eyeball_loss: float = 0.0
var _spawn_timer: float = 0.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _live_customers: Array = []
var _speed_active: bool = false


func _ready() -> void:
	_rng.seed = Time.get_ticks_usec()
	_bud_left = StreetDealSession.bud_in_session
	_collect_paths()
	_cash_earned = 0
	_lock_player(true)
	exit_button.pressed.connect(_on_exit_pressed)
	_reset_spawn_timer()
	_cop_spawn_timer = StreetDealSession.cop_check_interval_minutes
	_refresh_speed()
	_refresh_ui()
	CrimeSystem.crime_witnessed.connect(_on_crime_witnessed)


func _exit_tree() -> void:
	_lock_player(false)
	if _speed_active:
		TimeSystem.pop_speed()
		_speed_active = false
	if CrimeSystem.crime_witnessed.is_connected(_on_crime_witnessed):
		CrimeSystem.crime_witnessed.disconnect(_on_crime_witnessed)


func _process(delta: float) -> void:
	if _bud_left <= 0:
		# Auto-exit when out of product. Pop speed first so we don't leave
		# the stack dirty.
		if _speed_active:
			TimeSystem.pop_speed()
			_speed_active = false
		_request_exit()
		return

	# Convert real seconds to game minutes for our timers.
	var game_minutes: float = delta / TimeSystem.real_seconds_per_minute

	# Customer spawn tick.
	_spawn_timer -= game_minutes
	if _spawn_timer <= 0.0 and _live_customers.size() < MAX_LIVE_CUSTOMERS:
		_spawn_customer()
		_reset_spawn_timer()

	# Cop spawn tick — independent cadence, chance scales with spot history.
	_tick_notice(delta)
	_cop_spawn_timer -= game_minutes
	if _cop_spawn_timer <= 0.0:
		_cop_spawn_timer = StreetDealSession.cop_check_interval_minutes
		_try_spawn_cop()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _cancel_active_deal():
			get_viewport().set_input_as_handled()


func _cancel_active_deal() -> bool:
	for c in _live_customers:
		if is_instance_valid(c) and c.has_method("is_dealing") and c.is_dealing():
			c.player_cancel()
			NotificationSystem.warn("Backed off.")
			return true
	return false

# Collected once on ready: each entry is one path's ordered points in the
# customer_layer's local space. A valid path needs at least 2 markers.
var _paths: Array[PackedVector2Array] = []

func _collect_paths() -> void:
	_paths.clear()
	if paths_root == null:
		push_warning("StreetDealMinigame: no Paths node found")
		return
	for path_node in paths_root.get_children():
		var pts := PackedVector2Array()
		for child in path_node.get_children():
			if child is Marker2D:
				pts.append(customer_layer.to_local(child.global_position))
		if pts.size() >= 2:
			_paths.append(pts)
			# Reversible: walking the same route end-to-start is a valid spawn.
			# Authoring one path yields both directions.
			var rev := pts.duplicate()
			rev.reverse()
			_paths.append(rev)
		else:
			push_warning("StreetDealMinigame: path '%s' has <2 markers, skipped" % path_node.name)
	if _paths.is_empty():
		push_warning("StreetDealMinigame: no valid paths under Paths node")


# --- Spawning ---

func _reset_spawn_timer() -> void:
	var base: float = StreetDealSession.spawn_interval_minutes * _time_of_day_multiplier()
	var jitter: float = _rng.randf_range(-0.2, 0.2) * base
	_spawn_timer = base + jitter


func _time_of_day_multiplier() -> float:
	# Multiplier on spawn interval. <1.0 = more frequent, >1.0 = less.
	# Alleyways and corners still follow the daily rhythm, just less intensely
	# than their base interval suggests.
	var h: int = TimeSystem.current_hour()
	if h >= 16 and h < 22:
		return 0.75   # evening rush
	elif h >= 10 and h < 16:
		return 1.0    # baseline day
	elif h >= 22 or h < 4:
		return 1.4    # late night thin
	else:
		return 2.0    # early morning dead


func _spawn_customer() -> void:
	var archetype: CustomerArchetype = _pick_archetype()
	print("[Spawn] archetypes=%s weights=%s" % [StreetDealSession.archetypes, StreetDealSession.archetype_weights])
	if archetype == null:
		push_warning("StreetDealMinigame: no archetypes configured on session")
		return
	if archetype.sprite_frames_pool.is_empty():
		push_warning("StreetDealMinigame: archetype '%s' has empty sprite_frames_pool" % archetype.archetype_id)
		return

	if _paths.is_empty():
		push_warning("StreetDealMinigame: no paths to spawn on")
		return
	var path: PackedVector2Array = _paths[_rng.randi() % _paths.size()]

	var customer = STREET_CUSTOMER_SCENE.instantiate()
	customer.set_path(path)
	customer.archetype = archetype
	customer.sprite_frames = archetype.sprite_frames_pool[_rng.randi() % archetype.sprite_frames_pool.size()]


	var willingness: float = archetype.roll_purchase_chance(_rng)
	customer.willingness_pct = willingness
	customer.is_willing = _rng.randf() < willingness

	customer.offer_resolved.connect(_on_customer_offer_resolved)
	customer.tree_exited.connect(_on_customer_freed.bind(customer))
	customer_layer.add_child(customer)
	_live_customers.append(customer)
	_refresh_speed()


# --- Offer resolution ---

func _on_customer_offer_resolved(willing: bool, completed: bool, _customer: Node) -> void:
	if not willing:
		# Refusal — apply heat, no sale, no crime.
		var heat: float = _rng.randf_range(REFUSAL_HEAT_MIN, REFUSAL_HEAT_MAX)
		if heat > 0.0 and StreetDealSession.area_id != &"":
			HeatSystem.add_heat(StreetDealSession.area_id, heat)
		NotificationSystem.warn("Refused.")
		_refresh_ui()
		return

	if not completed:
		# Action was cancelled mid-progress (e.g. player walked away).
		return

	# Successful sale — settle cash, XP, contact roll. Product type
	# determines pricing and whether eyeball tax applies.
	var is_raw: bool = StreetDealSession.product_id == &"weed_buds"

	var qty: int
	var cash: int
	if is_raw:
		# Raw bud: customer buys 1-2 grams, eyeball tax accrues.
		qty = _rng.randi_range(1, 2)
		qty = min(qty, _bud_left)
		if qty <= 0:
			NotificationSystem.warn("Out of product.")
			return
		cash = qty * CASH_PER_GRAM
		_eyeball_loss += float(qty) * _rng.randf_range(0.0, EYEBALL_TAX_MAX_PCT)
	else:
		# Pre-packaged: one bag per customer, fixed price, no tax.
		if _bud_left <= 0:
			NotificationSystem.warn("Out of product.")
			return
		qty = 1
		cash = CASH_PER_BAG

	_bud_left -= qty
	_cash_earned += cash
	Wallet.add(cash)
	DealerExperience.adjust(qty)

	SpotHeatTracker.record_deal(StreetDealSession.spot_id)

	var unit_label: String = "g" if is_raw else (" bag" if qty == 1 else " bags")
	NotificationSystem.warn("+$%d  (%d%s)" % [cash, qty, unit_label])

	if PagerSystem.has_pager and _rng.randf() < NEW_CUSTOMER_CHANCE_ON_ACCEPT:
		var new_cust = CustomerRoster.add_random_customer(0)
		if new_cust != null:
			NotificationSystem.warn("New contact: %s" % new_cust.display_name)

	_refresh_ui()


func _on_customer_freed(customer: Node) -> void:
	_live_customers.erase(customer)
	_refresh_speed()

func _refresh_speed() -> void:
	var should_speed: bool = _live_customers.is_empty() and _bud_left > 0
	if should_speed and not _speed_active:
		TimeSystem.push_speed(IDLE_SPEEDUP_MULT)
		_speed_active = true
	elif not should_speed and _speed_active:
		TimeSystem.pop_speed()
		_speed_active = false

# --- UI ---

func _refresh_ui() -> void:
	bud_label.text = "Bud: %d" % _bud_left
	cash_label.text = "Earned: $%d" % _cash_earned


# --- Exit ---

func _on_exit_pressed() -> void:
	_request_exit()


func _request_exit() -> void:
	if _speed_active:
		TimeSystem.pop_speed()
		_speed_active = false

	# Free any live actors so they don't tween into a freed scene.
	for c in _live_customers:
		if is_instance_valid(c):
			c.queue_free()
	_live_customers.clear()
	for c in _live_cops:
		if is_instance_valid(c):
			c.queue_free()
	_live_cops.clear()

	# Settle eyeball tax — deduct accumulated waste from leftover bud.
	var lost: int = int(round(_eyeball_loss))
	if lost > 0:
		lost = min(lost, _bud_left)
		_bud_left -= lost
		NotificationSystem.warn("Shorted yourself %dg (no scale)." % lost)

	_lock_player(false)
	StreetDealSession.end_session(_bud_left)


# --- Player freeze ---

func _lock_player(locked: bool) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and "input_locked" in player:
		player.input_locked = locked
		
func _try_spawn_cop() -> void:
	if StreetDealSession.spot_id == &"":
		print("[Cop] skipped — no spot_id")
		return
	var recent: int = SpotHeatTracker.recent_deal_count(StreetDealSession.spot_id)
	var chance: float = _cop_spawn_chance(recent)
	print("[Cop] spot=%s  recent=%d  chance=%.2f" % [StreetDealSession.spot_id, recent, chance])
	if recent <= 0:
		return  # first-deal protection: nothing recorded yet = no cops
	if _rng.randf() >= chance:
		return
	_spawn_cop()


func _cop_spawn_chance(recent: int) -> float:
	if recent <= 0:
		return 0.0
	return COP_CHANCE_MAX * (1.0 - exp(-COP_CHANCE_GROWTH * float(recent)))


func _spawn_cop() -> void:
	if StreetDealSession.spot_id == &"":
		return
	if _paths.is_empty():
		push_warning("StreetDealMinigame: no paths to spawn cop on")
		return

	var path: PackedVector2Array = _paths[_rng.randi() % _paths.size()]

	# Patrol points are stored in customer_layer space; cops want global.
	var patrol_points: Array[Vector2] = []
	for p in path:
		patrol_points.append(customer_layer.to_global(p))

	var cop: CopNPC = COP_PATROL_SCENE.instantiate()
	customer_layer.add_child(cop)

	# Suppress witness behavior for the minigame — the bust check is manual,
	# we don't want CrimeSystem firing pursuit on top.
	var wc := cop.get_node_or_null("WitnessComponent")
	if wc != null:
		WitnessRegistry.unregister(wc)

	cop.set_patrol(patrol_points)
	cop.patrol_finished.connect(cop.queue_free)
	cop.tree_exited.connect(_on_cop_freed.bind(cop))
	_live_cops.append(cop)


func _on_cop_freed(cop: Node) -> void:
	_live_cops.erase(cop)
	
func _on_crime_witnessed(_crime_id: int, crime_type: StringName, _pos: Vector2, _area: StringName, witness: WitnessComponent) -> void:
	if crime_type != &"weed_deal":
		return
	var observer: Node = witness.get_witness_owner()
	if not (observer is CopNPC):
		return
	if not _live_cops.has(observer):
		return
	_bust()
	
func _pick_archetype() -> CustomerArchetype:
	var archetypes: Array = StreetDealSession.archetypes
	var weights: Array = StreetDealSession.archetype_weights
	if archetypes.is_empty():
		return null

	var total: int = 0
	for i in range(min(archetypes.size(), weights.size())):
		total += max(0, weights[i])
	if total <= 0:
		# Fallback — uniform if weights are invalid.
		return archetypes[_rng.randi() % archetypes.size()]

	var roll: int = _rng.randi_range(1, total)
	var cumulative: int = 0
	for i in range(min(archetypes.size(), weights.size())):
		cumulative += max(0, weights[i])
		if roll <= cumulative:
			return archetypes[i]
	return archetypes[0]  # safety
	
	# --- Cop notice window ---

func _tick_notice(delta: float) -> void:
	if _busted:
		return
	var dealing: bool = _deal_in_progress()
	var player := get_tree().get_first_node_in_group("player")
	for cop in _live_cops:
		if not is_instance_valid(cop):
			continue
		var id: int = cop.get_instance_id()
		var has_los: bool = dealing and player != null and _cop_sees_player(cop, player)
		if not has_los:
			# Deal ended or LOS broke — reset, so backing off fully clears it.
			_cop_notice.erase(id)
			continue
		if not _cop_notice.has(id):
			var delay: float = _notice_delay_for(cop)
			var threshold: float = max(NOTICE_MIN, _rng.randf_range(0.0, delay))
			_cop_notice[id] = {"elapsed": 0.0, "threshold": threshold}
		var entry: Dictionary = _cop_notice[id]
		entry["elapsed"] += delta
		if entry["elapsed"] >= entry["threshold"]:
			_bust()
			return


func _deal_in_progress() -> bool:
	for c in _live_customers:
		if is_instance_valid(c) and c.has_method("is_dealing") and c.is_dealing():
			return true
	return false


func _cop_sees_player(cop: Node, player: Node2D) -> bool:
	var wc := cop.get_node_or_null("WitnessComponent")
	if wc != null and wc.has_method("can_witness"):
		return wc.can_witness(player)
	# No WC — fall back to a simple radius so cops still function.
	return cop.global_position.distance_to(player.global_position) < 200.0


func _notice_delay_for(cop: Node) -> float:
	if "profile" in cop and cop.profile != null \
			and "notice_delay" in cop.profile and cop.profile.notice_delay > 0.0:
		return cop.profile.notice_delay
	return COP_NOTICE_DELAY_FALLBACK


func _bust() -> void:
	if _busted:
		return
	_busted = true
	NotificationSystem.warn("Busted! Lost all product.")
	for c in _live_customers:
		if is_instance_valid(c) and c.has_method("bust_cancel"):
			c.bust_cancel()
	_bud_left = 0
	_request_exit()
	
	
