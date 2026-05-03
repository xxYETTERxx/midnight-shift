extends ColorRect

# Color stops keyed by hour (0-23). Between stops, we interpolate.
# Tune these by feel. Hours not listed inherit from the previous stop.
const COLOR_STOPS: Array = [
	{ "hour":  0, "color": Color(0.05, 0.08, 0.20, 0.55) },  # midnight: deep blue
	{ "hour":  4, "color": Color(0.10, 0.12, 0.25, 0.60) },  # 4 AM: deepest, coldest
	{ "hour":  6, "color": Color(0.40, 0.45, 0.55, 0.30) },  # 6 AM: predawn pale
	{ "hour":  8, "color": Color(1.00, 0.95, 0.85, 0.05) },  # 8 AM: warm clear morning
	{ "hour": 14, "color": Color(1.00, 0.99, 0.96, 0.02) },  # 2 PM: barely warm
	{ "hour": 16, "color": Color(1.00, 0.96, 0.88, 0.06) },  # 4 PM: gentle warm
	{ "hour": 18, "color": Color(1.00, 0.85, 0.65, 0.15) },  # 6 PM: warm
	{ "hour": 19, "color": Color(0.95, 0.70, 0.50, 0.22) },  # 7 PM: golden hour
	{ "hour": 20, "color": Color(0.80, 0.50, 0.50, 0.30) },  # 8 PM: rose dusk
	{ "hour": 21, "color": Color(0.45, 0.35, 0.50, 0.40) },  # 9 PM: muted dusk
	{ "hour": 23, "color": Color(0.10, 0.12, 0.30, 0.50) },  # 11 PM: into night
]


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	_refresh()
	TimeSystem.minute_tick.connect(_on_minute_tick)


func _on_minute_tick(_total: int) -> void:
	_refresh()


func _refresh() -> void:
	color = _color_for_minute(TimeSystem.current_hour(), TimeSystem.current_minute())


func _color_for_minute(hour: int, minute: int) -> Color:
	# Find the two stops surrounding the current time and lerp between them.
	var t_now := hour + minute / 60.0

	var prev_stop: Dictionary = COLOR_STOPS[COLOR_STOPS.size() - 1]
	var next_stop: Dictionary = COLOR_STOPS[0]

	# Find the stop just before and just after t_now.
	for i in range(COLOR_STOPS.size()):
		var stop: Dictionary = COLOR_STOPS[i]
		if stop["hour"] <= t_now:
			prev_stop = stop
			next_stop = COLOR_STOPS[(i + 1) % COLOR_STOPS.size()]

	# Compute lerp factor between prev and next, accounting for wrap-around.
	var prev_h: float = prev_stop["hour"]
	var next_h: float = next_stop["hour"]
	if next_h <= prev_h:
		next_h += 24.0  # wrap: e.g., prev at 23, next at 0 → treat as 24

	var t: float = (t_now - prev_h) / (next_h - prev_h)
	t = clampf(t, 0.0, 1.0)

	return prev_stop["color"].lerp(next_stop["color"], t)
