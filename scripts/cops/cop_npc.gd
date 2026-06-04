@tool
class_name CopNPC
extends ScheduledNPC

# Cop archetype + state machine. By default behaves as a ScheduledNPC,
# walking authored patrols from .sched. PoliceSystem flips state to
# PURSUIT/INVESTIGATE in response to crimes; while in those states this
# script drives movement via NavigationAgent2D and NPCDirector's schedule
# pose updates are suspended for this NPC (see NPCDirector override hook).

enum State { ROUTINE, PURSUIT, INVESTIGATE }

@export var profile: CopProfile

# Emitted on entry/exit of pursuit-related states. PoliceSystem uses these
# to track who's chasing, request backup later, etc.
signal state_changed(new_state: State)
signal backup_requested(position: Vector2)
signal player_caught()

const WAYPOINT_REACH_RADIUS: float = 6.0

const CATCH_RADIUS: float = 16.0

var state: State = State.ROUTINE

var _agent: NavigationAgent2D
var _patrolling: bool = false
var _patrol_points: Array[Vector2] = []
var _patrol_index: int = 0

# Per-crime noticing state. Keyed by crime_id.
#   { "elapsed": float, "threshold": float }
# A fresh threshold is rolled when noticing starts; resets fully on LOS loss.
var _noticing: Dictionary = {}

# Pursuit bookkeeping
var _target: Node2D = null
var _last_seen_position: Vector2 = Vector2.ZERO
var _los_lost_time: float = 0.0
var _investigate_elapsed: float = 0.0

# Last facing vector — preserved when stationary, updated during movement.
# Used for FOV checks. Defaults to "south" to match the idle convention.
var _facing_vec: Vector2 = Vector2.DOWN

signal patrol_finished()


func _ready() -> void:
	super._ready()
	print("[CopNPC] %s ready, profile=%s" % [name, profile.profile_id if profile else "<NONE>"])
	PoliceSystem.register_cop(self)
	State.ROUTINE
	if profile != null and profile.sprite_frames != null:
		sprite_frames = profile.sprite_frames

	_agent = get_node_or_null("NavigationAgent2D")
	if _agent == null:
		push_warning("CopNPC '%s' has no NavigationAgent2D child" % name)



# --- Public API (PoliceSystem calls these) -----------------------------

# Returns whether this cop's schedule should be suppressed by NPCDirector.
func is_overridden() -> bool:
	return state != State.ROUTINE


# Start a generic patrol. Cop walks the chain at profile.patrol_speed and
# emits patrol_finished when it reaches the last waypoint. Pursuit
# interrupts but doesn't cancel — when pursuit ends, patrol resumes from
# the current index.
func set_patrol(points: Array[Vector2]) -> void:
	if points.size() < 2:
		push_warning("CopNPC '%s': set_patrol needs at least 2 points" % name)
		return
	_patrolling = true
	_patrol_points = points
	_patrol_index = 1  # walking toward index 1; index 0 is the spawn point
	global_position = points[0]
	var delta: Vector2 = points[1] - points[0]
	if delta.length_squared() > 0.01:
		_facing_vec = delta.normalized()
	print("[CopNPC] %s patrol started, %d points, speed=%.0f" % [name, points.size(), profile.patrol_speed if profile else -1.0])


func _tick_patrol(delta: float) -> void:
	if profile == null or _patrol_points.is_empty():
		return
	if _patrol_index >= _patrol_points.size():
		_patrolling = false
		patrol_finished.emit()
		return

	var target: Vector2 = _patrol_points[_patrol_index]
	var to_target: Vector2 = target - global_position
	var dist: float = to_target.length()

	if dist <= WAYPOINT_REACH_RADIUS:
		_patrol_index += 1
		return

	var step: float = profile.patrol_speed * delta
	if step >= dist:
		global_position = target
		_patrol_index += 1
		return

	var dir: Vector2 = to_target / dist
	global_position += dir * step
	_facing_vec = dir
	_play_animation("walk", _facing_string())



func begin_pursuit(target: Node2D) -> void:
	if target == null:
		return
	_target = target
	_last_seen_position = target.global_position
	_los_lost_time = 0.0
	_set_state(State.PURSUIT)


func end_pursuit() -> void:
	# Hard reset — used for player-entered-interior. Skip INVESTIGATE.
	_target = null
	_los_lost_time = 0.0
	_investigate_elapsed = 0.0
	_set_state(State.ROUTINE)

func _exit_tree() -> void:
	if Engine.is_editor_hint():
		return
	PoliceSystem.unregister_cop(self)

# --- State machine -----------------------------------------------------

func _set_state(s: State) -> void:
	if s == state:
		return
	state = s
	state_changed.emit(s)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	match state:
		State.ROUTINE:
			if _patrolling:
				_tick_patrol(delta)
			else:
				super._process(delta)  # ScheduledNPC's transit lerp
		State.PURSUIT:
			_tick_pursuit(delta)
		State.INVESTIGATE:
			_tick_investigate(delta)


func _tick_pursuit(delta: float) -> void:
	if _agent == null or _target == null:
		_set_state(State.INVESTIGATE)
		return

	# Visibility check — viewport gates the chase for now. Cone gates only
	# initial detection (handled by PoliceSystem on crime); once we're
	# chasing, viewport alone keeps it alive.
	var visible_now: bool = _is_visible_for_pursuit()
	if visible_now:
		_last_seen_position = _target.global_position
		_los_lost_time = 0.0
	else:
		_los_lost_time += delta
		if _los_lost_time >= profile.pursuit_los_grace:
			backup_requested.emit(_last_seen_position)
			_investigate_elapsed = 0.0
			_set_state(State.INVESTIGATE)
			return

	_agent.target_position = _last_seen_position
	_step_along_nav(delta, profile.pursuit_speed)

	# Caught check — only if currently visible (don't "catch" through walls)
	if visible_now and global_position.distance_to(_target.global_position) <= CATCH_RADIUS:
		player_caught.emit()

func _is_visible_for_pursuit() -> bool:
	var wc: WitnessComponent = get_node_or_null("WitnessComponent")
	if wc == null:
		return true
	var notifier: VisibleOnScreenNotifier2D = wc.get_node_or_null("VisibleOnScreenNotifier2D")
	if notifier == null:
		return true
	return notifier.is_on_screen()

func _tick_investigate(delta: float) -> void:
	if _agent == null:
		_set_state(State.ROUTINE)
		return

	_agent.target_position = _last_seen_position
	# Reached the spot — stand and look around for the configured duration.
	if global_position.distance_to(_last_seen_position) <= 4.0:
		_investigate_elapsed += delta
		_play_animation("idle", _facing_string())
		if _investigate_elapsed >= profile.investigate_duration:
			_target = null
			_set_state(State.ROUTINE)
		return

	_step_along_nav(delta, profile.patrol_speed)


# --- Movement helper ---------------------------------------------------

func _step_along_nav(delta: float, speed: float) -> void:
	if _agent.is_navigation_finished():
		return
	var next: Vector2 = _agent.get_next_path_position()
	var dir: Vector2 = (next - global_position).normalized()
	global_position += dir * speed * delta
	if dir.length_squared() > 0.01:
		_facing_vec = dir
	_play_animation("walk", _facing_string())


func _facing_string() -> String:
	if abs(_facing_vec.x) > abs(_facing_vec.y):
		return "east" if _facing_vec.x > 0.0 else "west"
	return "south" if _facing_vec.y > 0.0 else "north"


# Override ScheduledNPC's set_stand to also update our facing vector,
# so stationary cops have a meaningful cone direction.
func set_stationary(position: Vector2, facing: String, animation: String) -> void:
	super.set_stationary(position, facing, animation)
	_facing_vec = _facing_string_to_vec(facing)


# When transit pushes a new pose, update facing from the first leg so
# witness cone follows the patrol direction immediately.
func set_transit(points: Array[Vector2], start_minute: int, end_minute: int, animation_prefix: String = "walk") -> void:
	super.set_transit(points, start_minute, end_minute, animation_prefix)
	if points.size() >= 2:
		var delta: Vector2 = points[1] - points[0]
		if delta.length_squared() > 0.01:
			_facing_vec = delta.normalized()


func _facing_string_to_vec(f: String) -> Vector2:
	match f:
		"north": return Vector2.UP
		"east": return Vector2.RIGHT
		"west": return Vector2.LEFT
		_: return Vector2.DOWN
		
# Called via WitnessComponent.reaction_weight when use_parent_cop_profile
# is on. Implements the notice-delay window: each new encounter rolls a
# threshold in [0, profile.notice_delay], accumulates while the cop has
# eyes on the crime, and only returns the profile's weight once the
# threshold fills. LOS loss this frame clears the entry entirely.
#
# Called every EVAL_INTERVAL while can_witness is true; we know LOS held
# this tick because the registry only invokes us in that case.
func reaction_weight_with_notice(crime_type: StringName, crime_id: int, delta: float) -> float:
	if profile == null:
		return 0.0
	var base_weight: float = profile.reaction_weight(crime_type)
	if base_weight <= 0.0:
		return 0.0

	# notice_delay of 0 → instant react (legacy / cops with zero patience).
	if profile.notice_delay <= 0.0:
		return base_weight

	if not _noticing.has(crime_id):
		var threshold: float = randf_range(0.0, profile.notice_delay)
		_noticing[crime_id] = {"elapsed": 0.0, "threshold": threshold}

	var entry: Dictionary = _noticing[crime_id]
	entry["elapsed"] += delta

	if entry["elapsed"] >= entry["threshold"]:
		_noticing.erase(crime_id)  # commitment — drop the bookkeeping
		return base_weight

	return 0.0


# Called by CrimeSystem when LOS to a crime is lost or the crime ends.
# Resets any in-progress noticing so the next encounter rolls fresh.
func clear_notice(crime_id: int) -> void:
	_noticing.erase(crime_id)
