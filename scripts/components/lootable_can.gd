class_name LootableCan
extends Node2D

# A garbage/trash can the player can rummage through for bottles. Modeled on
# LootableCar but deliberately stripped down:
#   - no lock / slim jim
#   - no tier / loot table (yields a flat bottle_count rolled at spawn)
#   - NOT a crime: no CrimeSystem entry, no cop pursuit
#
# It keeps the hold-to-search progress bar for feel, and on a *successful*
# rummage does a light witness check: if any NPC can see the player in the
# act, a small amount of neighborhood heat is added. The fiction is that
# visible desperation makes the block feel less safe — it is ambient creep,
# not a pursuable offense.
#
# All cans always exist in the world. Whether a given can is *stocked* with
# bottles on a given day is decided by the spawner (a random subset each
# morning); an unstocked can simply reads as empty.

const ACTION_DURATION: float = 1.5

# Small neighborhood heat added when the player is seen rummaging. Tiny on
# purpose — this is slow ambient creep, not a spike. Tune via playtest.
const WITNESSED_HEAT: float = 1.0

# The crime_type string is reused only to query civilian reaction weights via
# the witness component; it is never registered with CrimeSystem. Civilians
# default to weight 1.0 for unknown types, so no per-NPC config is needed.
const SCAVENGE_WITNESS_TAG: StringName = &"scavenging"

@export var can_id: StringName = &""

# Bottles currently inside. 0 = empty (already searched today, or never
# stocked). Set by the spawner; inspector default is for hand-placed cans.
@export var bottle_count: int = 0

@onready var sprite: Sprite2D = $Sprite
@onready var interactable: Interactable = $Interactable
@onready var progress_bar: ProgressBar = $ProgressBar

var _searched: bool = false

# Active interaction state — non-null while the player holds to search.
var _action_player: Node = null
var _action_elapsed: float = 0.0

signal searched(drops: int)


func _ready() -> void:
	progress_bar.visible = false
	progress_bar.min_value = 0.0
	progress_bar.max_value = 1.0
	progress_bar.value = 0.0
	interactable.interacted.connect(_on_interacted)
	_refresh_visual_state()


func _process(delta: float) -> void:
	if _action_player == null:
		return
	# Cancel if the player walks too far away.
	if _action_player.global_position.distance_to(global_position) > 64.0:
		_cancel_action()
		return
	_action_elapsed += delta
	progress_bar.value = _action_elapsed / ACTION_DURATION
	if _action_elapsed >= ACTION_DURATION:
		_complete_action()


# --- Interaction --------------------------------------------------------

func _is_empty() -> bool:
	return _searched or bottle_count <= 0


func _on_interacted(player: Node) -> void:
	if _is_empty():
		return
	if _action_player != null:
		return  # already in progress
	_action_player = player
	_action_elapsed = 0.0
	progress_bar.visible = true
	progress_bar.value = 0.0


func _cancel_action() -> void:
	_action_player = null
	_action_elapsed = 0.0
	progress_bar.visible = false


func _complete_action() -> void:
	var player := _action_player
	_cancel_action()
	if player == null:
		return

	var inv: Inventory = player.get("inventory") if player else null
	var item: ItemDef = ItemRegistry.get_item(Bottle.BOTTLE_ITEM_ID)
	if inv == null or item == null:
		_mark_searched()
		return

	var leftover: int = inv.add(item, bottle_count)
	var added: int = bottle_count - leftover
	if added > 0:
		NotificationSystem.loot(item, added)
	if leftover > 0:
		# Inventory full — keep the remainder in the can so the player can
		# return with space. Don't mark searched.
		bottle_count = leftover
		NotificationSystem.warn("Couldn't carry all of them.")
		return

	_check_witness(player)
	searched.emit(added)
	_mark_searched()


# Light, fire-and-forget witness check. Decoupled from CrimeSystem and from
# the cop notice state machine — we only care whether *someone* civilian-or-not
# can currently see the player, and nudge area heat if so.
func _check_witness(player: Node) -> void:
	if player == null or not (player is Node2D):
		return
	for w in WitnessRegistry._witnesses.values():
		if not is_instance_valid(w):
			continue
		if w.can_witness(player):
			HeatSystem.add_heat(_current_area_id(), WITNESSED_HEAT)
			return


func _current_area_id() -> StringName:
	if RoomManager.current_room == null:
		return &""
	return StringName(RoomManager.current_room.scene_file_path.get_file().get_basename())


func _mark_searched() -> void:
	_searched = true
	bottle_count = 0
	_refresh_visual_state()


func _refresh_visual_state() -> void:
	if _is_empty():
		# Dim slightly and suppress the prompt when there's nothing to find.
		modulate = Color(0.7, 0.7, 0.7)
		interactable.prompt_text = ""
		interactable.set_process_mode(Node.PROCESS_MODE_DISABLED)
	else:
		modulate = Color.WHITE
		interactable.prompt_text = "Search"
		interactable.set_process_mode(Node.PROCESS_MODE_INHERIT)


# --- State (for spawner-driven daily reset) -----------------------------

func to_state() -> Dictionary:
	return {
		"can_id": String(can_id),
		"bottle_count": bottle_count,
		"searched": _searched,
		"position_x": global_position.x,
		"position_y": global_position.y,
	}


func from_state(state: Dictionary) -> void:
	can_id = StringName(state.get("can_id", ""))
	bottle_count = state.get("bottle_count", 0)
	_searched = state.get("searched", false)
	global_position = Vector2(state.get("position_x", 0.0), state.get("position_y", 0.0))
	_refresh_visual_state()
