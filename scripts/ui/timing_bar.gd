class_name TimingBar
extends Control

# A single-hit timing skill-check. A block ping-pongs across a track; the
# player presses once; the press is graded by how close the block was to the
# target's center. PURE: it grades and reports. It knows nothing about heat,
# weed, locks, or consequences — the caller interprets the grade. Compose
# multiple of these externally for succession (lockpick) or dual-input checks.

enum Quality { MISS, GOOD, PERFECT }

# --- Config (set before start(), or pass into start()) ---
@export var block_speed: float = 1.2
@export var block_width: float = 0.12      # block's span as a fraction of the track — the difficulty knob
@export var target_width: float = 0.04     # thin sliver, fixed-ish
@export var target_position: float = -1.0
@export var perfect_band: float = 0.35     # fraction of the block's HALF-width that counts as PERFECT
@export var input_action: String = "interact"



# --- Nodes ---
@onready var _track: Control = $Track
@onready var _target: ColorRect = $Track/Target
@onready var _block: ColorRect = $Track/Block

# --- Runtime ---
var _active: bool = false
var _pos: float = 0.0        # block position 0..1
var _dir: float = 1.0        # +1 / -1 ping-pong
var _target_center: float = 0.5
var _phase: float = 0.0   # 0..TAU; drives an eased sweep instead of linear

# Fired once when the player presses (or the check is force-resolved).
#   quality: Quality enum
#   accuracy: 0..1, how centered the hit was (1 = dead center) — for callers
#             who want a continuous value instead of bands
signal resolved(quality: int, accuracy: float)


func _ready() -> void:
	visible = false
	set_process(true)
	set_process_unhandled_input(true)


# Begin a check. Optional overrides let a caller drive difficulty per-use
# without editing the node (e.g. heat-scaled speed/width).
func start(p_speed: float = -1.0, p_width: float = -1.0, p_target: float = -2.0) -> void:
	if _active:
		return   # already running — ignore re-trigger
	if p_speed >= 0.0:
		block_speed = p_speed
	if p_width >= 0.0:
		target_width = p_width
	if p_target >= -1.0:
		target_position = p_target

	_target_center = randf() if target_position < 0.0 else clampf(target_position, 0.0, 1.0)
	# Keep the target fully on-track.
	var half: float = target_width * 0.5
	_target_center = clampf(_target_center, half, 1.0 - half)

	_pos = 0.0
	_dir = 1.0
	_active = true
	visible = true
	_layout_target()
	_layout_block()
	set_process(true)
	set_process_unhandled_input(true)


func _process(delta: float) -> void:
	if not _active:
		return
	# Advance a phase; map through a cosine so the block eases at both ends
	# and moves fastest through the middle. block_speed = full sweeps/sec.
	_phase += block_speed * TAU * delta
	if _phase > TAU:
		_phase = fmod(_phase, TAU)
	# cos maps phase→[-1,1]; remap to [0,1]. Starts at 0, eases at both ends.
	_pos = (1.0 - cos(_phase)) * 0.5
	_layout_block()


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event.is_action_pressed(input_action):
		_resolve()
		get_viewport().set_input_as_handled()


func _resolve() -> void:
	if not _active:
		return
	_active = false
	set_process(false)
	set_process_unhandled_input(false)
	visible = false

	var block_half: float = block_width * 0.5
	var target_half: float = target_width * 0.5
	# Distance between block center and target center.
	var dist: float = absf(_pos - _target_center)

	var quality: int
	# Overlap exists if the gap between centers is less than the sum of half-widths.
	var overlap: bool = dist <= (block_half + target_half)
	if not overlap:
		quality = Quality.MISS
	elif dist <= block_half * perfect_band:
		quality = Quality.PERFECT
	else:
		quality = Quality.GOOD

	# accuracy: 1 = block dead-centered on target, 0 = just barely overlapping.
	var max_dist: float = block_half + target_half
	var accuracy: float = clampf(1.0 - (dist / max_dist), 0.0, 1.0) if max_dist > 0.0 else 0.0
	resolved.emit(quality, accuracy)
	


# Lets a caller abort/force-grade (e.g. a timeout, or the customer left).
func force_resolve() -> void:
	if _active:
		_resolve()


# --- Visual layout (positions in the track's local width) ---

func _layout_target() -> void:
	var w: float = _track.size.x
	_target.position.x = (_target_center - target_width * 0.5) * w
	_target.size.x = target_width * w

func _layout_block() -> void:
	var w: float = _track.size.x
	_block.size.x = block_width * w        # visual width = grading width
	_block.position.x = _pos * w - _block.size.x * 0.5
