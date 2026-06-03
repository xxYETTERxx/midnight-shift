extends Node

# Player's overall dealing level. Goes up on completed sales (proportional to
# quantity sold), down on missed page returns and missed deals. The spine of
# progression for the whole game — gates pawn shop stock (§5), catalogue
# access (§5), and neighborhood slot events (§23). What the design doc calls
# "pager rep" lives here.

var xp: int = 0

# Tier thresholds. Index = tier number, value = xp needed to reach that tier.
# Tune freely. Tier 0 is always reached (starter customer territory).
const TIER_THRESHOLDS: Array[int] = [0, 30, 90, 180, 320, 520, 820, 1250]

# XP awarded per unit of product sold. Bigger orders feed tier progression
# faster — by design, the network growing IS the progression.
const XP_PER_UNIT_SOLD: int = 1

# Penalties for letting buyers down.
const XP_PENALTY_MISSED_CALLBACK: int = -2
const XP_PENALTY_MISSED_DEAL: int = -5

signal xp_changed(new_xp: int)
signal tier_unlocked(tier: int)

const STREET_SKILL_MAX_TIER: int = 5

func _ready() -> void:
	SaveSystem.register_savable("dealer_experience", self)


# --- Public API ---

func current_tier() -> int:
	var t := 0
	for i in range(TIER_THRESHOLDS.size()):
		if xp >= TIER_THRESHOLDS[i]:
			t = i
		else:
			break
	return t


func max_tier() -> int:
	return TIER_THRESHOLDS.size() - 1


# Called by the meeting/sale flow on a completed deal.
func award_for_sale(quantity_sold: int) -> void:
	if quantity_sold <= 0:
		return
	_change_xp(quantity_sold * XP_PER_UNIT_SOLD)


func penalize_missed_callback() -> void:
	_change_xp(XP_PENALTY_MISSED_CALLBACK)


func penalize_missed_deal() -> void:
	_change_xp(XP_PENALTY_MISSED_DEAL)


# Direct adjustment — useful for debug, also for any future systems that need
# to push DEX without going through the named penalty/award helpers.
func adjust(delta: int) -> void:
	_change_xp(delta)


# --- Internal ---

func _change_xp(delta: int) -> void:
	if delta == 0:
		return
	var prev_tier := current_tier()
	xp = max(0, xp + delta)
	xp_changed.emit(xp)
	var new_tier := current_tier()
	# Only emit tier_unlocked on *upward* crossings. Tier loss is silent —
	# customers from a lost tier stay in the roster but stop paging until
	# the player recovers (filtered in CustomerRoster.active_customers).
	if new_tier > prev_tier:
		for t in range(prev_tier + 1, new_tier + 1):
			NotificationSystem.info("You're getting better at this")
			tier_unlocked.emit(t)
			if t == 5:
				RelationshipSystem.set_global_flag("tier_5_reached",true)

func street_skill_fraction() -> float:
	return clampf(float(current_tier()) / float(STREET_SKILL_MAX_TIER), 0.0, 1.0)

# --- Save/load ---

func save_state() -> Dictionary:
	return {"xp": xp}


func load_state(data: Dictionary) -> void:
	xp = data.get("xp", 0)
	xp_changed.emit(xp)
