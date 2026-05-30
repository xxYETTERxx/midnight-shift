class_name Bottle
extends Node2D

# A single discarded bottle lying on the ground. Purely a loose pickup:
# no progress bar, no lock, no crime. Interacting adds `bottle_count` of the
# `bottle` item to the player's inventory and frees this node.
#
# Visual variety comes from a pool of ~50 interchangeable PNGs assigned at
# spawn (the SpawnManager hands us a sprite_index). The variant is cosmetic
# only and is persisted so the bottle looks identical after a mid-day reload.

# All cosmetic variants. The spawner picks an index into this array; if art
# is added/removed, the index is clamped on load so saves never break.
const SPRITE_VARIANTS: Array[Texture2D] = [
	# Fill in as art lands. Example shape:
	preload("res://art/objects/Interactables/bottles/bottle0.png"),
	preload("res://art/objects/Interactables/bottles/bottle1.png"),
	preload("res://art/objects/Interactables/bottles/bottle2.png"),
	preload("res://art/objects/Interactables/bottles/bottle3.png"),
	preload("res://art/objects/Interactables/bottles/bottle4.png"),
	preload("res://art/objects/Interactables/bottles/bottle5.png"),
	preload("res://art/objects/Interactables/bottles/bottle6.png"),
	preload("res://art/objects/Interactables/bottles/bottle7.png"),
	preload("res://art/objects/Interactables/bottles/bottle8.png"),
	preload("res://art/objects/Interactables/bottles/bottle9.png"),
	preload("res://art/objects/Interactables/bottles/bottle10.png"),
	preload("res://art/objects/Interactables/bottles/bottle11.png"),
	preload("res://art/objects/Interactables/bottles/bottle12.png"),
	preload("res://art/objects/Interactables/bottles/bottle13.png"),
	preload("res://art/objects/Interactables/bottles/bottle14.png"),
	preload("res://art/objects/Interactables/bottles/bottle15.png"),
	preload("res://art/objects/Interactables/bottles/bottle16.png"),
	preload("res://art/objects/Interactables/bottles/bottle17.png"),
	preload("res://art/objects/Interactables/bottles/bottle18.png"),
	preload("res://art/objects/Interactables/bottles/bottle19.png"),
]

# The item handed to the player. Resolved from the registry so we don't hard
# preload a .tres path that may move.
const BOTTLE_ITEM_ID: StringName = &"bottle"

# How many bottle units this ground pickup yields. The spawner sets this;
# the inspector default is for hand-placed test bottles.
@export var bottle_count: int = 1

# Stable id used by the spawner / save system. Auto-assigned by the spawner.
@export var bottle_id: StringName = &""

@onready var sprite: Sprite2D = $Sprite
@onready var interactable: Interactable = $Interactable

var _sprite_index: int = 0
var _collected: bool = false

signal collected(bottle_id: StringName)


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)
	interactable.prompt_text = "Pick up"
	_apply_sprite()


# --- Interaction --------------------------------------------------------

func _on_interacted(player: Node) -> void:
	if _collected:
		return
	var inv: Inventory = player.get("inventory") if player else null
	if inv == null:
		return
	var item: ItemDef = ItemRegistry.get_item(BOTTLE_ITEM_ID)
	if item == null:
		push_warning("Bottle: no item registered for id '%s'" % BOTTLE_ITEM_ID)
		return

	var leftover: int = inv.add(item, bottle_count)
	var added: int = bottle_count - leftover
	if added > 0:
		NotificationSystem.loot(item, added)
	if leftover > 0:
		# Couldn't fit all of it — leave the remainder on the ground so the
		# player can come back with space. Reduce our count and stop.
		bottle_count = leftover
		return

	_collected = true
	collected.emit(bottle_id)
	queue_free()


# --- Visuals ------------------------------------------------------------

func set_sprite_index(idx: int) -> void:
	_sprite_index = idx
	if is_inside_tree():
		_apply_sprite()


func _apply_sprite() -> void:
	if SPRITE_VARIANTS.is_empty():
		return
	var idx: int = clampi(_sprite_index, 0, SPRITE_VARIANTS.size() - 1)
	sprite.texture = SPRITE_VARIANTS[idx]


# --- State (for spawner-driven daily reset) -----------------------------

func to_state() -> Dictionary:
	return {
		"bottle_id": String(bottle_id),
		"bottle_count": bottle_count,
		"sprite_index": _sprite_index,
		"position_x": global_position.x,
		"position_y": global_position.y,
	}


func from_state(state: Dictionary) -> void:
	bottle_id = StringName(state.get("bottle_id", ""))
	bottle_count = state.get("bottle_count", 1)
	_sprite_index = state.get("sprite_index", 0)
	global_position = Vector2(state.get("position_x", 0.0), state.get("position_y", 0.0))
	_apply_sprite()
