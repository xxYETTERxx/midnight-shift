class_name CustomerNPC
extends Node2D

# Ephemeral NPC spawned by MeetingSpawner for the duration of a meeting.
# Holds a back-reference to the Meeting so the talk handler can resolve
# customer info, request quantity, and complete the sale.

const RAW_BUD_ID: StringName = &"weed_buds"
const RETAIL_MULTIPLIER: float = 1.5

@onready var sprite: Sprite2D = $Sprite
@onready var interactable: Interactable = $Interactable

var meeting_id: StringName = &""


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)


# Called by the spawner right after instantiation to hook this NPC up to
# its meeting and configure visuals.
func bind_to_meeting(meeting: Meeting) -> void:
	meeting_id = meeting.id
	var customer: Customer = meeting.get_customer()
	if customer == null:
		return
	interactable.prompt_text = "Talk to %s" % customer.display_name
	# TODO: when sprite library lands, look up customer.sprite_id and assign
	# an appropriate texture / spritesheet here. For now we just use whatever
	# texture is set on the scene's Sprite node.


func _on_interacted(_player: Node) -> void:
	var meeting: Meeting = _resolve_meeting()
	if meeting == null:
		return
	var customer: Customer = meeting.get_customer()
	if customer == null:
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
