extends Node

# Manages daily car spawning across all outdoor scenes. Each morning at
# wake (TimeSystem.day_rolled), clears existing cars and spawns a fresh
# batch at registered spawn points. Cars persist their looted state across
# saves/loads within a day, but don't survive day rollovers.

const CAR_SCENE: PackedScene = preload("res://scenes/components/vehicle.tscn")

# Indexed as: SPRITES_BY_TIER[tier][orientation] = Array[Texture2D]
# Each [tier][orientation] cell is an array of variants to pick from randomly.
const SPRITES_BY_TIER: Array = [
	[  # tier 0
		[preload("res://art/objects/Interactables/Vehicles/Car0_Blue_N.png")],  # NORTH
		[preload("res://art/objects/Interactables/Vehicles/Car0_Blue_S.png")],  # SOUTH
		[preload("res://art/objects/Interactables/Vehicles/Car0_Blue_E.png")],  # EAST
		[preload("res://art/objects/Interactables/Vehicles/Car0_Blue_W.png")],  # WEST
	],
	[  # tier 1
		[preload("res://art/objects/Interactables/Vehicles/Car1_Orange_N.png")],
		[preload("res://art/objects/Interactables/Vehicles/Car1_Orange_S.png")],
		[preload("res://art/objects/Interactables/Vehicles/Car1_Orange_E.png")],
		[preload("res://art/objects/Interactables/Vehicles/Car1_Orange_W.png")],
	],
	[  # tier 2 — fill in when you have art
		[preload("res://art/objects/Interactables/Vehicles/Car3_White_N.png")],
		[preload("res://art/objects/Interactables/Vehicles/Car3_White_S.png")],
		[preload("res://art/objects/Interactables/Vehicles/Car3_White_E.png")],
		[preload("res://art/objects/Interactables/Vehicles/Car3_White_W.png")],
	],
]

# How many cars to spawn per outdoor scene each day. Tunable.
const CARS_PER_SCENE_MIN: int = 3
const CARS_PER_SCENE_MAX: int = 6

# Default tier weights if a scene doesn't override. [tier_0, tier_1, tier_2].
const DEFAULT_TIER_WEIGHTS: Array[float] = [0.7, 0.25, 0.05]

# Per-scene tier weight overrides. Key = scene path, value = Array[float].
# Author neighborhoods here as the map expands. Today's single neighborhood
# uses defaults.
const NEIGHBORHOOD_TIER_WEIGHTS: Dictionary = {
	# "res://scenes/world/nice_district.tscn": [0.2, 0.5, 0.3],
	# "res://scenes/world/industrial.tscn":    [0.9, 0.1, 0.0],
}

# Tier → loot table resource. Authored .tres files dropped in here.
const LOOT_TABLE_PATHS: Array[String] = [
	"res://data/loot_tables/car_tier_0.tres",
	"res://data/loot_tables/car_tier_1.tres",
	"res://data/loot_tables/car_tier_2.tres",
]

# Chance a spawned car is locked (vs. unlocked). Locked = slim jim required
# eventually, more loot. Per-tier, since nicer cars are more likely to be locked.
const LOCK_CHANCE_BY_TIER: Array[float] = [0.4, 0.7, 0.9]

# Track which scenes have already had their cars generated today, so we
# don't re-roll fresh cars every time the player walks back outside.
var _scenes_generated_today: Dictionary = {}
# spawn_id (as String) → {scene_path, x, y}
var _spawn_points: Dictionary = {}

# car_id (as String) → state Dictionary. The "current day" snapshot of spawned
# cars. Lets us re-instantiate them when the player re-enters a scene mid-day.
var _car_states: Dictionary = {}

# Cached loot tables, lazy-loaded.
var _loot_tables: Array[LootTable] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_car_id: int = 1


func _ready() -> void:
	SaveSystem.register_savable("car_spawner", self)
	_rng.seed = Time.get_ticks_usec()
	TimeSystem.day_rolled.connect(_on_day_rolled)
	RoomManager.room_changed.connect(_on_room_changed)
	_load_loot_tables()


func _load_loot_tables() -> void:
	_loot_tables.clear()
	for path in LOOT_TABLE_PATHS:
		if ResourceLoader.exists(path):
			_loot_tables.append(load(path))
		else:
			push_warning("CarSpawner: missing loot table at %s" % path)
			_loot_tables.append(null)


# --- Spawn point registry ---

func register_spawn_point(id: StringName, scene_path: String, world_pos: Vector2,orientation: int = CarSpawnPoint.Orientation.SOUTH) -> void:
	if id == &"":
		print("registration sucess")
		return
	_spawn_points[String(id)] = {
		"scene_path": scene_path,
		"x": world_pos.x,
		"y": world_pos.y,
		"orientation": orientation,
	}
	print(_spawn_points)


func unregister_spawn_point(id: StringName) -> void:
	_spawn_points.erase(String(id))


# --- Daily rollover ---

func _on_day_rolled(_dow: int, _dom: int) -> void:
	_car_states.clear()
	_scenes_generated_today.clear()
	_clear_existing_cars()
	# Spawn any cars that belong in the player's current scene.
	_materialize_cars_for_current_scene()


func _clear_existing_cars() -> void:
	_car_states.clear()
	# Despawn any currently-live car instances. They'll be re-created from
	# _car_states on demand.
	var current_room: Node = RoomManager.current_room
	if current_room == null:
		return
	var container: Node = current_room.get_node_or_null("Cars")
	if container != null:
		for c in container.get_children():
			c.queue_free()


func _roll_tier(weights: Array) -> int:
	var total: float = 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return 0
	var pick: float = _rng.randf() * total
	var cumulative: float = 0.0
	for i in range(weights.size()):
		cumulative += weights[i]
		if pick <= cumulative:
			return i
	return weights.size() - 1


# --- Room changes (materialize cars in the current scene) ---

func _on_room_changed(_room_path: String) -> void:
	_ensure_scene_generated()
	_materialize_cars_for_current_scene()


func _materialize_cars_for_current_scene() -> void:
	var room: Node = RoomManager.current_room
	if room == null:
		return
	var scene_path: String = room.scene_file_path
	print("[CarSpawner] materializing for scene: '%s'" % scene_path)
	# Find or create a Cars container in this room.
	var container: Node = room.get_node_or_null("Cars")
	if container == null:
		container = Node2D.new()
		container.name = "Cars"
		container.y_sort_enabled = true
		room.add_child(container)
	# Clear stale car instances (e.g., from a previous scene visit).
	for c in container.get_children():
		c.queue_free()
	# Spawn cars whose state says they belong here.
	for car_id in _car_states:
		var state: Dictionary = _car_states[car_id]
		print("  car %s stored scene: '%s'" % [car_id, state.get("scene_path", "")])
		if state.get("scene_path", "") != scene_path:
			continue
		_instantiate_car(container, state)


func _instantiate_car(parent: Node, state: Dictionary) -> void:
	var car: LootableCar = CAR_SCENE.instantiate()
	parent.add_child(car)
	car.from_state(state)
	var tier: int = state.get("tier", 0)
	if tier >= 0 and tier < _loot_tables.size():
		car.loot_table = _loot_tables[tier]
	_apply_sprite(car, state)
	car.looted.connect(func(_drops): _on_car_looted(car.car_id))

func _apply_sprite(car: LootableCar, state: Dictionary) -> void:
	var tier: int = state.get("tier", 0)
	var orientation: int = state.get("orientation", CarSpawnPoint.Orientation.SOUTH)
	if tier < 0 or tier >= SPRITES_BY_TIER.size():
		return
	var by_orientation: Array = SPRITES_BY_TIER[tier]
	if orientation < 0 or orientation >= by_orientation.size():
		return
	var variants: Array = by_orientation[orientation]
	if variants.is_empty():
		return
	var idx: int = state.get("sprite_index", 0)
	if idx >= variants.size():
		idx = 0
	car.sprite.texture = variants[idx]


func _on_car_looted(car_id: StringName) -> void:
	var key := String(car_id)
	if _car_states.has(key):
		_car_states[key]["is_looted"] = true

func _ensure_scene_generated() -> void:
	var room: Node = RoomManager.current_room
	if room == null:
		return
	var scene_path: String = room.scene_file_path
	if _scenes_generated_today.get(scene_path, false):
		return
	_generate_cars_for_scene(scene_path)
	_scenes_generated_today[scene_path] = true

func _generate_cars_for_scene(scene_path: String) -> void:
	# Find spawn points in this scene.
	print("spawn car 1")
	var sp_ids: Array = []
	for sp_id in _spawn_points:
		var sp: Dictionary = _spawn_points[sp_id]
		if sp.get("scene_path", "") == scene_path:
			sp_ids.append(sp_id)
	if sp_ids.is_empty():
		print("sp_ids empty")
		return
	sp_ids.shuffle()
	var target_count: int = _rng.randi_range(CARS_PER_SCENE_MIN, CARS_PER_SCENE_MAX)
	var spawn_count: int = min(target_count, sp_ids.size())
	var weights: Array = NEIGHBORHOOD_TIER_WEIGHTS.get(scene_path, DEFAULT_TIER_WEIGHTS)

	for i in range(spawn_count):
		print("spawn car 2")
		var sp_id: String = sp_ids[i]
		var sp: Dictionary = _spawn_points[sp_id]
		var tier: int = _roll_tier(weights)
		var orientation: int = sp.get("orientation", CarSpawnPoint.Orientation.SOUTH)
		var sprite_idx: int = 0
		if tier < SPRITES_BY_TIER.size():
			var by_orientation: Array = SPRITES_BY_TIER[tier]
			if orientation < by_orientation.size():
				var variants: Array = by_orientation[orientation]
				if not variants.is_empty():
					sprite_idx = _rng.randi() % variants.size()
		var car_id: String = "car_%04d" % _next_car_id
		_next_car_id += 1
		_car_states[car_id] = {
			"car_id": car_id,
			"tier": tier,
			"is_locked": _rng.randf() < LOCK_CHANCE_BY_TIER[tier],
			"is_looted": false,
			"position_x": sp.get("x", 0.0),
			"position_y": sp.get("y", 0.0),
			"orientation": orientation,
			"sprite_index": sprite_idx,
			"scene_path": scene_path,
		}

# --- Save/load ---

func save_state() -> Dictionary:
	return {
		"car_states": _car_states.duplicate(true),
		"scenes_generated_today": _scenes_generated_today.duplicate(),
		"next_car_id": _next_car_id,
	}


func load_state(data: Dictionary) -> void:
	var saved = data.get("car_states", {})
	if saved is Dictionary:
		_car_states = saved.duplicate(true)
	_scenes_generated_today = data.get("scenes_generated_today", {}).duplicate()
	_next_car_id = data.get("next_car_id", 1)
	# Re-materialize for the current scene, since the room_changed signal
	# that loaded this scene fired BEFORE our state was restored.
	call_deferred("_materialize_cars_for_current_scene")
