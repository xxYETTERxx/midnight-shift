class_name BottleRegion
extends Node2D

# Drop this into an outdoor scene and give it a RectangleShape2D (on the
# $Area/CollisionShape2D child). Each morning it clears yesterday's bottles
# and scatters a fresh random number of ground-bottle pickups at random
# points inside the rectangle.
#
# Self-contained: there's no central spawner. Each region owns its own daily
# roll and its own pile of spawned bottles. State persists within a day
# (save/load mid-day keeps the same bottles) but rerolls each morning.

const BOTTLE_SCENE: PackedScene = preload("res://scenes/components/bottle.tscn")

# How many cosmetic sprite variants exist. The region rolls an index in
# [0, count); Bottle clamps against its real art array, so this can run
# ahead of the art drop.
const SPRITE_VARIANT_COUNT: int = 50

# Daily count of bottle PILES scattered in this region.
@export var piles_min: int = 4
@export var piles_max: int = 9

# Bottles per pile.
@export var bottles_per_pile_min: int = 1
@export var bottles_per_pile_max: int = 4

# Stable id so the save system can tell regions apart. MUST be unique
# per region across all scenes. Set it in the inspector.
@export var region_id: StringName = &""

@onready var _area: Area2D = $Area
@onready var _shape: CollisionShape2D = $Area/CollisionShape2D

var _rng := RandomNumberGenerator.new()
# Live spawned bottles, so we can clear them on reroll.
var _spawned: Array[Bottle] = []
# Current-day snapshot, for save/load within a day.
var _states: Array = []
var _generated_today: bool = false
var _next_local_id: int = 1


func _ready() -> void:
	if region_id == &"":
		push_warning("BottleRegion at %s has no region_id" % global_position)
	_rng.seed = hash(region_id) ^ Time.get_ticks_usec()
	SaveSystem.register_savable("bottle_region_" + String(region_id), self)
	TimeSystem.day_rolled.connect(_on_day_rolled)
	# First-ever entry with no save data: generate today's batch now.
	if not _generated_today:
		_roll_new_day()
	_materialize()


# --- Daily roll ---------------------------------------------------------

func _on_day_rolled(_dow: int, _dom: int) -> void:
	_roll_new_day()
	_materialize()


func _roll_new_day() -> void:
	_states.clear()
	var pile_count: int = _rng.randi_range(piles_min, piles_max)
	for i in range(pile_count):
		var bid: String = "%s_%04d" % [region_id, _next_local_id]
		_next_local_id += 1
		var pos: Vector2 = _random_point_in_rect()
		_states.append({
			"bottle_id": bid,
			"bottle_count": _rng.randi_range(bottles_per_pile_min, bottles_per_pile_max),
			"sprite_index": _rng.randi() % SPRITE_VARIANT_COUNT,
			"position_x": pos.x,
			"position_y": pos.y,
		})
	_generated_today = true


# Returns a random world-space point inside the rectangle shape. If you ever
# switch to a CollisionPolygon2D, replace this with rejection sampling:
# pick points in the polygon's bounding box and keep the first that passes
# Geometry2D.is_point_in_polygon().
func _random_point_in_rect() -> Vector2:
	var rect_shape := _shape.shape as RectangleShape2D
	if rect_shape == null:
		push_warning("BottleRegion '%s': shape is not a RectangleShape2D" % region_id)
		return _shape.global_position
	var half: Vector2 = rect_shape.size * 0.5
	var local := Vector2(
		_rng.randf_range(-half.x, half.x),
		_rng.randf_range(-half.y, half.y),
	)
	# Respect the shape node's own transform (position/scale relative to region).
	return _shape.global_position + local
	
	
# --- Materialization ----------------------------------------------------

func _materialize() -> void:
	_clear_spawned()
	for state in _states:
		var bottle: Bottle = BOTTLE_SCENE.instantiate()
		add_child(bottle)
		bottle.from_state(state)
		bottle.collected.connect(_on_bottle_collected)
		_spawned.append(bottle)


func _clear_spawned() -> void:
	for b in _spawned:
		if is_instance_valid(b):
			b.queue_free()
	_spawned.clear()


func _on_bottle_collected(bottle_id: StringName) -> void:
	# Drop it from the day's snapshot so a mid-day save/reload doesn't
	# resurrect a bottle the player already grabbed.
	var key := String(bottle_id)
	for i in range(_states.size()):
		if _states[i].get("bottle_id", "") == key:
			_states.remove_at(i)
			return
			
			
# --- Save / load --------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"states": _states.duplicate(true),
		"generated_today": _generated_today,
		"next_local_id": _next_local_id,
	}


func load_state(data: Dictionary) -> void:
	var s = data.get("states", [])
	if s is Array:
		_states = s.duplicate(true)
	_generated_today = data.get("generated_today", false)
	_next_local_id = data.get("next_local_id", 1)
	# _ready() may have already rolled a batch before load fired; the loaded
	# snapshot is authoritative, so re-materialize from it.
	call_deferred("_materialize")
