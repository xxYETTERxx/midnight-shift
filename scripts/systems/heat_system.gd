extends Node

# Per-area heat float. Crimes tick heat up; time ticks heat down via
# exponential decay. Heat governs cop spawn rate and patrol count (used
# by PoliceSystem). Persists across saves.
#
# Discrete heat bands gate downstream behaviors (max cop count, witness
# sensitivity). Bands derive from the float so the internal value can
# move smoothly while gameplay reads as discrete tiers.

signal heat_changed(area_id: StringName, new_heat: float)
signal heat_band_changed(area_id: StringName, new_band: int)

# Heat added per crime type. Tune via playtest.
# Per-crime-type heat config. witnessed_heat fires when a cop sees the act;
# unwitnessed_heat fires on COMPLETED outcome when no cop ever saw it
# (the "discovered later" case — applies to public crimes like car loots
# but not private ones like drug deals). CANCELLED unwitnessed crimes
# leak nothing — nobody knows it happened.
const CRIME_CONFIG: Dictionary = {
	&"weed_deal": {
		"witnessed_heat": 5.0,
		"unwitnessed_heat": 0.0,
	},
	&"car_loot": {
		"witnessed_heat": 8.0,
		"unwitnessed_heat": 2.5,
	},
}

const HEAT_MAX: float = 100.0

# Band thresholds (inclusive lower bound). 4 bands matching the doc's
# [1,2,3,4] patrol-count scaling, plus band 0 = "calm".
const BAND_THRESHOLDS: Array[float] = [0.0, 25.0, 50.0, 75.0]

# Per-game-minute decay factor. Half-life of 1 game day (1440 min) =
# heat halves every in-game day of inactivity. Tune freely.
const DECAY_HALF_LIFE_MINUTES: float = 1440.0

# Snap heat below this to zero to avoid forever-decaying floats.
const HEAT_EPSILON: float = 0.05

# area_id (String) -> float
var _heat: Dictionary = {}
# area_id (String) -> int (last broadcast band, for change-detect)
var _last_band: Dictionary = {}


func _ready() -> void:
	SaveSystem.register_savable("heat_system", self)
	TimeSystem.minute_tick.connect(_on_minute_tick)
	CrimeSystem.crime_witnessed.connect(_on_crime_witnessed)
	CrimeSystem.crime_ended.connect(_on_crime_ended)


# --- Public API ---------------------------------------------------------

func get_heat(area_id: StringName) -> float:
	return _heat.get(String(area_id), 0.0)


func get_heat_band(area_id: StringName) -> int:
	return _band_for(get_heat(area_id))


# Direct heat injection for non-crime sources (witness reports, structuring,
# repeat-location bonuses, etc.). Crimes route through CrimeSystem instead.
func add_heat(area_id: StringName, amount: float) -> void:
	if area_id == &"" or amount <= 0.0:
		return
	var key := String(area_id)
	var prev: float = _heat.get(key, 0.0)
	print("[HeatSystem] +%.2f → %s (was %.2f)" % [amount, area_id, prev])
	var next: float = clampf(prev + amount, 0.0, HEAT_MAX)
	_heat[key] = next
	_broadcast(area_id, prev, next)


# --- Crime / decay ------------------------------------------------------

func _on_crime_witnessed(_crime_id: int, crime_type: StringName, _position: Vector2, area_id: StringName, witness: WitnessComponent) -> void:
	var cfg: Dictionary = CRIME_CONFIG.get(crime_type, {})
	if cfg.is_empty():
		push_warning("HeatSystem: unknown crime type '%s'" % crime_type)
		return
	var base: float = float(cfg.get("witnessed_heat", 0.0))
	var multiplier: float = 1.0
	if witness != null:
		multiplier = witness.reaction_weight(crime_type)
	add_heat(area_id, base * multiplier)


func _on_crime_ended(_crime_id: int, crime_type: StringName, area_id: StringName, outcome: int, was_witnessed: bool) -> void:
	# Only completed, unwitnessed crimes leak the "discovered later" heat.
	if outcome != CrimeSystem.Outcome.COMPLETED:
		return
	if was_witnessed:
		return  # witness path already paid
	var cfg: Dictionary = CRIME_CONFIG.get(crime_type, {})
	var amount: float = float(cfg.get("unwitnessed_heat", 0.0))
	if amount > 0.0:
		add_heat(area_id, amount)


func _on_minute_tick(_total: int) -> void:
	if _heat.is_empty():
		return
	var factor: float = pow(0.5, 1.0 / DECAY_HALF_LIFE_MINUTES)
	for key in _heat.keys():
		var prev: float = _heat[key]
		if prev <= 0.0:
			continue
		var next: float = prev * factor
		if next < HEAT_EPSILON:
			next = 0.0
		_heat[key] = next
		_broadcast(StringName(key), prev, next)


# --- Helpers ------------------------------------------------------------

func _band_for(heat: float) -> int:
	var band: int = 0
	for i in range(BAND_THRESHOLDS.size()):
		if heat >= BAND_THRESHOLDS[i]:
			band = i
	return band


func _broadcast(area_id: StringName, prev: float, next: float) -> void:
	if not is_equal_approx(prev, next):
		heat_changed.emit(area_id, next)
	var key := String(area_id)
	var prev_band: int = _last_band.get(key, _band_for(prev))
	var new_band: int = _band_for(next)
	if new_band != prev_band:
		_last_band[key] = new_band
		heat_band_changed.emit(area_id, new_band)


# --- Save / load --------------------------------------------------------

func save_state() -> Dictionary:
	return {"heat": _heat.duplicate()}


func load_state(data: Dictionary) -> void:
	_heat = data.get("heat", {}).duplicate()
	_last_band.clear()
	for k in _heat.keys():
		_last_band[k] = _band_for(_heat[k])
