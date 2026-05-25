extends Node

# Tracks completed deals per spot per day, with a rolling 3-day window.
# Used by the street deal minigame to scale cop spawn chance.

const HISTORY_DAYS: int = 3

# spot_id (String) -> { day_index (int) -> count (int) }
var _deals: Dictionary = {}


func _ready() -> void:
	SaveSystem.register_savable("spot_heat_tracker", self)
	TimeSystem.day_rolled.connect(_on_day_rolled)


func record_deal(spot_id: StringName) -> void:
	if spot_id == &"":
		return
	var key := String(spot_id)
	var today: int = TimeSystem.day_index()
	var spot_data: Dictionary = _deals.get(key, {})
	spot_data[today] = spot_data.get(today, 0) + 1
	_deals[key] = spot_data


func recent_deal_count(spot_id: StringName, days: int = HISTORY_DAYS) -> int:
	var key := String(spot_id)
	if not _deals.has(key):
		return 0
	var today: int = TimeSystem.day_index()
	var cutoff: int = today - days + 1  # today counts as day 1 of the window
	var total: int = 0
	for day in _deals[key].keys():
		if int(day) >= cutoff:
			total += _deals[key][day]
	return total


func _on_day_rolled(_dow: int, _dom: int) -> void:
	var today: int = TimeSystem.day_index()
	var cutoff: int = today - HISTORY_DAYS + 1
	for key in _deals.keys():
		var spot_data: Dictionary = _deals[key]
		for day in spot_data.keys():
			if int(day) < cutoff:
				spot_data.erase(day)
		if spot_data.is_empty():
			_deals.erase(key)


func save_state() -> Dictionary:
	return { "deals": _deals.duplicate(true) }


func load_state(data: Dictionary) -> void:
	_deals = data.get("deals", {}).duplicate(true)
