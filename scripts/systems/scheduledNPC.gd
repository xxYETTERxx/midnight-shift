@tool
class_name ScheduledNPC
extends NPC

# Schedule-aware NPC. NPCDirector pushes pose updates via set_stand or
# set_transit. STAND is a one-shot teleport + idle anim; TRANSIT stores a
# start/end pair and uses _process to lerp position each frame, giving
# smooth movement that doesn't snap to minute ticks.

var _transit_active: bool = false
var _transit_start_pos: Vector2 = Vector2.ZERO
var _transit_end_pos: Vector2 = Vector2.ZERO
var _transit_start_minute: int = 0
var _transit_end_minute: int = 0


func set_stand(position: Vector2, facing: String) -> void:
	_transit_active = false
	global_position = position
	_play_animation("idle", facing)


func set_transit(start_pos: Vector2, end_pos: Vector2, start_minute: int, end_minute: int) -> void:
	_transit_start_pos = start_pos
	_transit_end_pos = end_pos
	_transit_start_minute = start_minute
	_transit_end_minute = end_minute
	_transit_active = true
	_update_transit_pose()


func _process(_delta: float) -> void:
	if _transit_active:
		_update_transit_pose()


func _update_transit_pose() -> void:
	var span: int = _transit_end_minute - _transit_start_minute
	if span <= 0:
		global_position = _transit_end_pos
		return
	var current: float = _shifted_minute_of_day()
	var fraction: float = clampf(
		(current - float(_transit_start_minute)) / float(span),
		0.0, 1.0,
	)

	var delta := _transit_end_pos - _transit_start_pos
	var dx: float = abs(delta.x)
	var dy: float = abs(delta.y)

	var pos: Vector2
	var facing: String

	if dx <= 0.0001:
		# Pure vertical — no L needed.
		pos = _transit_start_pos.lerp(_transit_end_pos, fraction)
		facing = "south" if delta.y > 0 else "north"
	elif dy <= 0.0001:
		# Pure horizontal — no L needed.
		pos = _transit_start_pos.lerp(_transit_end_pos, fraction)
		facing = "east" if delta.x > 0 else "west"
	else:
		# L-path: walk all of the X distance, then all of the Y distance.
		# Time is split proportional to Manhattan distance so the apparent
		# walking speed stays constant across the corner.
		var seg1_end_frac: float = dx / (dx + dy)
		if fraction <= seg1_end_frac:
			var sub: float = fraction / seg1_end_frac
			pos = Vector2(
				lerpf(_transit_start_pos.x, _transit_end_pos.x, sub),
				_transit_start_pos.y,
			)
			facing = "east" if delta.x > 0 else "west"
		else:
			var sub: float = (fraction - seg1_end_frac) / (1.0 - seg1_end_frac)
			pos = Vector2(
				_transit_end_pos.x,
				lerpf(_transit_start_pos.y, _transit_end_pos.y, sub),
			)
			facing = "south" if delta.y > 0 else "north"

	global_position = pos
	_play_animation("walk", facing)


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
