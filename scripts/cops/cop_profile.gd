class_name CopProfile
extends Resource

# Per-archetype cop tuning. Authored as .tres files (e.g., cop_fit.tres,
# cop_average.tres, reggie.tres). Same declarative pattern as ItemDef —
# all per-cop variation lives here, not in code.

# --- Identity ----------------------------------------------------------
@export var profile_id: StringName = &""
@export var display_name: String = ""

# --- Movement ----------------------------------------------------------
@export var patrol_speed: float = 80.0
@export var pursuit_speed: float = 95.0

# --- Perception --------------------------------------------------------
# Cone width for initial detection. Cop must have the player in viewport
# AND within this angle of their facing direction to register a witness.
@export var fov_degrees: float = 110.0

# Seconds of continuous in-cone visibility before PATROL flips to PURSUIT.
# Lets you brush past a slow cop without instant detection.
@export var notice_delay: float = 0.5

# --- Pursuit -----------------------------------------------------------
# Once chasing, this many seconds of "lost sight" before dropping to
# INVESTIGATE. Higher = more tenacious.
@export var pursuit_los_grace: float = 3.0

# Pursuit-only. How far past the viewport edge the cop keeps "seeing" the
# player before LOS officially breaks. Reserved for tuning the chase tail
# once the basic loop is running.
@export var pursuit_tracking_buffer: float = 80.0

# Seconds spent at last-known-position before giving up and returning
# to routine (schedule).
@export var investigate_duration: float = 8.0

# --- Vault capability (cop pursuit vault interaction, see DD §8) -------
@export var can_vault_low: bool = true
@export var can_vault_medium: bool = false
@export var can_vault_high: bool = false

# --- Crime weighting ---------------------------------------------------
# How seriously this cop reacts to specific crime types. 0.0 = ignores
# entirely, 1.0 = full reaction. Missing keys default to 1.0.
@export var notice_weight: Dictionary = {}

# --- Visual ------------------------------------------------------------
@export var sprite_frames: SpriteFrames


func reaction_weight(crime_type: StringName) -> float:
	return float(notice_weight.get(crime_type, 1.0))
