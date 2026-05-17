class_name TransitNPC
extends Node2D

# Ephemeral pedestrian. Spawned by TransitSpawner with a random
# appearance and a pre-resolved route through the current room.
# Walks the route at WALK_SPEED, despawns at the end. No interaction,
# no persistence — purely visual world filler.

const WALK_SPEED: float = 70.0  # matches CustomerNPC; same speed feels right

const WALK_PREFIX: String = "walk"
const IDLE_PREFIX: String = "idle"

@onready var sprite: CharacterSprite = $Sprite

var _route: Array[Vector2] = []
var _segment_idx: int = 0
var _segment_progress: float = 0.0
var _arrived: bool = false
var _facing: String = "s"


func _ready() -> void:
	# Roll appearance + dialogue at spawn — no roster, no persistence.
	# The dialogue line currently goes nowhere (transit NPCs have no
	# interaction), but it's there for future flavor pop-ups.
	var identity: Dictionary = NPCGenerator.generate_transit_identity()
	sprite.apply_appearance(
		&"transit",
		identity.get("head_index", -1),
		identity.get("body_index", -1),
	)


# Begin walking the provided point chain. Mirrors CustomerNPC.walk_route
# but without the arrival-stop semantics — the last waypoint frees the NPC.
func walk_route(points: Array[Vector2]) -> void:
	_route = points
	_segment_idx = 0
	_segment_progress = 0.0
	_arrived = false
	if _route.size() < 2:
		queue_free()
		return
	global_position = _route[0]
	_update_facing_for_segment(0)
	sprite.play_anim(WALK_PREFIX, _facing)


func _process(delta: float) -> void:
	if _arrived or _route.size() < 2:
		return
	var step: float = WALK_SPEED * delta
	while step > 0.0 and _segment_idx < _route.size() - 1:
		var seg_start: Vector2 = _route[_segment_idx]
		var seg_end: Vector2 = _route[_segment_idx + 1]
		var seg_len: float = seg_start.distance_to(seg_end)
		if seg_len <= 0.0:
			_segment_idx += 1
			_segment_progress = 0.0
			continue
		var remaining_in_seg: float = seg_len - _segment_progress
		if step < remaining_in_seg:
			_segment_progress += step
			global_position = seg_start.lerp(seg_end, _segment_progress / seg_len)
			return
		step -= remaining_in_seg
		_segment_idx += 1
		_segment_progress = 0.0
		if _segment_idx >= _route.size() - 1:
			global_position = _route[-1]
			_arrived = true
			queue_free()
			return
		_update_facing_for_segment(_segment_idx)
		sprite.play_anim(WALK_PREFIX, _facing)


func _update_facing_for_segment(idx: int) -> void:
	if idx < 0 or idx >= _route.size() - 1:
		return
	var d: Vector2 = _route[idx + 1] - _route[idx]
	if abs(d.x) > abs(d.y):
		_facing = "e" if d.x > 0.0 else "w"
	else:
		_facing = "s" if d.y > 0.0 else "n"
