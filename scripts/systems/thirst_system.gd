extends Node

# Mirror of HungerSystem with thirst-specific rates and signals.
# See HungerSystem for design rationale.

const MAX_VALUE: float = 100.0
const DECAY_PER_HOUR: float = 3.00
const SLEEP_DECAY_MULT: float = 0.3   # was 1.0
const SLEEP_DECAY_CAP: float = 40.0   # NEW

const THRESH_PARCHED: float = 50.0
const THRESH_THIRSTY: float = 25.0
const THRESH_DEHYDRATED: float = 10.0
const SPEED_THIRSTY: float = 0.75
const SPEED_DEHYDRATED: float = 0.50

const COLLAPSE_GRACE_MINUTES: int = 30

var current: float = MAX_VALUE
var _zero_minutes: int = 0
var _last_band: int = 0

signal thirst_changed(current: float, maximum: float)
signal threshold_crossed(band_name: String)
signal collapsed()


func _ready() -> void:
	SaveSystem.register_savable("thirst_system", self)
	TimeSystem.minute_tick.connect(_on_minute_tick)
	TimeSkipSystem.time_skipped.connect(_on_time_skipped)


func current_value() -> float:
	return current


func speed_multiplier() -> float:
	if current <= THRESH_DEHYDRATED:
		return SPEED_DEHYDRATED
	if current <= THRESH_THIRSTY:
		return SPEED_THIRSTY
	return 1.0


func restore(amount: float) -> void:
	if amount == 0.0:
		return
	current = clampf(current + amount, 0.0, MAX_VALUE)
	if amount > 0.0:
		_zero_minutes = 0
	thirst_changed.emit(current, MAX_VALUE)
	_check_band()


func is_dehydrated() -> bool:
	return current <= THRESH_DEHYDRATED


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
	thirst_changed.emit(current, MAX_VALUE)
	if current <= 0.0:
		_zero_minutes += 1
		if _zero_minutes >= COLLAPSE_GRACE_MINUTES:
			_zero_minutes = 0
			collapsed.emit()
	else:
		_zero_minutes = 0
	if not was_zero:
		_check_band()


func _check_band() -> void:
	var band: int = 0
	if current <= THRESH_DEHYDRATED:
		band = 3
	elif current <= THRESH_THIRSTY:
		band = 2
	elif current <= THRESH_PARCHED:
		band = 1
	if band > _last_band:
		match band:
			1: threshold_crossed.emit("parched")
			2: threshold_crossed.emit("thirsty")
			3: threshold_crossed.emit("dehydrated")
	_last_band = band


func save_state() -> Dictionary:
	return {"current": current, "zero_minutes": _zero_minutes, "last_band": _last_band}


func load_state(data: Dictionary) -> void:
	current = data.get("current", MAX_VALUE)
	_zero_minutes = data.get("zero_minutes", 0)
	_last_band = data.get("last_band", 0)
	thirst_changed.emit(current, MAX_VALUE)
