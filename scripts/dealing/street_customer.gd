extends Node2D

# Throwaway street pedestrian — walks across the dealing-spot scene.
# Becomes interactable when in range of the player. On player interact,
# if willing, halts and runs a progress action that registers a deal
# crime; if witnessed by a cop during the window, the bust check fires.

const ACTION_DURATION: float = 2.0
const PLAYER_MAX_DISTANCE: float = 64.0
const CRIME_TYPE: StringName = &"weed_deal"

@export var walk_speed: float = 60.0
@export var sprite_frames: SpriteFrames
@onready var _info_label: Label = $InfoLabel

var target_position: Vector2 = Vector2.ZERO
var facing_right: bool = true
var is_willing: bool = false

# The probability rolled at spawn time from the archetype's range.
# is_willing was derived from this; kept around so tier-gated UI can
# surface it to the player.
var willingness_pct: float = 0.0

# Lifecycle flags. Once "committed" the customer no longer walks; they're
# locked in until completion or bust.
var _committed: bool = false
var _resolved: bool = false
var _arrived: bool = false

# Action progress (only used in the willing branch).
var _action_player: Node = null
var _action_elapsed: float = 0.0
var _crime_id: int = -1

var archetype: CustomerArchetype = null

# Crime area is read from the active session.
var _area_id: StringName = &""

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _interactable: Interactable = $Interactable
@onready var _progress_bar: ProgressBar = $ProgressBar

signal offer_resolved(willing: bool, completed: bool, customer: Node)


func _ready() -> void:
	if sprite_frames != null:
		_sprite.sprite_frames = sprite_frames
	_sprite.flip_h = not facing_right
	_play_walk()
	_info_label.text = _build_info_text()
	_interactable.interact_priority = 40
	_interactable.interacted.connect(_on_interacted)

	_progress_bar.visible = false
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0

	_area_id = StreetDealSession.area_id


func _process(delta: float) -> void:
	if _action_player != null:
		_tick_action(delta)
		return
	if _committed:
		return  # refusing customer stands still briefly before walking off
	if _arrived:
		return
	_tick_walk(delta)


# --- Walking ---

func _tick_walk(delta: float) -> void:
	var to_target: Vector2 = target_position - position
	var step: float = walk_speed * delta
	if to_target.length() <= step:
		position = target_position
		_arrived = true
		queue_free()
		return
	position += to_target.normalized() * step


# --- Interaction ---

func _on_interacted(player: Node) -> void:
	if _committed:
		return
	_committed = true
	# Disable further interaction immediately so a held-E doesn't re-fire.
	_interactable.monitoring = false
	_play_idle()
	_info_label.visible = false

	if not is_willing:
		# Refusal resolves immediately; minigame handles heat + walks off.
		_resolved = true
		offer_resolved.emit(false, false, self)
		# Resume walking off after a brief moment so the player gets feedback.
		_committed = false
		_play_walk()
		return

	# Willing — kick off the action window.
	_action_player = player
	_action_elapsed = 0.0
	_progress_bar.visible = true
	_progress_bar.value = 0.0
	_crime_id = CrimeSystem.begin_crime(CRIME_TYPE, self, global_position, _area_id)


# --- Action progress ---

func _tick_action(delta: float) -> void:
	if _action_player == null:
		return
	if not is_instance_valid(_action_player):
		_cancel_action()
		return
	if _action_player.global_position.distance_to(global_position) > PLAYER_MAX_DISTANCE:
		_cancel_action()
		return
	_action_elapsed += delta
	_progress_bar.value = _action_elapsed / ACTION_DURATION
	if _action_elapsed >= ACTION_DURATION:
		_complete_action()


func _cancel_action() -> void:
	if _crime_id != -1:
		CrimeSystem.end_crime(_crime_id, CrimeSystem.Outcome.CANCELLED)
		_crime_id = -1
	_action_player = null
	_action_elapsed = 0.0
	_progress_bar.visible = false
	# Customer wanders off without resolving — no sale, no heat from refusal.
	_resolved = true
	_committed = false
	_play_walk()


func _complete_action() -> void:
	if _crime_id != -1:
		CrimeSystem.end_crime(_crime_id, CrimeSystem.Outcome.COMPLETED)
		_crime_id = -1
	_action_player = null
	_progress_bar.visible = false
	_resolved = true
	offer_resolved.emit(true, true, self)
	# Sale done — customer walks off the opposite way.
	_committed = false
	_play_walk()


# --- Helpers ---

func _play_walk() -> void:
	if _sprite.sprite_frames == null:
		return
	if _sprite.sprite_frames.has_animation("walk_e"):
		_sprite.play("walk_e")
	elif _sprite.sprite_frames.has_animation("walk"):
		_sprite.play("walk")


func _play_idle() -> void:
	_sprite.pause()

# Builds the always-visible overhead label. Reveal scales with DealerExperience tier:
#   Tier 0: hidden
#   Tier 1: "<archetype>"
#   Tier 2: "<archetype> ~<min>-<max>%"
#   Tier 3: "<archetype> ~<rolled ±15>%"
#   Tier 4: "<archetype> <rolled>%"
func _build_info_text() -> String:
	var tier: int = DealerExperience.current_tier()
	if tier <= 0 or archetype == null:
		return ""

	
	if tier == 1:
		var mid: float = (archetype.purchase_chance_min + archetype.purchase_chance_max) * 0.5
		if mid >= 0.65: return "Likely"
		elif mid >= 0.35: return "Maybe"
		else: return "Unlikely"

	if tier == 2:
		var lo_pct: int = int(round(archetype.purchase_chance_min * 100.0))
		var hi_pct: int = int(round(archetype.purchase_chance_max * 100.0))
		return "~%d-%d%%" % [lo_pct, hi_pct]

	if tier == 3:
		var center: int = int(round(willingness_pct * 100.0))
		var lo: int = clamp(center - 15, 0, 100)
		var hi: int = clamp(center + 15, 0, 100)
		return "%d-%d%%" % [lo, hi]

	var pct: int = int(round(willingness_pct * 100.0))
	return "%d%%" % [pct]

# Called externally by the minigame on bust — ends the crime cleanly and
# clears action state without firing offer_resolved (bust is its own flow).
func bust_cancel() -> void:
	if _crime_id != -1:
		CrimeSystem.end_crime(_crime_id, CrimeSystem.Outcome.CANCELLED)
		_crime_id = -1
	_action_player = null
	_progress_bar.visible = false
	_resolved = true
	
# Used by the minigame HUD (and future tier-gated reveals) to show
# archetype info on hover or by-default.
func get_archetype_display_name() -> String:
	if archetype == null:
		return ""
	return archetype.display_name

func is_dealing() -> bool:
	return _action_player != null


# Player aborted the deal deliberately (e.g. spotted a cop). Same clean
# effect as walking out of range — ends the crime CANCELLED, no heat, the
# customer wanders off. Distinct from bust_cancel(), which is the cop path.
func player_cancel() -> void:
	if _action_player == null:
		return
	_cancel_action()
