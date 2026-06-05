extends Node2D

# Throwaway street pedestrian — walks across the dealing-spot scene.
# Becomes interactable when in range of the player. On player interact,
# if willing, halts and runs a progress action that registers a deal
# crime; if witnessed by a cop during the window, the bust check fires.

const PREP_TIME_BASE: float = 2.8   # tier 0 — deliberately slower than the old flat 2.0
const PREP_TIME_MIN: float = 1.7    # tier 5 — slightly faster than old 2.0

const PLAYER_MAX_DISTANCE: float = 64.0
const CRIME_TYPE: StringName = &"weed_deal"

@export var walk_speed: float = 60.0
@export var sprite_frames: SpriteFrames
@onready var _info_label: Label = $InfoLabel

# Ordered world-space points the customer walks through: [entry, ...pivots, exit].
# Set by the minigame before add_child. Walked start-to-end; freed on arrival
# at the final point.
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
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
var _action_duration: float = 2.0
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
	_update_facing_from_next()
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
	if _path_index >= _path.size():
		queue_free()
		return

	var target: Vector2 = _path[_path_index]
	var to_target: Vector2 = target - position
	var step: float = walk_speed * delta

	if to_target.length() <= step:
		position = target
		_path_index += 1
		if _path_index >= _path.size():
			# Reached the final point — walk complete.
			queue_free()
			return
		# Turn toward the next segment (handles corners).
		_update_facing_from_next()
		return

	position += to_target.normalized() * step


# Picks facing + the correct directional walk animation from the vector to the
# current target point. Falls back gracefully: 4-way dir anim -> "walk" -> nothing.
func _update_facing_from_next() -> void:
	if _path_index >= _path.size():
		return
	var to_target: Vector2 = _path[_path_index] - position
	if to_target.length() < 0.01:
		return
	_play_walk_for_dir(to_target)


func _play_walk_for_dir(dir: Vector2) -> void:
	if _sprite.sprite_frames == null:
		return

	# Dominant axis decides the animation. Horizontal ties go east/west.
	var anim: String
	if absf(dir.x) >= absf(dir.y):
		facing_right = dir.x > 0.0
		anim = "walk_e"  # flipped to face west when facing_right is false
		_sprite.flip_h = not facing_right
	else:
		# Vertical-dominant — north (up) or south (down). No horizontal flip.
		_sprite.flip_h = false
		anim = "walk_n" if dir.y < 0.0 else "walk_s"

	_play_anim_with_fallback(anim)


func _play_anim_with_fallback(anim: String) -> void:
	var sf := _sprite.sprite_frames
	if sf.has_animation(anim):
		_sprite.play(anim)
	elif sf.has_animation("walk"):
		_sprite.play("walk")


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
	_action_duration = lerpf(PREP_TIME_BASE, PREP_TIME_MIN, DealerExperience.street_skill_fraction())
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
	_progress_bar.value = _action_elapsed / _action_duration
	if _action_elapsed >= _action_duration:
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
# Called by the minigame before add_child. Spawns the customer at the path's
# first point and queues the rest as the walk route.
func set_path(points: PackedVector2Array) -> void:
	_path = points
	_path_index = 0
	if _path.size() > 0:
		position = _path[0]
		_path_index = 1  # walk toward the second point first


func _play_walk() -> void:
	_update_facing_from_next()


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
		return "%d-%d%%" % [clamp(center - 15, 0, 100), clamp(center + 15, 0, 100)]
	if tier == 4:
		var c: int = int(round(willingness_pct * 100.0))
		return "%d-%d%%" % [clamp(c - 7, 0, 100), clamp(c + 7, 0, 100)]
	# Tier 5+: the mastery payoff — read them outright.
	return "WILL BUY" if is_willing else "WON'T BUY"

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
	
func _exit_tree() -> void:
	# Safety net: if we're freed mid-deal (room change, day rollover, scene
	# teardown) none of the normal ending paths ran. End the crime CANCELLED
	# so it can't linger in CrimeSystem._active and re-dispatch pursuit
	# against every cop that later sees the player.
	if _crime_id != -1:
		CrimeSystem.end_crime(_crime_id, CrimeSystem.Outcome.CANCELLED)
		_crime_id = -1
