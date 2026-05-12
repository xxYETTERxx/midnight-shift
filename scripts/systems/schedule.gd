class_name Schedule
extends Resource

# Time-indexed location plan for one NPC. Plain dict of minute-of-day → entry.
# Entry shape:
#   STAND:   {"activity": "stand", "scene_path": "...", "marker": &"id", "facing": "..."}
#   TRANSIT: {"activity": "transit", "scene_path": "...", "route": [&"start_id", &"end_id"]}
# Missing "activity" defaults to "stand".
#
# Each entry's window runs from its key to the next key (wrapping past
# midnight as needed). TRANSIT duration is implicit — the span between
# this entry's key and the next.

@export var entries: Dictionary = {}


# Returns the entry dict in effect at the given calendar minute_of_day, or
# {} if the schedule is empty.
func entry_at(minute_of_day: int) -> Dictionary:
	return entry_window_at(minute_of_day).get("entry", {})


# Returns {entry, start_minute, end_minute}. end_minute may be >= 1440 if
# the window wraps past midnight; callers handling fractional time should
# shift their query forward by 1440 in that case.
func entry_window_at(minute_of_day: int) -> Dictionary:
	if entries.is_empty():
		return {}
	var keys: Array = entries.keys()
	keys.sort()

	# Latest key <= query, defaulting to last key (wrap from previous day).
	var chosen_idx: int = keys.size() - 1
	for i in range(keys.size()):
		if keys[i] <= minute_of_day:
			chosen_idx = i
		else:
			break

	var start: int = keys[chosen_idx]
	var next_idx: int = (chosen_idx + 1) % keys.size()
	var end: int = keys[next_idx]
	# Wrap: if the next entry is "tomorrow's first," advance end by a day.
	if end <= start:
		end += 1440

	return {
		"entry": entries[start],
		"start_minute": start,
		"end_minute": end,
	}


# True if the schedule places the NPC in `scene_path` at the given minute.
func is_in_scene_at(scene_path: String, minute_of_day: int) -> bool:
	return entry_at(minute_of_day).get("scene_path", "") == scene_path
