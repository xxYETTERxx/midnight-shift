@tool
class_name WitnessComponent
extends Node2D

# Drop this as a child of any NPC scene to make them a witness. Cops,
# pedestrians, defined NPCs — anyone with this component can trigger
# heat when they observe a crime. Pursuit is a separate concern owned
# by PoliceSystem and only applies to CopNPC.
#
# Facing direction: the component samples its parent for a property or
# method that exposes facing. CopNPC has _facing_vec; other NPCs can
# expose facing_vec via a property. Falls back to Vector2.DOWN.

# Cone width for the FOV check.
@export var fov_degrees: float = 130.0

@export var notice_distance: float = 140.0   # fixed; NOT affected by camera

# Per-crime-type reaction weight. Missing keys default to 1.0.
# Civilian defaults are usually fine; cops override via CopProfile.
@export var reaction_weights: Dictionary = {}

# When true, the component pulls reaction weights from CopProfile.notice_weight
# on its parent instead of from reaction_weights above. Cop archetypes
# already have this data — no point duplicating it.
@export var use_parent_cop_profile: bool = false

@onready var _notifier: VisibleOnScreenNotifier2D = $VisibleOnScreenNotifier2D


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	if _notifier == null:
		push_warning("WitnessComponent on '%s': no VisibleOnScreenNotifier2D child" % get_parent().name)
	WitnessRegistry.register(self)


func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	WitnessRegistry.unregister(self)


# --- Witness interface --------------------------------------------------

func can_witness(player: Node2D) -> bool:
	if player == null:
		return false
	var origin: Vector2 = global_position
	var to_player: Vector2 = player.global_position - origin
	var dist_sq: float = to_player.length_squared()
	if dist_sq > notice_distance * notice_distance:
		return false                      # too far — fixed range, camera-independent
	if dist_sq < 1.0:
		return true
	var facing: Vector2 = _resolve_facing().normalized()
	if facing.length_squared() < 0.01:
		return true
	var dir_to_player: Vector2 = to_player.normalized()
	var dot: float = facing.dot(dir_to_player)
	return dot >= cos(deg_to_rad(fov_degrees * 0.5))


# crime_id and delta are passed through so subclasses / parents can implement
# stateful reactions (e.g. cop notice delay). Default impl ignores them.
func reaction_weight(crime_type: StringName, _crime_id: int = 0, _delta: float = 0.0) -> float:
	if use_parent_cop_profile:
		var parent: Node = get_parent()
		if parent != null and parent.has_method("reaction_weight_with_notice"):
			return parent.reaction_weight_with_notice(crime_type, _crime_id, _delta)
		# Fall back to raw profile weight if parent doesn't implement notice.
		if parent != null and parent.get("profile") != null:
			var profile = parent.get("profile")
			if profile != null and profile.has_method("reaction_weight"):
				return profile.reaction_weight(crime_type)
	return float(reaction_weights.get(crime_type, 1.0))


# Convenience for CrimeSystem — used when it needs the cop reference,
# not the component, to dispatch pursuit.
func get_witness_owner() -> Node:
	return get_parent()


# --- Internal -----------------------------------------------------------

func _resolve_facing() -> Vector2:
	var parent: Node = get_parent()
	if parent == null:
		return Vector2.DOWN
	# CopNPC and any other NPC that maintains a facing vector exposes it
	# as _facing_vec. Pull via get() so this works without a hard dep.
	var v = parent.get("_facing_vec")
	if v is Vector2 and (v as Vector2).length_squared() > 0.01:
		return v
	# Pedestrians with a facing_vec property (public name) also work.
	v = parent.get("facing_vec")
	if v is Vector2 and (v as Vector2).length_squared() > 0.01:
		return v
	return Vector2.DOWN
