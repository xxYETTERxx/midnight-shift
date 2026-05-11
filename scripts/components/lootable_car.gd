class_name LootableCar
extends Node2D

# A parked car that the player can break into for loot. Tier determines
# loot table; locked state determines whether a slim jim is required (future)
# and how long the action takes. Looted state persists until daily reset.

const ACTION_DURATION_UNLOCKED: float = 1.0

# Base lockpick duration in seconds, indexed by car tier.
# Lockpicking skill scales this down by up to 60% at L50.
const BASE_DURATION_LOCKED: Array[float] = [4.0, 6.0, 9.0]

# Lock probability per car tier — used by the spawner at car init.
const LOCK_PROBABILITY_BY_TIER: Array[float] = [0.20, 0.60, 0.98]

# CRIM_XP gain per successful loot. Tier scales the reward.
const CRIM_XP_PER_TIER: Array[int] = [3, 6, 12]

# Flat lockpicking XP per successful locked pick.
const LOCKPICK_XP_PER_SUCCESS: int = 3

@export var tier: int = 0
@export var is_locked: bool = true
@export var loot_table: LootTable

# Stable id used by the spawner / save system to track per-car state
# across the day. Auto-assigned by the spawner; set manually for hand-placed
# test cars.
@export var car_id: StringName = &""

@onready var sprite: Sprite2D = $Sprite
@onready var interactable: Interactable = $Interactable
@onready var progress_bar: ProgressBar = $ProgressBar

var is_looted: bool = false

# Active interaction state — non-null while the player is holding to loot.
var _action_player: Node = null
var _action_elapsed: float = 0.0
var _action_duration: float = 0.0

signal looted(drops: Array)


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
	# Cancel if player walks too far away.
	if _action_player.global_position.distance_to(global_position) > 64.0:
		_cancel_action()
		return
	_action_elapsed += delta
	progress_bar.value = _action_elapsed / _action_duration
	if _action_elapsed >= _action_duration:
		_complete_action()


# --- Interaction ---

func _on_interacted(player: Node) -> void:
	if is_looted:
		return
	if _action_player != null:
		return  # already in progress
	
	if is_locked:
		var inv: Inventory = player.get("inventory")
		if inv == null or not inv.has_item(&"slim_jim"):
			NotificationSystem.warn("You need a slim jim to pry this open.")
			return
		var base: float = BASE_DURATION_LOCKED[clampi(tier, 0, BASE_DURATION_LOCKED.size() - 1)]
		_action_duration = base * PlayerSkills.lockpick_duration_multiplier()
	else:
		_action_duration = ACTION_DURATION_UNLOCKED
	
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
	
	if player == null or loot_table == null:
		_mark_looted()
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = Time.get_ticks_usec() + hash(car_id)
	var drops: Array = loot_table.roll(rng)

	var inv: Inventory = player.get("inventory")
	for drop in drops:
		var item: ItemDef = drop["item"]
		var count: int = drop["count"]
		if inv != null and item != null:
			var leftover: int = inv.add(item, count)
			var added: int = count - leftover
			if added > 0:
				NotificationSystem.loot(item, added)
			if leftover > 0:
				NotificationSystem.warn("Couldn't fit %d %s" % [leftover, item.display_name])

	# Award criminal XP for the act, regardless of loot quality.
	if tier >= 0 and tier < CRIM_XP_PER_TIER.size():
		CriminalExperience.adjust(CRIM_XP_PER_TIER[tier])
	if is_locked:
		PlayerSkills.adjust(&"lockpicking", LOCKPICK_XP_PER_SUCCESS)

	looted.emit(drops)
	_mark_looted()


func _mark_looted() -> void:
	is_looted = true
	_refresh_visual_state()


func _refresh_visual_state() -> void:
	if is_looted:
		# TODO: swap to "looted" sprite variant (door ajar). For MVP, just dim.
		modulate = Color(0.6, 0.6, 0.6)
		interactable.prompt_text = ""
		interactable.set_process_mode(Node.PROCESS_MODE_DISABLED)
	else:
		modulate = Color.WHITE
		interactable.prompt_text = "Slim Jim" if is_locked else "Search"
		interactable.set_process_mode(Node.PROCESS_MODE_INHERIT)


# --- State (for spawner-driven daily reset) ---

func to_state() -> Dictionary:
	return {
		"car_id": String(car_id),
		"tier": tier,
		"is_locked": is_locked,
		"is_looted": is_looted,
		"position_x": global_position.x,
		"position_y": global_position.y,
	}


func from_state(state: Dictionary) -> void:
	car_id = StringName(state.get("car_id", ""))
	tier = state.get("tier", 0)
	is_locked = state.get("is_locked", true)
	is_looted = state.get("is_looted", false)
	global_position = Vector2(state.get("position_x", 0.0), state.get("position_y", 0.0))
	_refresh_visual_state()

static func roll_locked_for_tier(car_tier: int, rng: RandomNumberGenerator) -> bool:
	var t: int = clampi(car_tier, 0, LOCK_PROBABILITY_BY_TIER.size() - 1)
	return rng.randf() < LOCK_PROBABILITY_BY_TIER[t]
