class_name CustomerNPC
extends Node2D

# Ephemeral NPC spawned by MeetingSpawner for the duration of a meeting.
# Walks an authored route to the meet spot at WALK_SPEED, then idles.
# Sale completes through _on_interacted once they've arrived.

const RETAIL_MULTIPLIER: float = 1.0

# Source of truth for walk speed. MeetingManager reads this when computing
# how early to set spawn_minute, and MeetingSpawner reads it when advancing
# a customer to their mid-route position on a late room entry.
const WALK_SPEED: float = 70.0

const WALK_PREFIX: String = "walk"
const IDLE_PREFIX: String = "idle"

const CRIME_TYPE: StringName = &"weed_deal"
const PLAYER_MAX_DISTANCE: float = 64.0

const PREP_TIME_BASE: float = 2.8
const PREP_TIME_MIN: float = 1.7

@onready var sprite: CharacterSprite = $Sprite
@onready var interactable: Interactable = $Interactable
@onready var _progress_bar: ProgressBar = $ProgressBar

var meeting_id: StringName = &""
var RAW_BUD_ID: StringName = &"weed_buds"

# Walk state
var _route: Array[Vector2] = []
var _segment_idx: int = 0          # index of the segment currently being walked
var _segment_progress: float = 0.0 # distance walked into _route[_segment_idx]
var _arrived: bool = false
var _facing: String = "s"
var _action_player: Node = null
var _action_duration: float = 2.0
var _action_elapsed: float = 0.0
var _crime_id: int = -1
var _dealing: bool = false


var _leaving: bool = false


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)
	_play_anim(IDLE_PREFIX, _facing)
	_progress_bar.visible = false
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0
	var player := get_tree().get_first_node_in_group("player")


# Called by the spawner right after instantiation to hook this NPC up to
# its meeting and configure visuals.
func bind_to_meeting(meeting: Meeting) -> void:
	meeting_id = meeting.id
	var customer: Customer = meeting.get_customer()
	if customer == null:
		return
	sprite.apply_appearance(&"customer", customer.head_index, customer.body_index)
	interactable.prompt_text = "Talk to %s" % customer.display_name


# Begin (or resume) the walk along the provided point chain. points[0] is
# the spawn position; points[-1] is the destination. Empty or single-point
# inputs mark the customer as arrived immediately.
func walk_route(points: Array[Vector2]) -> void:
	_route = points
	_segment_idx = 0
	_segment_progress = 0.0
	_arrived = false
	if _route.is_empty():
		_on_arrived()
		return
	global_position = _route[0]
	if _route.size() == 1:
		_on_arrived()
		return
	_update_facing_for_segment(0)
	_play_anim(WALK_PREFIX, _facing)


func _process(delta: float) -> void:
	if _action_player != null:
		_tick_action(delta)
		return
	if _arrived or _route.size() < 2:
		return
	var step: float = WALK_SPEED * delta
	while step > 0.0 and _segment_idx < _route.size() - 1:
		var seg_start: Vector2 = _route[_segment_idx]
		var seg_end: Vector2 = _route[_segment_idx + 1]
		var seg_len: float = seg_start.distance_to(seg_end)
		if seg_len <= 0.0:
			# Degenerate segment — skip it.
			_segment_idx += 1
			_segment_progress = 0.0
			continue
		var remaining_in_seg: float = seg_len - _segment_progress
		if step < remaining_in_seg:
			_segment_progress += step
			global_position = seg_start.lerp(seg_end, _segment_progress / seg_len)
			return
		# Crossed a waypoint. Advance and continue consuming step.
		step -= remaining_in_seg
		_segment_idx += 1
		_segment_progress = 0.0
		if _segment_idx >= _route.size() - 1:
			global_position = _route[-1]
			_on_arrived()
			return
		_update_facing_for_segment(_segment_idx)
		_play_anim(WALK_PREFIX, _facing)


func _on_arrived() -> void:
	_arrived = true
	if _route.size() >= 2:
		_update_facing_for_segment(_route.size() - 2)
	_play_anim(IDLE_PREFIX, _facing)
	if _leaving:
		queue_free()


func _update_facing_for_segment(idx: int) -> void:
	if idx < 0 or idx >= _route.size() - 1:
		return
	var d: Vector2 = _route[idx + 1] - _route[idx]
	if abs(d.x) > abs(d.y):
		_facing = "e" if d.x > 0.0 else "w"
	else:
		_facing = "s" if d.y > 0.0 else "n"


# Mirrors ScheduledNPC's animation fallback chain — most-specific first,
# then degrade so a partial SpriteFrames set still renders something.
func _play_anim(prefix: String, facing: String) -> void:
	sprite.play_anim(prefix, facing)


func _on_interacted(player_node: Node) -> void:
	if _leaving or _dealing:
		return
	var meeting: Meeting = _resolve_meeting()
	if meeting == null:
		return
	var customer: Customer = meeting.get_customer()
	if customer == null:
		return

	if not _arrived:
		return

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var inv: Inventory = player.inventory

	if inv.has_item(&"dime_bag_full"):
		RAW_BUD_ID = &"dime_bag_full"
	var have: int = _count_item(inv, RAW_BUD_ID)
	if have < meeting.quantity_requested:
		NotificationSystem.info("You're short. Come back when you've got")
		return

	# Validation passed — open the timed deal window. The sale itself happens
	# in _complete_action; until then nothing is deducted or paid.
	_action_player = player
	_action_elapsed = 0.0
	_action_duration = lerpf(PREP_TIME_BASE, PREP_TIME_MIN, DealerExperience.street_skill_fraction())
	_dealing = true
	_progress_bar.visible = true
	_progress_bar.value = 0.0
	var area_id: StringName = _current_area_id()
	_crime_id = CrimeSystem.begin_crime(CRIME_TYPE, self, global_position, area_id)



func _resolve_meeting() -> Meeting:
	if meeting_id == &"":
		return null
	return MeetingManager.get_meeting(meeting_id)
	
func walk_away() -> void:
	if _leaving:
		return
	_leaving = true
	if not _arrived or _route.size() < 2:
		queue_free()
		return
	var reverse: Array[Vector2] = []
	for i in range(_route.size() - 1, -1, -1):
		reverse.append(_route[i])
	_route = reverse
	_segment_idx = 0
	_segment_progress = 0.0
	_arrived = false
	global_position = _route[0]
	_update_facing_for_segment(0)
	_play_anim(WALK_PREFIX, _facing)


func _count_item(inv: Inventory, id: StringName) -> int:
	var total: int = 0
	for i in range(inv.max_slots):
		var stack: ItemStack = inv.get_slot(i)
		if stack != null and stack.item != null and stack.item.id == id:
			total += stack.count
	return total

func _tick_action(delta: float) -> void:
	if not is_instance_valid(_action_player):
		_cancel_action()
		return
	if _action_player.global_position.distance_to(global_position) > PLAYER_MAX_DISTANCE:
		_cancel_action()
		return
	_action_elapsed += delta
	_progress_bar.value = _action_elapsed / _action_duration
	if _action_elapsed >= _action_duration:
		_complete_action()

func _complete_action() -> void:
	if _crime_id != -1:
		CrimeSystem.end_crime(_crime_id, CrimeSystem.Outcome.COMPLETED)
		_crime_id = -1
	_action_player = null
	_dealing = false
	_progress_bar.visible = false

	var meeting: Meeting = _resolve_meeting()
	if meeting == null:
		return
	var customer: Customer = meeting.get_customer()
	var player := get_tree().get_first_node_in_group("player")
	_crime_id = -1
	if player == null or customer == null:
		return
	var inv: Inventory = player.inventory

	# Re-check inventory at completion — the player could have dropped product
	# mid-action. Cheap guard against a free payout.
	if _count_item(inv, RAW_BUD_ID) < meeting.quantity_requested:
		print("[Deal] %s: deal fell through, short on product." % customer.display_name)
		return

	_consume_item(inv, RAW_BUD_ID, meeting.quantity_requested)
	var item: ItemDef = ItemRegistry.get_item(RAW_BUD_ID)
	var unit_price: int = 0
	if item != null:
		unit_price = int(round(item.base_value * RETAIL_MULTIPLIER))
	var payout: int = unit_price * meeting.quantity_requested
	Wallet.add(payout)
	DealerExperience.adjust(meeting.quantity_requested)
	CriminalExperience.adjust(1)

	print("[Deal] %s paid $%d for %d units" %
		[customer.display_name, payout, meeting.quantity_requested])
	MeetingManager.mark_completed(meeting.id)

func _consume_item(inv: Inventory, id: StringName, count: int) -> void:
	var remaining: int = count
	for i in range(inv.max_slots):
		if remaining <= 0:
			break
		var stack: ItemStack = inv.get_slot(i)
		if stack == null or stack.item == null or stack.item.id != id:
			continue
		var to_take: int = min(stack.count, remaining)
		inv.consume_from_slot(i, to_take)
		remaining -= to_take

func _cancel_action() -> void:
	if _crime_id != -1:
		CrimeSystem.end_crime(_crime_id, CrimeSystem.Outcome.CANCELLED)
		_crime_id = -1
	_action_player = null
	_action_elapsed = 0.0
	_dealing = false
	_progress_bar.visible = false
	
func is_dealing() -> bool:
	return _dealing


func bust_cancel() -> void:
	if _crime_id != -1:
		CrimeSystem.end_crime(_crime_id, CrimeSystem.Outcome.CANCELLED)
		_crime_id = -1
	_action_player = null
	_dealing = false
	_progress_bar.visible = false
	
func _current_area_id() -> StringName:
	if RoomManager.current_room == null:
		return &""
	return StringName(RoomManager.current_room.scene_file_path.get_file().get_basename())
	
func _exit_tree() -> void:
	if _crime_id != -1:
		CrimeSystem.end_crime(_crime_id, CrimeSystem.Outcome.CANCELLED)
		_crime_id = -1
