extends Node

const JOB_FLAG: String = "has_job"
const SHIFT_LENGTH_HOURS: int = 4
const MIN_HOURS_OUT: int = 12
const MAX_HOURS_OUT: int = 36

const STRIKE_LIMIT: int = 2   # strikes beyond this (i.e. the 3rd) fires you
const FIRED_FLAG: String = "fired"

const EARLIEST_START_HOUR: int = 15   # 2pm
const LATEST_START_HOUR: int = 1      # 1am
const GRACE_MINUTES: int = 15   # minutes after shift start you can still clock in

# True once the player has clocked into the current scheduled shift, so the
# missed-shift check doesn't strike a shift that's being/been worked.
var _clocked_in: bool = false

var strikes: int = 0
var next_shift_minute: int = -1
var _rng := RandomNumberGenerator.new()

signal shift_scheduled(start_total_minutes: int)

func _ready() -> void:
	_rng.seed = Time.get_ticks_usec()
	SaveSystem.register_savable("employment", self)
	RelationshipSystem.global_flag_changed.connect(_on_global_flag_changed)
	TimeSystem.week_rolled.connect(_on_week_rolled)
	TimeSystem.minute_tick.connect(_on_minute_tick)
	BarShiftSession.shift_ended.connect(on_shift_ended)
	CollapseSystem.collapsed.connect(_collapsed)
	# Catch the case where the flag was already set before we connected.
	if RelationshipSystem.get_global_flag(JOB_FLAG) and next_shift_minute < 0:
		_schedule_next_shift()


func _on_global_flag_changed(flag: String, value: bool) -> void:
	print("[Employment] flag_changed: %s = %s" % [flag, value])
	if flag != JOB_FLAG:
		return
	if value:
		_schedule_next_shift()
	else:
		next_shift_minute = -1


func has_shift_scheduled() -> bool:
	return next_shift_minute >= 0


func _schedule_next_shift() -> void:
	_clocked_in = false
	var base: int = TimeSystem.total_minutes
	var raw_offset_min: int = _rng.randi_range(MIN_HOURS_OUT * 60, MAX_HOURS_OUT * 60)
	var candidate: int = _snap_to_legal_start(base + raw_offset_min)
	next_shift_minute = candidate
	print("[Employment] scheduled shift at %s (minute %d)" %
		[MeetingManager.format_minute(next_shift_minute), next_shift_minute])
	shift_scheduled.emit(next_shift_minute)


func _snap_to_legal_start(minute: int) -> int:
	var m: int = int(ceil(minute / 60.0)) * 60
	for _i in range(48):
		if _is_legal_start_hour(_clock_hour_of(m)):
			return m
		m += 60
	return m


func _is_legal_start_hour(hour: int) -> bool:
	return hour >= EARLIEST_START_HOUR or hour <= LATEST_START_HOUR


# Clock hour for an absolute minute, matching TimeSystem's 14:00 wake convention.
func _clock_hour_of(minute: int) -> int:
	return ((minute + TimeSystem.START_HOUR * 60) % 1440) / 60

# Records a missed/late shift. Strikes accumulate within a week (reset on week
# roll). The strike that pushes the count past STRIKE_LIMIT fires the player.
func record_strike() -> void:
	if not RelationshipSystem.get_global_flag(JOB_FLAG):
		return  # not employed — nothing to strike against
	strikes += 1
	print("[Employment] strike recorded (%d)" % strikes)
	if strikes > STRIKE_LIMIT:
		_fire()
	else:
		NotificationSystem.warn("Missed shift. Strike %d of %d." % [strikes, STRIKE_LIMIT + 1])

func _collapsed(cause:int, sum: String ) -> void:
	record_strike()
	on_shift_ended(false)
		

func _fire() -> void:
	strikes = 0
	next_shift_minute = -1
	RelationshipSystem.set_global_flag(FIRED_FLAG, true)
	RelationshipSystem.set_global_flag(JOB_FLAG, false)
	NotificationSystem.warn("Missed shift — you're fired.")
	print("[Employment] fired")


func _on_week_rolled(_week: int) -> void:
	if strikes > 0:
		print("[Employment] week rolled, strikes reset (was %d)" % strikes)
	strikes = 0

func _on_minute_tick(_total: int) -> void:
	if next_shift_minute < 0:
		return
	if _clocked_in:
		return
	# Window closes at start + grace. If we're past it and never clocked in,
	# that's a missed shift.
	if TimeSystem.total_minutes > next_shift_minute + GRACE_MINUTES:
		_miss_shift()


# True when the player can currently clock in: shift time has arrived and the
# grace window hasn't closed. The bar clock-in interactable gates on this.
func can_clock_in() -> bool:
	if next_shift_minute < 0 or _clocked_in:
		return false
	var now: int = TimeSystem.total_minutes
	return now >= next_shift_minute - GRACE_MINUTES \
		and now <= next_shift_minute + GRACE_MINUTES


# Called by the bar clock-in interactable when the player starts the shift.
func clock_in() -> void:
	if not can_clock_in():
		return
	_clocked_in = true
	# Launch the minigame. Return info is captured by the clock-in node itself
	# (it knows the bar return position); here we just mark attendance.


# Called when BarShiftSession reports the shift ended. completed is informational
# for now — attendance is what matters for strikes. Either way the shift is done,
# so schedule the next one (if still employed).
func on_shift_ended(_completed: bool) -> void:
	_clocked_in = false
	next_shift_minute = -1
	if RelationshipSystem.get_global_flag(JOB_FLAG):
		_schedule_next_shift()


func _miss_shift() -> void:
	print("[Employment] shift missed at %s" % MeetingManager.format_minute(next_shift_minute))
	_clocked_in = false
	next_shift_minute = -1
	record_strike()
	# record_strike fires (clears has_job) at the limit. Only reschedule if we
	# survived — i.e. still employed.
	if RelationshipSystem.get_global_flag(JOB_FLAG):
		_schedule_next_shift()


func save_state() -> Dictionary:
	return {
		"next_shift_minute": next_shift_minute,
		"strikes": strikes,
		"clocked_in": _clocked_in,
	}


func load_state(data: Dictionary) -> void:
	next_shift_minute = data.get("next_shift_minute", -1)
	strikes = data.get("strikes", 0)
	_clocked_in = data.get("clocked_in", false)
	# Heal: if we're employed but somehow have no scheduled shift (e.g. a save
	# from before employment state was persisted), schedule one now.
	if RelationshipSystem.get_global_flag(JOB_FLAG) and next_shift_minute < 0:
		_schedule_next_shift()
