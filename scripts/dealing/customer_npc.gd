class_name CustomerNPC
extends Node2D

# Ephemeral NPC spawned by MeetingSpawner for the duration of a meeting.
# Walks an authored route to the meet spot at WALK_SPEED, then idles.
# Sale completes through _on_interacted once they've arrived.

const RAW_BUD_ID: StringName = &"weed_buds"
const RETAIL_MULTIPLIER: float = 1.5

# Source of truth for walk speed. MeetingManager reads this when computing
# how early to set spawn_minute, and MeetingSpawner reads it when advancing
# a customer to their mid-route position on a late room entry.
const WALK_SPEED: float = 70.0

const WALK_PREFIX: String = "walk"
const IDLE_PREFIX: String = "idle"

@onready var sprite: CharacterSprite = $Sprite
@onready var interactable: Interactable = $Interactable

var meeting_id: StringName = &""

# Walk state
var _route: Array[Vector2] = []
var _segment_idx: int = 0          # index of the segment currently being walked
var _segment_progress: float = 0.0 # distance walked into _route[_segment_idx]
var _arrived: bool = false
var _facing: String = "s"

var _leaving: bool = false


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)
	_play_anim(IDLE_PREFIX, _facing)


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


func _on_interacted(_player: Node) -> void:
	if _leaving:
		return
	var meeting: Meeting = _resolve_meeting()
	if meeting == null:
		return
	var customer: Customer = meeting.get_customer()
	if customer == null:
		return

	if not _arrived:
		print("[Deal] %s is still on the way." % customer.display_name)
		return

	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var inv: Inventory = player.inventory

	var have: int = _count_item(inv, RAW_BUD_ID)
	if have < meeting.quantity_requested:
		print("[Deal] %s: \"You're short. Come back when you've got %d.\"" %
			[customer.display_name, meeting.quantity_requested])
		return

	# Deduct product, pay out at retail margin.
	_consume_item(inv, RAW_BUD_ID, meeting.quantity_requested)
	var item: ItemDef = ItemRegistry.get_item(RAW_BUD_ID)
	var unit_price: int = 0
	if item != null:
		unit_price = int(round(item.base_value * RETAIL_MULTIPLIER))
	var payout: int = unit_price * meeting.quantity_requested
	Wallet.add(payout)

	print("[Deal] %s paid $%d for %d units" %
		[customer.display_name, payout, meeting.quantity_requested])
	MeetingManager.mark_completed(meeting.id)
	# MeetingSpawner listens for meeting_completed and despawns us.


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
