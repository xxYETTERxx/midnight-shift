@tool
class_name ScheduledNPC
extends NPC

# Schedule-aware NPC. NPCDirector pushes pose updates via set_stand or
# set_transit. STAND is a one-shot teleport + idle anim; TRANSIT stores a
# start/end pair and uses _process to lerp position each frame, giving
# smooth movement that doesn't snap to minute ticks.

var _transit_active: bool = false
var _transit_points: Array[Vector2] = []
var _transit_cumulative: Array[float] = []  # cumulative Manhattan dist to each point (first = 0)
var _transit_total_distance: float = 0.0
var _transit_start_minute: int = 0
var _transit_end_minute: int = 0
var _transit_animation_prefix: String = "walk"


func set_stationary(position: Vector2, animation_name: String, facing: String) -> void:
	_transit_active = false
	global_position = position
	_play_animation(animation_name, facing)

func set_transit(points: Array[Vector2], start_minute: int, end_minute: int, animation_prefix: String = "walk") -> void:
	_transit_points = points
	_transit_start_minute = start_minute
	_transit_end_minute = end_minute
	_transit_animation_prefix = animation_prefix

	_transit_cumulative = [0.0]
	var total: float = 0.0
	for i in range(1, points.size()):
		var d: Vector2 = points[i] - points[i - 1]
		total += abs(d.x) + abs(d.y)
		_transit_cumulative.append(total)
	_transit_total_distance = total

	_transit_active = true
	_update_transit_pose()


func _process(_delta: float) -> void:
	if _transit_active:
		_update_transit_pose()


func _update_transit_pose() -> void:
	if _transit_points.size() < 2:
		return
	var span: int = _transit_end_minute - _transit_start_minute
	if span <= 0:
		global_position = _transit_points[-1]
		return
	if _transit_total_distance <= 0.0:
		global_position = _transit_points[-1]
		return

	var current: float = _shifted_minute_of_day()
	var fraction: float = clampf(
		(current - float(_transit_start_minute)) / float(span),
		0.0, 1.0,
	)
	var target_distance: float = fraction * _transit_total_distance

	# Find which leg the cursor is on — first leg whose cumulative distance
	# at its end-point exceeds the target. Linear walk is fine; routes are
	# small (handful of waypoints).
	var leg_idx: int = _transit_points.size() - 2  # default to last leg
	for i in range(1, _transit_cumulative.size()):
		if _transit_cumulative[i] >= target_distance:
			leg_idx = i - 1
			break

	var leg_start: Vector2 = _transit_points[leg_idx]
	var leg_end: Vector2 = _transit_points[leg_idx + 1]
	var leg_dist_start: float = _transit_cumulative[leg_idx]
	var leg_dist: float = _transit_cumulative[leg_idx + 1] - leg_dist_start

	if leg_dist <= 0.0:
		global_position = leg_start
		_play_animation(_transit_animation_prefix, "south")
		return

	var sub: float = (target_distance - leg_dist_start) / leg_dist
	global_position = leg_start.lerp(leg_end, sub)

	var delta: Vector2 = leg_end - leg_start
	var facing: String
	if abs(delta.x) > abs(delta.y):
		facing = "east" if delta.x > 0 else "west"
	else:
		facing = "south" if delta.y > 0 else "north"
	_play_animation(_transit_animation_prefix, facing)


# Returns fractional minute-of-day, shifted forward by 1440 if our window
# wraps midnight and the real clock is in the pre-midnight half.
func _shifted_minute_of_day() -> float:
	var raw: float = TimeSystem.current_fractional_minute() + 14.0 * 60.0
	var mod: float = fmod(raw, 1440.0)
	if mod < float(_transit_start_minute) and _transit_end_minute > 1440:
		mod += 1440.0
	return mod


func _facing_from_vector(delta: Vector2) -> String:
	if abs(delta.x) > abs(delta.y):
		return "east" if delta.x > 0 else "west"
	return "south" if delta.y > 0 else "north"


# Resolve to the most specific available animation, falling back to "idle"
# so NPCs without directional or walk anims still render correctly.
func _play_animation(prefix: String, facing: String) -> void:
	if not has_node("AnimatedSprite2D"):
		return
	var sprite: AnimatedSprite2D = $AnimatedSprite2D
	if sprite.sprite_frames == null:
		return
	var candidates: Array[String] = [
		"%s_%s" % [prefix, facing],
		prefix,
		"idle_%s" % facing,
		"idle",
	]
	for anim_name in candidates:
		if sprite.sprite_frames.has_animation(anim_name):
			if sprite.animation != anim_name:
				sprite.play(anim_name)
			return
