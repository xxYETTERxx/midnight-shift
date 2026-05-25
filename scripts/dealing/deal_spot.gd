extends Node2D

# Outdoor-scene interactable that starts a 2-bit dealing minigame session.
# Wraps an Interactable child. On interact: deducts player's raw bud,
# starts the session through StreetDealSession.

const WEED_BUDS_ID: StringName = &"weed_buds"

# Identifies which area this spot belongs to. Used for heat application
# during the session. Set in the inspector.
@export var area_id: StringName = &""

# Unique id for this dealing spot. Used by SpotHeatTracker to count
# deals per spot. Distinct from area_id (which scopes heat).
@export var spot_id: StringName = &""

# Display in the interact prompt.
@export var prompt_text: String = "Post up"

@onready var _interactable: Interactable = $Interactable

# Foot traffic — average game-minutes between NPC spawns at this spot.
@export var spawn_interval_minutes: float = 30.0

# Archetype mix at this spot — parallel arrays of archetype resources and
# their relative spawn weights. Weights are normalized internally.
# Example for an alley: pothead=70, normal=25, business_man=5.
@export var archetypes: Array[CustomerArchetype] = []
@export var archetype_weights: Array[int] = []

# Game-minutes between cop spawn checks at this spot.
@export var cop_check_interval_minutes: float = 30.0


func _ready() -> void:
	_interactable.prompt_text = prompt_text
	_interactable.interact_priority = 50
	_interactable.interacted.connect(_on_interacted)


func _on_interacted(player: Node) -> void:
	if StreetDealSession.active:
		return  # defensive — shouldn't happen, but no double-entry

	var bud_count: int = _count_item(player.inventory, WEED_BUDS_ID)
	if bud_count <= 0:
		NotificationSystem.warn("No product on you.")
		return

	# Deduct ALL bud into the session bank. Leftover deposits back on exit.
	_consume_all(player.inventory, WEED_BUDS_ID)

	var return_room: String = RoomManager.current_room.scene_file_path
	print("[DealSpot] passing archetypes=%s weights=%s" % [archetypes, archetype_weights])
	StreetDealSession.begin_session(
	bud_count, spot_id, area_id, return_room, global_position,
	spawn_interval_minutes, archetypes, archetype_weights, cop_check_interval_minutes
)


# --- Inventory helpers (Inventory doesn't expose count/consume_all) ---

func _count_item(inv: Inventory, item_id: StringName) -> int:
	var total := 0
	for i in range(inv.max_slots):
		var stack := inv.get_slot(i)
		if stack != null and stack.item != null and stack.item.id == item_id:
			total += stack.count
	return total


func _consume_all(inv: Inventory, item_id: StringName) -> void:
	for i in range(inv.max_slots):
		var stack := inv.get_slot(i)
		if stack != null and stack.item != null and stack.item.id == item_id:
			inv.consume_from_slot(i, stack.count)
