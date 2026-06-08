extends Node

# Cross-scene handoff for working the lemonade-stand front. Twin of
# BarShiftSession / StreetDealSession: stores return info, fades into the
# stand scene, fades back on exit. No "completed" concept — the player works
# until they choose to leave (lemonade is unlimited; weed is inventory-gated).

const MINIGAME_SCENE_PATH: String = "res://scenes/minigames/lemonade_minigame.tscn"

# Tunables — per-front config could override these later.
const LEMONADE_PRICE: int = 1          # clean, to bank
const WEED_PRICE: int = 10             # dirty, to cash
const WEED_CUSTOMER_RATIO: float = 0.4 # fraction of arrivals who want weed
const WEED_SERVE_HEAT: float = 4.0     # heat per weed serve at this area
const WRONG_WEED_HEAT: float = 15.0    # offering weed to a lemonade buyer

var active: bool = false
var return_room_path: String = ""
var return_position: Vector2 = Vector2.ZERO
var area_id: StringName = &""

signal shift_ended()


func begin_session(p_return_room: String, p_return_pos: Vector2, p_area_id: StringName) -> void:
	if active:
		push_warning("LemonadeStandSession: already active")
		return
	active = true
	return_room_path = p_return_room
	return_position = p_return_pos
	area_id = p_area_id

	await ScreenFade.fade_out(0.4)
	RoomManager.change_room(MINIGAME_SCENE_PATH, "default")
	await ScreenFade.fade_in(0.4)


func end_session() -> void:
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
	var ended_area := area_id
	area_id = &""

	await ScreenFade.fade_in(0.4)
	shift_ended.emit()
