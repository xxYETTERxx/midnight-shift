extends Node

# Mirror of HungerSystem / ThirstSystem with stamina-specific rules.
# Unlike hunger/thirst (constant decay), stamina decay depends on whether
# the player is moving and which movement mode is active. The player pushes
# its movement state in each physics frame via set_movement_state(); we
# read that on minute_tick to compute the drain.

const MAX_VALUE: float = 100.0
const PASSIVE_DRAIN_PER_MINUTE: float = 0.07
const MOVEMENT_DRAIN_PER_MINUTE: float = 0.05
const SKATEBOARD_DRAIN_MULTIPLIER: float = 0.4

# Sprint and vault are spent directly via spend() — no per-minute tick.
const SPRINT_DRAIN_PER_SECOND: float = 10.0
const VAULT_COST: float = 2.0

const SLEEP_RESTORE_SAFE_FRAC: float = 1.0
const SLEEP_RESTORE_UNSAFE_FRAC: float = 0.5

var current: float = MAX_VALUE
var _max: float = MAX_VALUE

# Player updates these each physics frame so minute-tick drain reflects
# the player's current movement context.
var _is_moving: bool = false
var _movement_mode: StringName = &""

# Re-entry guard so a spend that lands on 0 can't recursively fire collapse.
var _collapsing: bool = false

signal stamina_changed(current: float, maximum: float)
signal collapsed()


func _ready() -> void:
	SaveSystem.register_savable("stamina_system", self)
	TimeSystem.minute_tick.connect(_on_minute_tick)
	TimeSkipSystem.time_skipped.connect(_on_time_skipped)


# --- Public API ---

func current_value() -> float:
	return current

func maximum() -> float:
	return _max

# Permanent cap change (future: stamina+ consumables, skill rewards).
func set_maximum(new_max: float) -> void:
	_max = max(1.0, new_max)
	current = clampf(current, 0.0, _max)
	stamina_changed.emit(current, _max)

func is_exhausted() -> bool:
	return current <= 0.0

# Player pushes its movement state each physics frame so decay rate
# can adapt without the system needing a back-pointer to the player.
func set_movement_state(is_moving: bool, mode: StringName = &"") -> void:
	_is_moving = is_moving
	_movement_mode = mode

func spend(amount: float) -> void:
	if amount == 0.0:
		return
	current = clampf(current - amount, 0.0, _max)
	stamina_changed.emit(current, _max)
	if current <= 0.0 and not _collapsing:
		_collapsing = true
		collapsed.emit()
		_collapsing = false

func restore(amount: float) -> void:
	if amount == 0.0:
		return
	current = clampf(current + amount, 0.0, _max)
	stamina_changed.emit(current, _max)

# Hard set — used by CollapseSystem to drop player to 50% post-exhaustion.
func set_value(value: float) -> void:
	current = clampf(value, 0.0, _max)
	stamina_changed.emit(current, _max)


# --- Decay ---

func _on_minute_tick(_total: int) -> void:
	var drain := PASSIVE_DRAIN_PER_MINUTE
	if _is_moving:
		var movement_drain := MOVEMENT_DRAIN_PER_MINUTE
		if _movement_mode == &"skateboard":
			movement_drain *= SKATEBOARD_DRAIN_MULTIPLIER
		drain += movement_drain
	spend(drain)


func _on_time_skipped(_from_min: int, _to_min: int, context: Dictionary) -> void:
	if context.get("kind", "") != "sleep":
		return
	var safe: bool = context.get("safe", true)
	# A sleep source can cap how much it restores TO (bed = full, sleeping
	# bag = 80). Absent a cap, default to full max. Unsafe sleep still halves
	# the *gain*, layered on top of whatever the source allows.
	var restore_cap: float = float(context.get("restore_to", _max))
	restore_cap = clampf(restore_cap, 0.0, _max)
	if current >= restore_cap:
		return  # already at or above what this sleep can give
	var gain: float = restore_cap - current
	if not safe:
		gain *= SLEEP_RESTORE_UNSAFE_FRAC
	restore(gain)


# --- Save / load ---

func save_state() -> Dictionary:
	return {"current": current, "max": _max}

func load_state(data: Dictionary) -> void:
	_max = data.get("max", MAX_VALUE)
	current = data.get("current", _max)
	stamina_changed.emit(current, _max)
