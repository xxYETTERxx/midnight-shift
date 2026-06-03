extends Node

# Hidden personal-suspicion meter (design doc §25.1). NOT police heat — this
# is the slow "does this person make sense" tide that a future audit/detective
# event reads. No number on the HUD; the player feels it through symptoms,
# surfaced via suspicion_band_changed.
#
# This system is a pure SINK. It does not know what an ATM or a front is, does
# not track cleaning caps, and does not reset anything weekly except its own
# clean-week flag. Laundering channels own their caps/tallies and report only
# the dollar overage here; CrimeSystem owns the rap sheet and reports only the
# fact-of-a-reported-crime here. Two entry points, one formula each.

# --- Tuning ---

# Suspicion gained per "1.0 proportional overage" (i.e. cleaning exactly one
# full cap's worth over the cap). overage_fraction = over_dollars / cap, so a
# 50%-over deposit at any cap size yields 0.5 * OVERAGE_K. Scales with the
# player's world for free: the dollar figure grows, the proportion is what bites.
const OVERAGE_K: float = 20.0

# Flat suspicion per reported witnessed crime. Cop sightings build a case;
# a nosy neighbour's report is a lesser mark.
const SUSPICION_COP: float = 12.0
const SUSPICION_NPC: float = 5.0

# Discrete amount walked off on a fully clean week (no suspicion added at all
# that week). A notch, not a reset — a long dirty streak takes sustained
# laying-low to undo. The permanent record never decays.
const CLEAN_WEEK_DECAY: float = 15.0

const SUSPICION_MAX: float = 100.0
const SUSPICION_EPSILON: float = 0.01

# Band thresholds. Index = band. Crossing a band edge fires the symptom signal.
const BAND_THRESHOLDS: Array[float] = [0.0, 25.0, 50.0, 75.0]

const SUSPICION_PER_LEGIT_HOUR: float = 4.0

# Below this, suspicion is a warning zone only — tiers drive story/environmental
# nudges to cool down, but no court date can trigger. At or above, the weekly
# roll uses _suspicion directly as the percent chance of being hauled in.
const COURT_THRESHOLD: float = 25.0

# How much of the visible meter a court date burns off. You've faced the music
# for what you'd accrued — the roll shouldn't re-fire next week on the same
# heat. The permanent record is untouched (the audit still remembers).
const COURT_SUSPICION_RELIEF: float = 60.00


# --- State ---

# The decaying visible-through-symptoms meter.
var _suspicion: float = 0.0

# Never decays. Every add() writes here; sinks and decay never touch it. The
# audit/detective system reads this later to reach through a "clean" present
# into a dirty past. Write-only for now.
var _permanent_record: float = 0.0

# Reset each week-roll. Gates the clean-week decay: any add() this week sets it.
var _suspicion_added_this_week: bool = false

var _last_band: int = 0

# Emitted only on band-edge crossings — the hook for ambient symptoms. The
# raw value is deliberately not broadcast (hidden meter).
signal suspicion_band_changed(new_band: int)
signal court_date_triggered()


func _ready() -> void:
	SaveSystem.register_savable("suspicion", self)
	TimeSystem.week_rolled.connect(_on_week_rolled)


# --- Intake: financial (called by laundering channels) ---

# A channel cleaned past its cap. over_dollars is the newly-over portion the
# channel already computed (charging only the not-yet-charged slice this week);
# cap is that channel's weekly capacity, used solely as the proportionality
# denominator. The breach is scored on proportion, so the same percentage over
# stings equally at a $200 ATM or a $4000 front.
func report_overage(over_dollars: int, cap: int) -> void:
	if over_dollars <= 0 or cap <= 0:
		return
	var fraction: float = float(over_dollars) / float(cap)
	_add(fraction * OVERAGE_K)


# --- Intake: witnessed crime (called by CrimeSystem) ---

# CrimeSystem owns the cop/NPC determination and the NPC report roll; by the
# time it calls here the decision to report has already been made. We just
# add the right amount.
func report_witnessed_crime(is_cop: bool) -> void:
	_add(SUSPICION_COP if is_cop else SUSPICION_NPC)

# Called by any legit job on completion. hours = in-game hours the job
# committed (bar shift length, delivery window used, etc.). Cools the visible
# meter only — the permanent record never moves, so the audit still remembers
# however clean you've made yourself look.
func report_legit_work(hours: float) -> void:
	if hours <= 0.0:
		return
	reduce(hours * SUSPICION_PER_LEGIT_HOUR)

# --- Intake: explicit sinks ---

# Legit wages, certain quest completions. Reduces the visible meter only; the
# permanent record is untouched (laying low cools you, it doesn't erase history).
func reduce(amount: float) -> void:
	if amount <= 0.0:
		return
	_set_suspicion(_suspicion - amount)


# Quest hook — can push either direction.
func apply_delta(amount: float) -> void:
	if amount > 0.0:
		_add(amount)
	elif amount < 0.0:
		reduce(-amount)


# --- Reads (for the future audit; no HUD number) ---

func band() -> int:
	return _band_for(_suspicion)


func permanent_record() -> float:
	return _permanent_record


# --- Internal ---

func _add(amount: float) -> void:
	if amount <= 0.0:
		return
	_permanent_record += amount
	_suspicion_added_this_week = true
	_set_suspicion(_suspicion + amount)


func _set_suspicion(value: float) -> void:
	var prev: float = _suspicion
	_suspicion = clampf(value, 0.0, SUSPICION_MAX)
	if _suspicion < SUSPICION_EPSILON:
		_suspicion = 0.0
	if is_equal_approx(prev, _suspicion):
		return
	var prev_band: int = _band_for(prev)
	var new_band: int = _band_for(_suspicion)
	if new_band != prev_band:
		_last_band = new_band
		suspicion_band_changed.emit(new_band)


func _band_for(value: float) -> int:
	var b: int = 0
	for i in range(BAND_THRESHOLDS.size()):
		if value >= BAND_THRESHOLDS[i]:
			b = i
	return b


func _on_week_rolled(_week: int) -> void:
	# Clean-week decay first — laying low this week should lower the odds
	# before we roll them.
	if not _suspicion_added_this_week:
		_set_suspicion(_suspicion - CLEAN_WEEK_DECAY)
	_suspicion_added_this_week = false

	# Court-date roll. Immune below the threshold; at/above, _suspicion IS the
	# percent chance.
	if _suspicion >= COURT_THRESHOLD:
		if randf() * 100.0 < _suspicion:
			_trigger_court_date()

func _trigger_court_date() -> void:
	# SEAM: the notification + obligation flow lands here next. For now just
	# announce it and burn off the visible meter so we don't double-jeopardy
	# the player next week. permanent_record deliberately untouched.
	print("[Suspicion] COURT DATE triggered at suspicion=%.1f" % _suspicion)
	court_date_triggered.emit()
	_set_suspicion(_suspicion - COURT_SUSPICION_RELIEF)

# --- Save / load ---

func save_state() -> Dictionary:
	return {
		"suspicion": _suspicion,
		"permanent_record": _permanent_record,
		"added_this_week": _suspicion_added_this_week,
	}


func load_state(data: Dictionary) -> void:
	_suspicion = float(data.get("suspicion", 0.0))
	_permanent_record = float(data.get("permanent_record", 0.0))
	_suspicion_added_this_week = bool(data.get("added_this_week", false))
	_last_band = _band_for(_suspicion)
