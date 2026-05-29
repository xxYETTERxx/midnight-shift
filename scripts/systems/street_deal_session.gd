extends Node

# Orchestrates the cross-scene "post up at a dealing spot" minigame.
# Owns: return-room info, bud banked into the session, spot config.
# Holds NO live customer state — that lives on the minigame scene itself.

const WEED_BUDS_ID: StringName = &"weed_buds"
const DIME_BAG_ID: StringName = &"dime_bag_full"

# What the player is selling this session. Set by deal_spot at intake.
# Determines pricing and whether eyeball tax applies.
var product_id: StringName = &""

const MINIGAME_SCENE_PATH: String = "res://scenes/minigames/"

var spot_id: StringName = &""

var active: bool = false

# Session inputs — set by deal_spot.begin_session()
var bud_in_session: int = 0
var area_id: StringName = &""
var return_room_path: String = ""
var return_position: Vector2 = Vector2.ZERO

var spawn_interval_minutes: float = 30.0
var archetypes: Array = []
var archetype_weights: Array = []
var cop_check_interval_minutes: float = 30.0


# Called by DealSpot on interact.
# Caller already deducted bud_count from the player's real inventory.
func begin_session(
	bud_count: int,
	p_product_id: StringName,
	p_spot_id: StringName,
	p_area_id: StringName,
	p_return_room: String,
	p_return_pos: Vector2,
	p_spawn_interval_minutes: float,
	p_archetypes: Array,
	p_archetype_weights: Array,
	p_cop_check_interval_minutes: float
) -> void:
	if active:
		push_warning("StreetDealSession: already active")
		return
	active = true
	bud_in_session = bud_count
	product_id = p_product_id
	spot_id = p_spot_id
	area_id = p_area_id
	return_room_path = p_return_room
	return_position = p_return_pos
	spawn_interval_minutes = p_spawn_interval_minutes
	archetypes = p_archetypes
	archetype_weights  = p_archetype_weights
	cop_check_interval_minutes = p_cop_check_interval_minutes  

	await ScreenFade.fade_out(0.4)
	RoomManager.change_room(MINIGAME_SCENE_PATH+spot_id+".tscn", "default")
	await ScreenFade.fade_in(0.4)


# Called by the minigame scene on exit.
# bud_left is whatever the player didn't sell. Cash earned has already been
# deposited per-deal via Wallet.add() during the session.
func end_session(bud_left: int) -> void:
	if not active:
		return
	active = false
	spot_id = &""
	area_id = &""

	await ScreenFade.fade_out(0.4)
	RoomManager.change_room(return_room_path, "default")

	# Deposit leftover bud, position player at the deal spot.
	var player := get_tree().get_first_node_in_group("player")
	if player != null:
		player.global_position = return_position
		if bud_left > 0:
			var item := ItemRegistry.get_item(product_id)
			if item != null:
				var leftover: int = player.inventory.add(item, bud_left)
				if leftover > 0:
					push_warning("StreetDealSession: %d %s didn't fit on return" % [leftover, item.display_name])

	bud_in_session = 0
	area_id = &""
	return_room_path = ""
	archetypes = []
	archetype_weights = []
	return_position = Vector2.ZERO

	await ScreenFade.fade_in(0.4)
