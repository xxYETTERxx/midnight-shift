@tool
class_name NPC
extends Node2D

# Attach to the root of an NPC scene (e.g., your TestMale scene).
# The scene should have an Interactable child with auto_trigger = false.
# This script connects the Interactable's `interacted` signal to fire dialogue.

# Identifies which .dlg file's lines this NPC speaks.
# Convention: must match the .dlg filename (mira.dlg → "mira").
# If left blank, falls back to the node name lowercased.
@export var npc_id: String = ""

# Display name for the dialogue box (e.g., "Mira"). Falls back to node name.
@export var display_name: String = ""

# Prompt shown when player is in range. Leave default unless this NPC has
# a non-standard interaction (e.g., "Greet", "Argue with").
@export var prompt_text: String = "Talk"

@onready var _interactable: Interactable = $Interactable

@export var sprite_frames: SpriteFrames:
	set(value):
		sprite_frames = value
		if is_inside_tree() and has_node("AnimatedSprite2D"):
			$AnimatedSprite2D.sprite_frames = value




func _ready() -> void:
	if npc_id == "":
		npc_id = name.to_lower()
	if display_name == "":
		display_name = name

	if _interactable == null:
		push_error("NPC '%s' has no Interactable child" % name)
		return
	
	if has_node("AnimatedSprite2D"):
			var sprite: AnimatedSprite2D = $AnimatedSprite2D
			if sprite_frames != null:
				sprite.sprite_frames = sprite_frames
			if sprite.sprite_frames and sprite.sprite_frames.has_animation("idle"):
				sprite.play("idle")
	
	_interactable.prompt_text = prompt_text
	_interactable.interact_priority = 40  # NPC tier per design doc
	_interactable.interacted.connect(_on_interacted)
	_interactable.alt_interacted.connect(_on_alt_interacted)


func _on_interacted(_player: Node) -> void:
	if not DialogueRuntime.trigger(npc_id, display_name):
		push_warning("NPC '%s': no dialogue match" % npc_id)





func _current_location_id() -> String:
	# Uses the current room's scene basename as the location tag
	# (e.g., "apartment_living"). If you want a coarser "apartment" tag
	# that matches both rooms in the apartment, we'll add a location_id
	# export on the room script later.
	if RoomManager.current_room == null:
		return ""
	return RoomManager.current_room.scene_file_path.get_file().get_basename()

func _on_alt_interacted(_player: Node) -> void:
	print("[alt] NPC._on_alt_interacted fired for ", npc_id)
	if not RelationshipSystem.can_receive_gift(npc_id):
		NotificationSystem.warn("They already got something from you today.")
		return
	var panel := get_tree().get_first_node_in_group("gift_panel")
	print("[alt] gift_panel lookup=", panel)
	if panel == null:
		push_warning("NPC '%s': no GiftPanel in scene tree" % npc_id)
		return
	panel.open(npc_id, display_name)
