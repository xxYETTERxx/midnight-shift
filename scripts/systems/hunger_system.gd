extends Node

# Tracks the player's hunger. Decays passively over game-time. Decay
# halves during sleep. Drives a speed multiplier (worst-of with ThirstSystem).
# Hits zero sustained → collapse signal, picked up by HospitalSystem.

# Tunables — see design notes in chat.
const MAX_VALUE: float = 100.0
const DECAY_PER_HOUR: float = 12.5
const SLEEP_DECAY_MULT: float = 0.5   # was 1.0
const SLEEP_DECAY_CAP: float = 40.0   # NEW

# Threshold bands (current >= threshold means we're in that band).
const THRESH_PECKISH: float = 50.0   # mild notification
const THRESH_HUNGRY: float = 25.0    # speed 0.75
const THRESH_STARVING: float = 10.0  # speed 0.50
const SPEED_HUNGRY: float = 0.75
const SPEED_STARVING: float = 0.50

# How long (game minutes) the player can sit at zero before collapsing.
const COLLAPSE_GRACE_MINUTES: int = 30



var current: float = MAX_VALUE
var _zero_minutes: int = 0

# Previous band tracker so we only fire notification on threshold crossings,
# not on every tick.
var _last_band: int = 0  # 0=fed, 1=peckish, 2=hungry, 3=starving

signal hunger_changed(current: float, maximum: float)
signal threshold_crossed(band_name: String)
signal collapsed()


func _ready() -> void:
	SaveSystem.register_savable("hunger_system", self)
	TimeSystem.minute_tick.connect(_on_minute_tick)
	TimeSkipSystem.time_skipped.connect(_on_time_skipped)


# --- Public API ---

func current_value() -> float:
	return current


func speed_multiplier() -> float:
	if current <= THRESH_STARVING:
		return SPEED_STARVING
	if current <= THRESH_HUNGRY:
		return SPEED_HUNGRY
	return 1.0


func restore(amount: float) -> void:
	if amount <= 0.0:
		return
	current = clampf(current + amount, 0.0, MAX_VALUE)
	_zero_minutes = 0
	hunger_changed.emit(current, MAX_VALUE)
	_check_band()


func is_starving() -> bool:
	return current <= THRESH_STARVING


# --- Decay ---

func _on_minute_tick(_total: int) -> void:
	_decay(DECAY_PER_HOUR / 60.0)


func _on_time_skipped(from_min: int, to_min: int, context: Dictionary) -> void:
	var minutes: int = to_min - from_min
	if minutes <= 0:
		return
	var rate: float = DECAY_PER_HOUR / 60.0
	var total: float = rate * float(minutes)
	if context.get("kind", "") == "sleep":
		total *= SLEEP_DECAY_MULT
		total = min(total, SLEEP_DECAY_CAP)
	_decay(total)


func _decay(amount: float) -> void:
	var was_zero: bool = current <= 0.0
	current = clampf(current - amount, 0.0, MAX_VALUE)
	hunger_changed.emit(current, MAX_VALUE)
	if current <= 0.0:
		_zero_minutes += 1
		if _zero_minutes >= COLLAPSE_GRACE_MINUTES:
			_zero_minutes = 0
			collapsed.emit()
	else:
		_zero_minutes = 0
	if not was_zero:
		_check_band()


# --- Band tracking ---

func _check_band() -> void:
	var band: int = 0
	if current <= THRESH_STARVING:
		band = 3
	elif current <= THRESH_HUNGRY:
		band = 2
	elif current <= THRESH_PECKISH:
		band = 1
	if band > _last_band:
		match band:
			1: threshold_crossed.emit("peckish")
			2: threshold_crossed.emit("hungry")
			3: threshold_crossed.emit("starving")
	_last_band = band


# --- Save/load ---

func save_state() -> Dictionary:
	return {"current": current, "zero_minutes": _zero_minutes, "last_band": _last_band}


func load_state(data: Dictionary) -> void:
	current = data.get("current", MAX_VALUE)
	_zero_minutes = data.get("zero_minutes", 0)
	_last_band = data.get("last_band", 0)
	hunger_changed.emit(current, MAX_VALUE)
