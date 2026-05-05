class_name Placeable
extends Node2D

# The ItemDef this placeable was instantiated from. Set at placement time
# so we know what to return to inventory on pickup, and so persistence
# knows which scene to re-instantiate on room re-entry.
#
# Note this is a PlaceableItemDef but typed as ItemDef for forward-compat
# with anything that might want to reference it generically.
var source_item: PlaceableItemDef


# Called by placement code immediately after the scene is instantiated
# and added to the room. Override in subclasses for additional setup
# (e.g., plant containers spawning their per-slot Interactables).
func on_placed(item: PlaceableItemDef) -> void:
	source_item = item
	


# Whether the placeable currently allows pickup. Override in subclasses
# to gate (e.g., plant container with plants in it returns false).
func can_pickup() -> bool:
	return true


# Reason string for refused pickup, shown to the player.
# Only consulted when can_pickup() returns false.
func pickup_refusal_reason() -> String:
	return "Can't pick this up right now."


# Per-placeable state to be serialized into the room's save dict.
# Subclasses override to add their own fields. The base implementation
# captures position + source item id, which is enough to reconstruct
# any "stateless" placeable.
func save_state() -> Dictionary:
	return {
		"item_id": String(source_item.id) if source_item else "",
		"x": global_position.x,
		"y": global_position.y,
	}


# Apply saved state. Called after on_placed() during room restoration.
# Subclasses override to restore their own fields.
func load_state(data: Dictionary) -> void:
	global_position = Vector2(data.get("x", 0.0), data.get("y", 0.0))
