extends Node

# Court summons obligation. Fires when SuspicionSystem's weekly roll lands a
# court date. Modeled on EmploymentSystem's scheduled-obligation pattern, with
# a page/callback front half (the player learns of it like a pager page —
# "Unknown" — and returns the call to acknowledge).
#
# Lifecycle (all within one week, so no overlap guard needed — rolls are weekly):
#   IDLE     — nothing pending.
#   PAGED    — summons issued; "Unknown" page waiting. Player must return the
#              call within CALLBACK_DEADLINE_MIN waking minutes, or it's ditched.
#   CONFIRMED— call returned, court time acknowledged (imposed, not chosen).
#              Player must reach the bus stop by court time, or it's ditched.
#
# Resolution:
#   attend()         — bus stop interact while CONFIRMED. Lowers suspicion,
#                      clears flag, notifies. Arc done.
#   ditch (callback
#   expired OR court
#   time passed)     — writes a confirmed ditched_court ledger entry + sets the
#                      courtdate_missed flag. The event builder handles the rest.

enum State { IDLE, PAGED, CONFIRMED }

# How far out the imposed court date sits from the summons (game-hours), snapped
# to a daytime hour so the player isn't told to show up at 4am.
const COURT_HOURS_OUT_MIN: int = 24
const COURT_HOURS_OUT_MAX: int = 48
const COURT_EARLIEST_HOUR: int = 9
const COURT_LATEST_HOUR: int = 16

# Reuse the pager callback deadline — 6 waking hours to return the Unknown call.
const CALLBACK_DEADLINE_MIN: int = 6 * 60

# Suspicion removed for actually showing up. Attending is the player facing it;
# the visible meter cools hard. (permanent_record is untouched in SuspicionSystem.)
const ATTEND_SUSPICION_RELIEF: float = 60.0

const MISSED_FLAG: String = "courtdate_missed"

var _state: int = State.IDLE
var _court_minute: int = -1        # imposed court time (absolute minute)
var _callback_deadline: int = -1   # absolute minute the Unknown page expires

signal court_paged()               # "Unknown" page arrived — HUD/pager hook
signal court_confirmed(court_minute: int)
signal court_resolved()            # attended or ditched — UI can clear

func _ready() -> void:
	SaveSystem.register_savable("court_summons", self)
	SuspicionSystem.court_date_triggered.connect(_on_court_date_triggered)
	TimeSystem.minute_tick.connect(_on_minute_tick)


func has_pending() -> bool:
	return _state != State.IDLE


func court_minute() -> int:
	return _court_minute


# --- Summons -----------------------------------------------------------

func _on_court_date_triggered() -> void:
	# Weekly cadence means an arc always resolves before the next roll, so a
	# fresh trigger while non-IDLE shouldn't happen — but if it somehow does,
	# don't stomp an in-progress arc.
	if _state != State.IDLE:
		return
	_court_minute = _roll_court_minute()
	_callback_deadline = TimeSystem.total_minutes + CALLBACK_DEADLINE_MIN
	_state = State.PAGED
	print("[Court] PAGED — court at %s, callback by %s" % [
		MeetingManager.format_minute(_court_minute),
		MeetingManager.format_minute(_callback_deadline),
	])
	court_paged.emit()


func _roll_court_minute() -> int:
	var raw: int = TimeSystem.total_minutes + randi_range(
		COURT_HOURS_OUT_MIN * 60, COURT_HOURS_OUT_MAX * 60)
	# Snap forward to a legal daytime court hour.
	var m: int = int(ceil(raw / 60.0)) * 60
	for _i in range(48):
		var hour: int = ((m + TimeSystem.START_HOUR * 60) % 1440) / 60
		if hour >= COURT_EARLIEST_HOUR and hour <= COURT_LATEST_HOUR:
			return m
		m += 60
	return m


# --- Callback (returning the Unknown call) -----------------------------

# Called when the player returns the call at the payphone/callback panel.
# Acknowledges the imposed court time. No slot-picking — court isn't negotiated.
func return_call() -> void:
	if _state != State.PAGED:
		return
	_state = State.CONFIRMED
	_callback_deadline = -1
	print("[Court] CONFIRMED for %s" % MeetingManager.format_minute(_court_minute))
	NotificationSystem.warn("Court date confirmed for %s. Be at the bus stop." %
		MeetingManager.format_minute(_court_minute))
	court_confirmed.emit(_court_minute)


# --- Attendance (bus stop interact) ------------------------------------

# Called by the bus stop while a court date is CONFIRMED. For now this directly
# runs the attend effect; later it'll open a panel that calls this on confirm.
func attend() -> void:
	if _state != State.CONFIRMED:
		return
	SuspicionSystem.reduce(ATTEND_SUSPICION_RELIEF)
	NotificationSystem.info("You made your court date.")
	print("[Court] ATTENDED — suspicion relieved")
	_reset()
	court_resolved.emit()

func can_attend() -> bool:
	return _state == State.CONFIRMED

# --- Miss watchers -----------------------------------------------------

func _on_minute_tick(_total: int) -> void:
	var now: int = TimeSystem.total_minutes
	match _state:
		State.PAGED:
			if _callback_deadline >= 0 and now > _callback_deadline:
				_ditch("never returned the call")
		State.CONFIRMED:
			if _court_minute >= 0 and now > _court_minute:
				_ditch("missed the court date")
		_:
			pass


# Both failure modes collapse here: confirmed ditched ledger entry + flag set
# immediately (no waiting to be hauled in). The event builder drives whatever
# happens next off the courtdate_missed flag.
func _ditch(reason: String) -> void:
	print("[Court] DITCHED — %s" % reason)
	CrimeSystem.record_ditched_court()
	RelationshipSystem.set_global_flag(MISSED_FLAG, true)
	_reset()
	court_resolved.emit()


func _reset() -> void:
	_state = State.IDLE
	_court_minute = -1
	_callback_deadline = -1


# --- Save / load -------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"state": _state,
		"court_minute": _court_minute,
		"callback_deadline": _callback_deadline,
	}


func load_state(data: Dictionary) -> void:
	_state = data.get("state", State.IDLE)
	_court_minute = data.get("court_minute", -1)
	_callback_deadline = data.get("callback_deadline", -1)
