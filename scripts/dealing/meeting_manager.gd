extends Node

# Schedules and tracks meetings between the player and customers. Picks a free
# (spot, time) pair when a callback is returned, listens for the time window
# to elapse, and fires status transitions. Spawning the meet NPC is chunk 4.

const MIN_HOURS_OUT: int = 3
const RANDOM_HOUR_JITTER: int = 6
const MEETING_WINDOW_MINUTES: int = 60
const MAX_SEARCH_HOURS: int = 48

const SLEEP_START_HOUR: int = 6
const SLEEP_END_HOUR: int = 14

const CUSTOMER_WALK_SPEED: float = 70.0
const SECONDS_PER_MINUTE: int = 60

# spot_id (as String) → { display_name, scene_path, x, y }
var _spots: Dictionary = {}
var _spot_route_distances: Dictionary = {}

# meeting_id (as String) → Meeting
var _meetings: Dictionary = {}

var _next_meeting_id: int = 1
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


signal meeting_scheduled(meeting: Meeting)
signal meeting_spawning(meeting: Meeting)   # walk-in phase — customer should appear
signal meeting_started(meeting: Meeting)    # sale window opens
signal meeting_missed(meeting: Meeting)
signal meeting_completed(meeting: Meeting)





func _ready() -> void:
	SaveSystem.register_savable("meeting_manager", self)
	_rng.seed = Time.get_ticks_usec()
	TimeSystem.minute_tick.connect(_on_minute_tick)


# --- Spot registry ---

func register_spot(id: StringName, display_name: String, scene_path: String, world_pos: Vector2) -> void:
	if id == &"":
		return
	_spots[String(id)] = {
		"display_name": display_name,
		"scene_path": scene_path,
		"x": world_pos.x,
		"y": world_pos.y,
	}


func get_spot_info(id: StringName) -> Dictionary:
	return _spots.get(String(id), {})


func get_spot_display_name(id: StringName) -> String:
	return _spots.get(String(id), {}).get("display_name", "")


func registered_spot_ids() -> Array:
	var result: Array = []
	for k in _spots.keys():
		result.append(StringName(k))
	return result

func register_route_distances(spot_id: StringName, distances: Array) -> void:
	if spot_id == &"":
		return
	_spot_route_distances[String(spot_id)] = distances

# --- Scheduling ---

# Picks one spot (shuffled, first with capacity) and returns up to
# `count` free future time slots at that spot. Returns:
#   { "spot_id": StringName, "slots": Array[int] }   on success
#   {} (empty)                                       if no spot has any slot
# `slots` are absolute total_minutes values, sorted ascending.
func offer_slots(count: int = 5) -> Dictionary:
	if _spots.is_empty():
		push_warning("MeetingManager: no spots registered")
		return {}

	var spot_ids: Array = _spots.keys()
	spot_ids.shuffle()

	for spot_key in spot_ids:
		var spot_id := StringName(spot_key)
		var slots: Array = _free_slots_for_spot(spot_id, count)
		if not slots.is_empty():
			return {"spot_id": spot_id, "slots": slots}
	return {}


# Walks the search window for one spot, collecting free, non-sleep,
# quarter-hour-aligned candidate minutes until it has `count` of them.
func _free_slots_for_spot(spot_id: StringName, count: int) -> Array:
	var base_minute: int = TimeSystem.total_minutes + MIN_HOURS_OUT * 60
	# Round up to the next quarter hour so offered times read cleanly.
	var start_minute: int = int(ceil(base_minute / 15.0)) * 15

	var slots: Array = []
	var step: int = 0
	# Search in 15-minute increments across the window.
	var max_steps: int = (MAX_SEARCH_HOURS * 60) / 15
	while step < max_steps and slots.size() < count:
		var candidate: int = start_minute + step * 15
		step += 1
		if _is_in_sleep_window(candidate):
			continue
		if _spot_free_at(spot_id, candidate):
			slots.append(candidate)
	return slots


# Commits a player-chosen (spot, minute) slot. Returns the new Meeting, or
# null if the slot was taken in the meantime (e.g. another page scheduled it
# while the picker was open) or inputs are invalid.
func schedule_meeting_at(customer: Customer, quantity: int, spot_id: StringName, minute: int) -> Meeting:
	if customer == null:
		return null
	if not _spots.has(String(spot_id)):
		push_warning("MeetingManager: unknown spot %s" % spot_id)
		return null
	if _is_in_sleep_window(minute):
		push_warning("MeetingManager: chosen slot in sleep window")
		return null
	if not _spot_free_at(spot_id, minute):
		push_warning("MeetingManager: chosen slot no longer free")
		return null

	var m := Meeting.new()
	m.id = StringName("meet_%04d" % _next_meeting_id)
	_next_meeting_id += 1
	m.customer_id = customer.id
	m.spot_id = spot_id
	m.scheduled_minute = minute
	m.window_minutes = MEETING_WINDOW_MINUTES
	m.quantity_requested = quantity
	_compute_arrival(m)
	m.status = Meeting.Status.SCHEDULED

	_meetings[String(m.id)] = m
	print("[Meeting] Scheduled %s: %s at %s, %s (qty %d)" % [
		m.id, customer.display_name, get_spot_display_name(m.spot_id),
		format_minute(m.scheduled_minute), m.quantity_requested,
	])
	meeting_scheduled.emit(m)
	return m


# Legacy random-pick path. Kept for any non-player-driven callers (scripted
# events, debug). Player-facing callback flow now uses offer_slots +
# schedule_meeting_at.
func schedule_meeting(customer: Customer, quantity: int) -> Meeting:
	if _spots.is_empty():
		push_warning("MeetingManager: no spots registered")
		return null

	var slot := _find_available_slot()
	if slot.is_empty():
		push_warning("MeetingManager: no available slot found within search window")
		return null

	return schedule_meeting_at(customer, quantity, slot["spot_id"], slot["minute"])


func _find_available_slot() -> Dictionary:
	var base_minute: int = TimeSystem.total_minutes + MIN_HOURS_OUT * 60
	var jitter_hours: int = _rng.randi_range(0, RANDOM_HOUR_JITTER)
	var quarter: int = _rng.randi_range(0, 3) * 15
	var start_minute: int = base_minute + jitter_hours * 60 + quarter

	var spot_ids: Array = _spots.keys()
	spot_ids.shuffle()

	for hour_offset in range(0, MAX_SEARCH_HOURS):
		var candidate: int = start_minute + hour_offset * 60
		if _is_in_sleep_window(candidate):
			continue
		for spot_key in spot_ids:
			var spot_id := StringName(spot_key)
			if _spot_free_at(spot_id, candidate):
				return {"spot_id": spot_id, "minute": candidate}
	return {}


func _spot_free_at(spot_id: StringName, candidate_minute: int) -> bool:
	var candidate_end: int = candidate_minute + MEETING_WINDOW_MINUTES
	for m in _meetings.values():
		if m.status != Meeting.Status.SCHEDULED:
			continue
		if m.spot_id != spot_id:
			continue
		var existing_end: int = m.scheduled_minute + m.window_minutes
		if candidate_minute < existing_end and candidate_end > m.scheduled_minute:
			return false
	return true


func _is_in_sleep_window(minute: int) -> bool:
	# Game starts at 14:00, so total_minutes 0 = clock hour 14.
	var hour: int = ((minute + 14 * 60) % 1440) / 60
	return hour >= SLEEP_START_HOUR and hour < SLEEP_END_HOUR

# Picks a random arrival route for the meeting's spot, resolves its
# waypoints to compute path length, and sets m.spawn_minute and
# m.route_waypoints. Falls back to a teleport-at-spot (spawn_minute ==
# scheduled_minute, empty route) if no routes are authored or any
# waypoint fails to resolve.
# Picks a random arrival route for the meeting's spot and computes
# m.spawn_minute from the route's pre-measured distance (registered by
# MeetSpot on _ready). Stores the chosen waypoint chain on m so the
# spawner can re-resolve positions at materialize time.
#
# Falls back to teleport (spawn_minute == scheduled_minute, empty route)
# if no routes are authored, the chosen route is degenerate, or the
# spot's room hasn't loaded yet to register distances.
func _compute_arrival(m: Meeting) -> void:
	var routes: Array = CustomerRoutes.get_routes(m.spot_id)
	if routes.is_empty():
		m.spawn_minute = m.scheduled_minute
		m.route_waypoints = []
		return

	var idx: int = _rng.randi() % routes.size()
	var route_ids: Array = routes[idx]
	if route_ids.size() < 2:
		m.spawn_minute = m.scheduled_minute
		m.route_waypoints = []
		return

	var distances: Array = _spot_route_distances.get(String(m.spot_id), [])
	if idx >= distances.size() or distances[idx] <= 0.0:
		push_warning("MeetingManager: no precomputed distance for %s route %d — teleport" % [
			m.spot_id, idx,
		])
		m.spawn_minute = m.scheduled_minute
		m.route_waypoints = []
		return

	var total_dist: float = distances[idx]
	var walk_seconds: float = total_dist / CUSTOMER_WALK_SPEED
	var walk_game_minutes: float = walk_seconds / TimeSystem.real_seconds_per_minute
	var lead_minutes: int = int(ceil(walk_game_minutes))

	m.spawn_minute = m.scheduled_minute - lead_minutes
	m.route_waypoints = route_ids
	print("[MeetingManager] _compute_arrival spot=%s route=%d dist=%.0fpx walk=%.1fs lead=%d gmin" % [
		m.spot_id, idx, total_dist, walk_seconds, lead_minutes,
	])


# --- Tick / status transitions ---

func _on_minute_tick(_total: int) -> void:
	var now: int = TimeSystem.total_minutes
	var to_spawn: Array = []
	var to_start: Array = []
	var to_miss: Array = []
	for m in _meetings.values():
		if m.status != Meeting.Status.SCHEDULED:
			continue
		var window_end: int = m.scheduled_minute + m.window_minutes
		if now >= window_end:
			to_miss.append(m)
		elif now >= m.scheduled_minute:
			to_start.append(m)
		elif now >= m.spawn_minute:
			to_spawn.append(m)
	# Re-emit every minute during each phase — MeetingSpawner dedupes via
	# _live_npcs, so only the first does real work. Keeps spawn logic robust
	# to room changes mid-walk or mid-window.
	for m in to_spawn:
		meeting_spawning.emit(m)
	for m in to_start:
		meeting_started.emit(m)
	for m in to_miss:
		_mark_missed(m)
		
func visible_meetings_at(minute: int) -> Array:
	var result: Array = []
	for m in _meetings.values():
		if m.is_visible_at(minute):
			result.append(m)
	return result


func visible_meetings_now() -> Array:
	return visible_meetings_at(TimeSystem.total_minutes)


func _mark_missed(m: Meeting) -> void:
	m.status = Meeting.Status.MISSED
	var c: Customer = m.get_customer()
	if c != null:
		c.times_flaked += 1
		c.trust = max(c.trust - 10, -100)
	DealerExperience.penalize_missed_deal()
	print("[Meeting] MISSED: %s flaked on %s" %
		[c.display_name if c else "?", m.id])
	meeting_missed.emit(m)


# Chunk 4 will call this when the player completes a sale at the spot.
func mark_completed(meeting_id: StringName) -> void:
	var m: Meeting = _meetings.get(String(meeting_id))
	if m == null or m.status != Meeting.Status.SCHEDULED:
		return
	m.status = Meeting.Status.COMPLETED
	var c: Customer = m.get_customer()
	if c != null:
		c.times_dealt += 1
		c.trust = min(c.trust + 8, 100)
		c.affinity = min(c.affinity + 2, 100)
		var referred: Customer = CustomerRoster.try_referral_from(c)
		if referred != null:
			NotificationSystem.warn("%s referred a new contact: %s" % [
				c.display_name, referred.display_name,
			])
	DealerExperience.award_for_sale(m.quantity_requested)
	meeting_completed.emit(m)
	var spot_info: Dictionary = get_spot_info(m.spot_id)
	var pos: Vector2 = spot_info.get("position", Vector2.ZERO)
	var area: StringName = StringName(String(spot_info.get("scene_path", "")).get_file().get_basename())

func get_meeting(id: StringName) -> Meeting:
	return _meetings.get(String(id), null)

# --- Queries ---

func active_meetings_at(minute: int) -> Array:
	var result: Array = []
	for m in _meetings.values():
		if m.is_active_at(minute):
			result.append(m)
	return result


func active_meetings_now() -> Array:
	return active_meetings_at(TimeSystem.total_minutes)


func upcoming_meetings() -> Array:
	var result: Array = []
	for m in _meetings.values():
		if m.status == Meeting.Status.SCHEDULED \
		and m.scheduled_minute > TimeSystem.total_minutes:
			result.append(m)
	return result



# --- Formatting ---

func format_minute(minute: int) -> String:
	# Match TimeSystem's wake-to-wake convention: total_minutes 0 = 14:00 Mon Day 1,
	# game-day rolls at 14:00 not midnight, so a 02:00 calendar time is still
	# "Mon" if it's the early hours of the Tuesday calendar day.
	var day_idx: int = minute / 1440
	var dow: int = day_idx % 7
	var clock_min_of_day: int = (minute + 14 * 60) % 1440
	var hour: int = clock_min_of_day / 60
	var min_in_hour: int = clock_min_of_day % 60
	var day_names := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
	return "%s %02d:%02d" % [day_names[dow], hour, min_in_hour]


# --- Debug ---

func debug_print() -> void:
	print("[Meeting] %d spots, %d meetings" % [_spots.size(), _meetings.size()])
	for k in _spots:
		var s: Dictionary = _spots[k]
		print("  spot %s: %s @ (%.0f, %.0f)" % [k, s.get("display_name", ""), s.get("x", 0), s.get("y", 0)])
	var status_names := ["SCHEDULED", "COMPLETED", "MISSED"]
	for m in _meetings.values():
		var c: Customer = m.get_customer()
		print("  %s: %s @ %s, %s, qty %d, %s" % [
			m.id, c.display_name if c else "?", get_spot_display_name(m.spot_id),
			format_minute(m.scheduled_minute), m.quantity_requested,
			status_names[m.status],
		])
		print("[Meeting] Scheduled %s: %s at %s (spawn %s), %s (qty %d)" % [
		m.id, c.display_name, get_spot_display_name(m.spot_id),
		format_minute(m.spawn_minute), format_minute(m.scheduled_minute), m.quantity_requested,
	])
	


# --- Save/load ---

func save_state() -> Dictionary:
	var meeting_data: Array = []
	for m in _meetings.values():
		meeting_data.append(m.to_dict())
	return {
		"meetings": meeting_data,
		"spots": _spots.duplicate(true),
		"next_id": _next_meeting_id,
	}


func load_state(data: Dictionary) -> void:
	_meetings.clear()
	var meeting_data: Array = data.get("meetings", [])
	for entry in meeting_data:
		var m: Meeting = Meeting.from_dict(entry)
		_meetings[String(m.id)] = m
	var saved_spots = data.get("spots", {})
	if saved_spots is Dictionary:
		_spots = saved_spots.duplicate(true)
	_next_meeting_id = data.get("next_id", 1)
