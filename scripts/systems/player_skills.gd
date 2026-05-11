extends Node

# PlayerSkills — capability-progression spine.
#
# Distinct from XP tracks (DealerExperience, CriminalExperience), which gate
# *content* (new customers, new contacts). Skills gate *capability and access*
# — speed, carry, traversal, detection.
#
# All skills owned via a single dict keyed by skill id. Adding a new skill
# is a SKILL_CONFIG entry plus the trigger wiring in the source system.
# Save/load is one flat dict.
#
# Visibility:
# - No "+1 Athletics" popups.
# - One-time notification on each configured level threshold.
# - Optional dedicated screen (deferred).

signal skill_changed(skill_id: StringName, new_xp: int)
signal level_up(skill_id: StringName, new_level: int)
signal capability_unlocked(capability: StringName)

# --- Tuning constants (easily tweakable) ---

# Athletics multiplies player base speed by 1.0 + level * this.
# 0.01 = +1% per level = 1.5x at L50.
const SPEED_PER_ATHLETICS_LEVEL: float = 0.015

# XP per pixel of player movement. With speed=80 px/s, ~9.6 XP per in-game
# minute of continuous movement at 0.002. Tune after playtesting.
const ATHLETICS_XP_PER_PIXEL: float = 0.002
const STRENGTH_XP_PER_PIXEL_PER_SLOT: float = 0.001

# Inventory progression — strength level thresholds and starting size.
const STARTING_INVENTORY_SLOTS: int = 6
const STRENGTH_SLOT_THRESHOLDS: Array[int] = [10, 20, 30, 40, 50]
const SLOTS_PER_THRESHOLD: int = 6

const LOCKPICK_DURATION_REDUCTION_PER_LEVEL: float = 0.012

# --- Skill config ---
# Each entry:
#   max_level          — cap; levels are 0..max_level
#   capabilities       — { level: capability_id } unlocked at that level
#   threshold_messages — { level: one-time notification string }
#   per_day_cap        — int XP-gain ceiling per day, -1 == uncapped
const SKILL_CONFIG := {
	&"athletics": {
		"max_level": 50,
		"capabilities": {
			10: &"vault_low",
			25: &"vault_medium",
			50: &"vault_high",
		},
		"threshold_messages": {
			10: "You feel quicker on your feet.",
			25: "Low fences don't even slow you down anymore.",
			50: "Your stride is effortless. Nothing in the neighborhood looks unreachable.",
		},
		"per_day_cap": -1,
	},
	&"strength": {
		"max_level": 50,
		"capabilities": {
			10: &"carry_12",
			20: &"carry_18",
			30: &"carry_24",
			40: &"carry_30",
			50: &"carry_36",
		},
		"threshold_messages": {
			10: "Your arms feel stronger. You can carry more.",
			20: "A heavy load barely slows you down anymore.",
			30: "Your back has set. You can haul real weight.",
			40: "The weight hardly registers.",
			50: "You can carry whatever the job needs.",
		},
		"per_day_cap": -1,
	},
		&"lockpicking": {
		"max_level": 50,
		"capabilities": {},
		"threshold_messages": {
			15: "Your hands move faster on a lock now.",
			35: "Locks barely slow you down.",
		},
		"per_day_cap": -1,
	},
}

# --- Runtime state ---

var _xp: Dictionary = {}             # StringName -> int
var _level: Dictionary = {}          # StringName -> int (cached)
var _capabilities: Dictionary = {}   # StringName -> true (set membership)
var _xp_today: Dictionary = {}       # StringName -> int (resets each day)
var _xp_fractional: Dictionary = {}  # StringName -> float
var _last_cap_reset_day: int = -1


func _ready() -> void:
	for skill_id in SKILL_CONFIG.keys():
		_xp[skill_id] = 0
		_level[skill_id] = 0
		_xp_today[skill_id] = 0
		_xp_fractional[skill_id] = 0.0
	SaveSystem.register_savable("player_skills", self)


# --- Public API ----------------------------------------------------------

func value(skill_id: StringName) -> int:
	return _xp.get(skill_id, 0)


func tier(skill_id: StringName) -> int:
	# "tier" here == discrete integer level 0..max_level.
	# (XP tracks use 'tier' for their 0..3 bucket — different concept.)
	return _level.get(skill_id, 0)


func max_level(skill_id: StringName) -> int:
	if not SKILL_CONFIG.has(skill_id):
		return 0
	return SKILL_CONFIG[skill_id].get("max_level", 0)


func has_capability(capability: StringName) -> bool:
	return _capabilities.has(capability)


func adjust(skill_id: StringName, delta: int) -> void:
	if delta == 0 or not SKILL_CONFIG.has(skill_id):
		return
	_check_day_rollover()
	if delta > 0:
		var cap: int = SKILL_CONFIG[skill_id].get("per_day_cap", -1)
		if cap > 0:
			var remaining: int = cap - _xp_today.get(skill_id, 0)
			if remaining <= 0:
				return
			delta = min(delta, remaining)
	
	var prev_level: int = _level.get(skill_id, 0)
	var prev_xp: int = _xp.get(skill_id, 0)
	_xp[skill_id] = max(0, prev_xp + delta)
	if delta > 0:
		_xp_today[skill_id] = _xp_today.get(skill_id, 0) + delta
	
	_level[skill_id] = _compute_level(skill_id, _xp[skill_id])
	skill_changed.emit(skill_id, _xp[skill_id])
	
	var new_level: int = _level[skill_id]
	if new_level > prev_level:
		for lvl in range(prev_level + 1, new_level + 1):
			_handle_level_up(skill_id, lvl)


# Fractional XP accumulator. Carries the sub-1 remainder between calls so
# per-frame distance accumulation doesn't spam signals.
func adjust_f(skill_id: StringName, delta: float) -> void:
	if delta == 0.0 or not SKILL_CONFIG.has(skill_id):
		return
	var acc: float = _xp_fractional.get(skill_id, 0.0) + delta
	var whole: int = int(acc)
	if whole != 0:
		adjust(skill_id, whole)
		acc -= float(whole)
	_xp_fractional[skill_id] = acc


# --- Effect helpers ------------------------------------------------------

func speed_multiplier() -> float:
	return 1.0 + tier(&"athletics") * SPEED_PER_ATHLETICS_LEVEL
	
func inventory_slot_count() -> int:
	var lvl: int = tier(&"strength")
	var bonus: int = 0
	for threshold in STRENGTH_SLOT_THRESHOLDS:
		if lvl >= threshold:
			bonus += SLOTS_PER_THRESHOLD
	return STARTING_INVENTORY_SLOTS + bonus

func lockpick_duration_multiplier() -> float:
	return maxf(0.1, 1.0 - tier(&"lockpicking") * LOCKPICK_DURATION_REDUCTION_PER_LEVEL)


# --- Internals -----------------------------------------------------------

func _compute_level(skill_id: StringName, xp: int) -> int:
	var max_lvl: int = SKILL_CONFIG[skill_id].get("max_level", 0)
	var lvl: int = 0
	while lvl < max_lvl and xp >= _xp_required_for_level(lvl + 1):
		lvl += 1
	return lvl


func _xp_required_for_level(n: int) -> int:
	# Cumulative XP to reach level n.
	# round(20 * pow(n, 1.6)). L1=20, L10=~795, L25=~3789, L50=~12649.
	# Swap for a hand-tuned array if numbers stop feeling right.
	if n <= 0:
		return 0
	return int(round(20.0 * pow(float(n), 1.6)))


# Public alias for UI / progress bars.
func xp_for_level(n: int) -> int:
	return _xp_required_for_level(n)


func _handle_level_up(skill_id: StringName, new_level: int) -> void:
	level_up.emit(skill_id, new_level)
	var cfg: Dictionary = SKILL_CONFIG[skill_id]
	var caps: Dictionary = cfg.get("capabilities", {})
	if caps.has(new_level):
		var capability: StringName = caps[new_level]
		_capabilities[capability] = true
		capability_unlocked.emit(capability)
	var messages: Dictionary = cfg.get("threshold_messages", {})
	if messages.has(new_level):
		NotificationSystem.info(messages[new_level])


func _check_day_rollover() -> void:
	# Lazy reset on next XP gain after the in-game day rolls. No signal
	# coupling; just reads TimeSystem.total_minutes.
	var day_idx: int = TimeSystem.total_minutes / (24 * 60)
	if day_idx != _last_cap_reset_day:
		_last_cap_reset_day = day_idx
		for k in _xp_today.keys():
			_xp_today[k] = 0


# --- Save / load ---------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"xp": _xp.duplicate(),
		"xp_today": _xp_today.duplicate(),
		"xp_fractional": _xp_fractional.duplicate(),
		"capabilities": _capabilities.keys(),
		"last_cap_reset_day": _last_cap_reset_day,
	}


func load_state(data: Dictionary) -> void:
	# Re-init from config first so new skills added after save still get
	# clean entries; then overlay saved values.
	_xp.clear()
	_level.clear()
	_xp_today.clear()
	_xp_fractional.clear()
	_capabilities.clear()
	for skill_id in SKILL_CONFIG.keys():
		_xp[skill_id] = 0
		_level[skill_id] = 0
		_xp_today[skill_id] = 0
		_xp_fractional[skill_id] = 0.0
	
	for k in data.get("xp", {}).keys():
		_xp[StringName(k)] = data["xp"][k]
	for k in data.get("xp_today", {}).keys():
		_xp_today[StringName(k)] = data["xp_today"][k]
	for k in data.get("xp_fractional", {}).keys():
		_xp_fractional[StringName(k)] = data["xp_fractional"][k]
	for c in data.get("capabilities", []):
		_capabilities[StringName(c)] = true
	_last_cap_reset_day = data.get("last_cap_reset_day", -1)
	
	# Recompute cached levels from XP — keeps them in sync if config
	# thresholds changed between save and load.
	for skill_id in _xp.keys():
		_level[skill_id] = _compute_level(skill_id, _xp[skill_id])
		skill_changed.emit(skill_id, _xp[skill_id])
	
	
