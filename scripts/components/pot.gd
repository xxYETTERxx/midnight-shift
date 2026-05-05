class_name Pot
extends Placeable


const ITEM_WATERING_CAN: StringName = &"watering_can"

const ITEM_BUDS: StringName = &"weed_buds"
const HARVEST_YIELD: int = 30

enum ContainerState {
	EMPTY,
	SOILED,
}

enum PlantStage {
	NONE,
	SEEDED,
	SPROUT,
	EARLY,
	MEDIUM,
	FULL,
	FLOWERING,
}

const WATERABLE_STAGES: Array = [
	PlantStage.SEEDED, PlantStage.SPROUT, PlantStage.EARLY,
	PlantStage.MEDIUM, PlantStage.FULL, PlantStage.FLOWERING,
]


# Container textures — owned by the pot (these are container art).
@export var empty_texture: Texture2D
@export var soiled_texture: Texture2D

# Plant stage textures — temporarily owned by the pot, will move to a
# Strain resource when multiple strains exist. Indexed by PlantStage,
# with NONE being null.
@export var plant_stage_textures: Array[Texture2D] = []

@onready var container_sprite: Sprite2D = $ContainerSprite  # the pot
@onready var plant_sprite: Sprite2D = $PlantSprite  
@onready var watered_mark: Sprite2D = $WateredMark

# How many plant cycles a fresh fill of soil supports.
@export var soil_uses_per_fill: int = 3

# Item ids the pot consumes to advance between states.
# Kept here as constants for clarity; could move to a config resource later.
const ITEM_SOIL: StringName = &"soil_bag"
const ITEM_SEED: StringName = &"weed_seed"  # ItemDef coming in this sub-chunk


@onready var interactable: Interactable = $Interactable

var container_state: ContainerState = ContainerState.EMPTY
var plant_stage: PlantStage = PlantStage.NONE
var soil_uses_remaining: int = 0
var watered_today: bool = false

var modifiers: Array = []


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)
	TimeSystem.day_rolled.connect(_on_day_rolled)
	_refresh_visual()

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("interact"):
		var player := get_tree().get_first_node_in_group("player")

# Override Placeable.can_pickup so pots with anything in them can't be
# picked up. Empty pot returns to inventory cleanly.
func can_pickup() -> bool:
	return container_state == ContainerState.EMPTY and plant_stage == PlantStage.NONE


func pickup_refusal_reason() -> String:
	if plant_stage != PlantStage.NONE:
		return "Empty the pot first."
	if container_state == ContainerState.SOILED:
		return "Empty the soil first."
	return "Can't pick this up right now."


# --- Interactable hookup ---

func would_accept(player: Node) -> bool:
	if player == null:
		return false

	# Empty container + soil → soil it
	if container_state == ContainerState.EMPTY and player.is_holding(ITEM_SOIL):
		return true

	# Bare soil + seed → plant it
	if is_bare_soil() and player.is_holding(ITEM_SEED):
		return true

	# Watering
	if plant_stage in WATERABLE_STAGES and not watered_today and player.is_holding(ITEM_WATERING_CAN):
		return true
	
	#harvest
	if plant_stage == PlantStage.FLOWERING and not player.is_holding_anything():
		return true
	
	return false


func is_bare_soil() -> bool:
	return container_state == ContainerState.SOILED and plant_stage == PlantStage.NONE

func _on_interacted(player: Node) -> void:
	if container_state == ContainerState.EMPTY and player.is_holding(ITEM_SOIL):
		_apply_soil(player)
	elif is_bare_soil() and player.is_holding(ITEM_SEED):
		_apply_seed(player)
	elif plant_stage in WATERABLE_STAGES and not watered_today and player.is_holding(ITEM_WATERING_CAN):
		_apply_water()
	elif plant_stage == PlantStage.FLOWERING and not player.is_holding_anything():
		_apply_harvest(player)
	
#--- Plant Growth --------------------------------
	
func _on_day_rolled(_dow: int, _dom: int) -> void:
	# Only plants in soil tick.
	if plant_stage == PlantStage.NONE:
		return

	if watered_today:
		_advance_growth()
	else:
		_record_water_missed()

	# New day, fresh start.
	watered_today = false
	_refresh_visual()
	interactable.state_changed.emit()

func _advance_growth() -> void:
	# Cap at FLOWERING; harvest action returns to soiled/empty in next sub-chunk.
	if plant_stage == PlantStage.FLOWERING:
		return
	plant_stage = (plant_stage + 1) as PlantStage


func _record_water_missed() -> void:
	# Quality system foundations — see design doc §21.
	# Dropped onto the plant's modifier list for harvest-time evaluation.
	modifiers.append({
		"kind": "water_missed",
		"day": TimeSystem.day_index(),
	})

# --- State transitions ---

func _apply_soil(player: Node) -> void:
	container_state = ContainerState.SOILED
	soil_uses_remaining = soil_uses_per_fill
	player.inventory.consume_active(1)
	_refresh_visual()
	interactable.state_changed.emit()


func _apply_seed(player: Node) -> void:
	plant_stage = PlantStage.SEEDED
	modifiers = []  # fresh plant, fresh quality history
	watered_today = false
	player.inventory.consume_active(1)
	_refresh_visual()
	interactable.state_changed.emit()
	
func _apply_water() -> void:
	watered_today = true
	_refresh_visual()
	interactable.state_changed.emit()

func _apply_harvest(player: Node) -> void:
	# Add buds to inventory; drop on ground if it overflows.
	# (For MVP we'll just push warnings on overflow — proper drop logic
	# is a later concern.)
	var buds := ItemRegistry.get_item(ITEM_BUDS)
	if buds == null:
		push_error("Pot: weed_buds not in registry")
		return
	var leftover: int = player.inventory.add(buds, HARVEST_YIELD)
	if leftover > 0:
		push_warning("Pot: harvest overflow, %d buds lost" % leftover)

	# Decrement soil uses; reset to soiled or empty depending on remaining uses.
	soil_uses_remaining -= 1
	plant_stage = PlantStage.NONE
	watered_today = false
	modifiers = []  # plant gone, modifier history cleared

	if soil_uses_remaining <= 0:
		container_state = ContainerState.EMPTY

	_refresh_visual()
	interactable.state_changed.emit()

# --- Visuals ---

func _refresh_visual() -> void:
	# Container art
	match container_state:
		ContainerState.EMPTY:
			container_sprite.texture = empty_texture
		ContainerState.SOILED:
			container_sprite.texture = soiled_texture

	# Plant overlay
	if plant_stage == PlantStage.NONE:
		plant_sprite.visible = false
	else:
		plant_sprite.visible = true
		var idx: int = plant_stage - 1
		if idx < plant_stage_textures.size():
			plant_sprite.texture = plant_stage_textures[idx]
	
	# Watered indicator — only meaningful when there's a plant
	watered_mark.visible = watered_today and plant_stage != PlantStage.NONE


# --- Save state hooks (extends Placeable's base save) ---

func save_state() -> Dictionary:
	var data := super.save_state()
	data["container_state"] = container_state
	data["plant_stage"] = plant_stage
	data["soil_uses_remaining"] = soil_uses_remaining
	data["watered_today"] = watered_today
	data["modifiers"] = modifiers.duplicate()  # don't share array references
	return data

func load_state(data: Dictionary) -> void:
	super.load_state(data)
	container_state = data.get("container_state", ContainerState.EMPTY)
	plant_stage = data.get("plant_stage", PlantStage.NONE)
	soil_uses_remaining = data.get("soil_uses_remaining", 0)
	watered_today = data.get("watered_today", false)
	modifiers = data.get("modifiers", [])
	_refresh_visual()

# Advances a pot's snapshot dictionary by one day. Used to tick pots
# in rooms the player isn't currently in. Mirrors the logic in
# _on_day_rolled, but operates on serialized data.
static func tick_snapshot_day(state: Dictionary) -> void:
	var plant_stage: int = state.get("plant_stage", PlantStage.NONE)
	var watered: bool = state.get("watered_today", false)

	if plant_stage != PlantStage.NONE:
		if watered and plant_stage < PlantStage.FLOWERING:
			state["plant_stage"] = plant_stage + 1
		state["watered_today"] = false
