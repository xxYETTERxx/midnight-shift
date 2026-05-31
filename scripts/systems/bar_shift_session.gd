extends Node

# Cross-scene handoff for a bartending shift. Twin of StreetDealSession:
# stores return info + shift length, fades into the mock bar scene, and on
# exit fades back and reports whether the shift was completed.
#
# "Completed" = the shift clock ran its full length. If the player exits
# early, completed is false. This layer does NOT decide what an incomplete
# shift costs (strikes, lost wage) — that's the employment system's job.
# Tips are settled inside the minigame via Wallet during the shift.

const MINIGAME_SCENE_PATH: String = "res://scenes/minigames/bar_minigame.tscn"

# Emitted after the scene has been torn down and the player restored.
signal shift_ended(completed: bool)

var active: bool = false

# Session inputs.
var shift_hours: int = 4
var return_room_path: String = ""
var return_position: Vector2 = Vector2.ZERO

# Absolute game-clock minute the shift ends at (start + shift_hours).
var _end_total_minutes: int = 0


# Called to start a shift. For now this is invoked from a debug trigger; the
# employment system will own this call later.
func begin_session(
	p_shift_hours: int,
	p_return_room: String,
	p_return_pos: Vector2
) -> void:
	if active:
		push_warning("BarShiftSession: already active")
		return
	active = true
	shift_hours = p_shift_hours
	return_room_path = p_return_room
	return_position = p_return_pos
	_end_total_minutes = TimeSystem.total_minutes + shift_hours * 60

	await ScreenFade.fade_out(0.4)
	RoomManager.change_room(MINIGAME_SCENE_PATH, "default")
	await ScreenFade.fade_in(0.4)


# The absolute clock minute the shift ends at. The scene polls this.
func end_minute() -> int:
	return _end_total_minutes


# Called by the minigame scene on exit. completed = did the clock run out
# (true) vs. player bailed early (false).
func end_session(completed: bool) -> void:
	if not active:
		return
	active = false

	await ScreenFade.fade_out(0.4)
	RoomManager.change_room(return_room_path, "default")

	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		player.global_position = return_position

	return_room_path = ""
	return_position = Vector2.ZERO
	_end_total_minutes = 0

	await ScreenFade.fade_in(0.4)
	shift_ended.emit(completed)
