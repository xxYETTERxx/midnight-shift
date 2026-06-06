extends Node

# Default fade duration. Callers can override per-skip via context.
const DEFAULT_FADE_DURATION: float = 1.5

# Emitted after time has advanced and listeners should react.
# from: total_minutes before the skip
# to: total_minutes after the skip
# context: caller-provided dictionary with arbitrary metadata
signal time_skipped(from_minute: int, to_minute: int, context: Dictionary)


# The main API. Skips time to target_minute (in TimeSystem's total_minutes
# scale), with a fade in/out and signal emission for listeners.
#
# context can include:
#   "fade_duration": float     - override fade time (default 0.5s)
#   "kind": String             - "sleep" / "arrest" / "fast_travel" / "event_skip"
#   "safe": bool               - sleep-specific: at home (full restore) vs not
#   "voluntary": bool          - sleep-specific: bed (true) vs forced (false)
#   "destination": Variant     - caller-defined: where the player ends up
#   ... whatever else callers want listeners to see
#
# context is passed through unchanged to listeners.
func skip_to(target_minute: int, context: Dictionary = {}) -> void:
	if target_minute <= TimeSystem.total_minutes:
		push_warning("TimeSkipSystem.skip_to called with non-future time")
		return

	var landing_tod: int = (target_minute + TimeSystem.START_HOUR * 60) % 1440
	if landing_tod > 6 * 60 and landing_tod < 14 * 60:
		target_minute = _next_wake_minute()
	var fade_duration: float = context.get("fade_duration", DEFAULT_FADE_DURATION)
	var from_minute := TimeSystem.total_minutes

	TimeSystem.pause()

	await ScreenFade.fade_out(fade_duration)

	TimeSystem.advance_to(target_minute)

	# Fire the signal while screen is still black, so listeners can do their
	# work (move NPCs, advance plants, restore stamina, reposition player)
	# before the screen reveals the new state.
	time_skipped.emit(from_minute, target_minute, context)

	await ScreenFade.fade_in(fade_duration)

	TimeSystem.resume()

func _next_wake_minute() -> int:
	var wake_hour: int = 14
	var now_tod: int = (TimeSystem.total_minutes + TimeSystem.START_HOUR * 60) % 1440
	var wake_tod: int = wake_hour * 60
	var delta: int = wake_tod - now_tod
	if delta <= 0:
		delta += 1440
	return TimeSystem.total_minutes + delta

# Convenience wrapper: skip by a delta rather than to an absolute time.
# Useful for "sleep 8 hours" or "wait 30 minutes" cases.
func skip_by(minutes: int, context: Dictionary = {}) -> void:
	await skip_to(TimeSystem.total_minutes + minutes, context)
