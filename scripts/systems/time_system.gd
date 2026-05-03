extends Node

# --- Tunables ---------------------------------------------------------

# How many real seconds equal one in-game minute.
# Stardew is roughly 0.7. Lower = faster days. Tune via export, not constant.
@export var real_seconds_per_minute: float = 0.7

# Display granularity — clock shows time rounded down to nearest N minutes.
# Internal logic still uses true minutes; this is a formatting concern only.
@export var display_minute_step: int = 10

# --- Constants --------------------------------------------------------

const MINUTES_PER_HOUR: int = 60
const HOURS_PER_DAY: int = 24
const MINUTES_PER_DAY: int = MINUTES_PER_HOUR * HOURS_PER_DAY  # 1440
const DAYS_PER_WEEK: int = 7
const DAYS_PER_MONTH: int = 28

const DAY_NAMES: Array[String] = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

# Game starts at Monday Day 1, 6:00 AM.
# total_minutes = 0 corresponds to 6:00 AM Mon Day 1.
const START_HOUR: int = 14

# Forced sleep happens at this hour (player must crash by dawn).
# Used by sleep system later — TimeSystem doesn't enforce it.
const FORCED_SLEEP_HOUR: int = 6

# --- State ------------------------------------------------------------

var total_minutes: int = 0
var _real_time_accumulator: float = 0.0
var _pause_count: int = 0

# --- Signals ----------------------------------------------------------

signal minute_tick(total_minutes: int)
signal hour_tick(hour: int, day_of_week: int, day_of_month: int)
signal day_rolled(day_of_week: int, day_of_month: int)

# --- Lifecycle --------------------------------------------------------

func _ready() -> void:
	SaveSystem.register_savable("time_system", self)

func _process(delta: float) -> void:
	if not is_running():
		return

	_real_time_accumulator += delta
	while _real_time_accumulator >= real_seconds_per_minute:
		_real_time_accumulator -= real_seconds_per_minute
		_advance_one_minute()

# --- Public API -------------------------------------------------------

func pause() -> void:
	_pause_count += 1

func resume() -> void:
	_pause_count = max(0, _pause_count - 1)

func is_running() -> bool:
	return _pause_count == 0

func advance_to(target_total_minutes: int) -> void:
	if target_total_minutes <= total_minutes:
		push_warning("TimeSystem.advance_to called with non-future time")
		return

	# Fire signals as if we ticked through each minute, but cheaply —
	# we don't loop minute-by-minute, we just fire the boundary signals
	# that any listeners care about (hour, day rolls).
	var old_hour := current_hour()
	var old_day := day_of_month()

	total_minutes = target_total_minutes
	_real_time_accumulator = 0.0

	# Always emit at least minute_tick so HUD updates.
	minute_tick.emit(total_minutes)

	if current_hour() != old_hour:
		hour_tick.emit(current_hour(), day_of_week(), day_of_month())

	if day_of_month() != old_day:
		day_rolled.emit(day_of_week(), day_of_month())

# --- Derived getters --------------------------------------------------

func current_hour() -> int:
	# Game starts at 6 AM, so total_minutes 0 = hour 6.
	var minute_of_day := (total_minutes + START_HOUR * MINUTES_PER_HOUR) % MINUTES_PER_DAY
	return minute_of_day / MINUTES_PER_HOUR

func current_minute() -> int:
	var minute_of_day := (total_minutes + START_HOUR * MINUTES_PER_HOUR) % MINUTES_PER_DAY
	return minute_of_day % MINUTES_PER_HOUR

func day_of_week() -> int:
	# 0 = Mon, 6 = Sun
	return day_index() % DAYS_PER_WEEK

func day_of_month() -> int:
	# 1-indexed (Day 1 .. Day 28)
	return (day_index() % DAYS_PER_MONTH) + 1

func day_index() -> int:
	# Total days since start, 0-indexed.
	# A "day" runs from wake time to wake time — i.e., 2 PM Mon
	# through 1:59 PM Tue is "Mon Day 1." Sleeping past 6 AM doesn't
	# advance the calendar; only crossing the next wake time does.
	return total_minutes / MINUTES_PER_DAY

func format_time() -> String:
	# Round display minute down to nearest display_minute_step.
	var disp_minute := (current_minute() / display_minute_step) * display_minute_step
	return "%02d:%02d" % [current_hour(), disp_minute]

func format_date() -> String:
	return "%s, Day %d" % [DAY_NAMES[day_of_week()], day_of_month()]

# --- Internal ---------------------------------------------------------

func _advance_one_minute() -> void:
	var old_hour := current_hour()
	var old_day := day_of_month()

	total_minutes += 1

	minute_tick.emit(total_minutes)

	if current_hour() != old_hour:
		hour_tick.emit(current_hour(), day_of_week(), day_of_month())

	if day_of_month() != old_day:
		day_rolled.emit(day_of_week(), day_of_month())

# --- Save System ---------------------------------------------------
func save_state() -> Dictionary:
	return {
		"total_minutes": total_minutes,
	}


func load_state(data: Dictionary) -> void:
	total_minutes = data.get("total_minutes", 0)
	_real_time_accumulator = 0.0
	# Emit a tick so the HUD refreshes
	minute_tick.emit(total_minutes)
