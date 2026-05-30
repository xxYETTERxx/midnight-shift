extends Node

# Manages daily spawning of scavenge content (ground bottles + garbage cans)
# across outdoor scenes. Modeled on CarSpawner: each morning at wake
# (TimeSystem.day_rolled) it clears the old batch and rolls a fresh one at
# registered spawn points. State persists across saves/loads within a day,
# but doesn't survive day rollovers.
#
# Two content types with different daily rules:
#
#   Ground bottles  — like cars: only a random SUBSET of bottle points get a
#                     bottle each day, so the player can't farm a fixed set.
#
#   Garbage cans    — every can point ALWAYS gets a can. What varies is
#                     whether the can is STOCKED with bottles: a random N
#                     cans per scene are stocked each morning; the rest are
#                     present but empty. This keeps cans as fixed landmarks
#                     while still discouraging "hit every can every day."

const BOTTLE_SCENE: PackedScene = preload("res://scenes/components/bottle.tscn")
const CAN_SCENE: PackedScene = preload("res://scenes/components/garbage_can.tscn")

# How many cosmetic bottle sprite variants exist. The spawner picks an index
# in [0, BOTTLE_SPRITE_VARIANT_COUNT); Bottle clamps it against its actual
# art array on load, so this can safely run ahead of the art drop.
const BOTTLE_SPRITE_VARIANT_COUNT: int = 50

# --- Ground bottle tuning ---
const BOTTLE_POINTS_STOCKED_MIN: int = 4
const BOTTLE_POINTS_STOCKED_MAX: int = 9
const BOTTLES_PER_PILE_MIN: int = 1
const BOTTLES_PER_PILE_MAX: int = 4

# --- Can tuning ---
# How many of a scene's cans get stocked with bottles each day.
const CANS_STOCKED_MIN: int = 3
const CANS_STOCKED_MAX: int = 6
const BOTTLES_PER_CAN_MIN: int = 3
const BOTTLES_PER_CAN_MAX: int = 10

# Track which scenes have been generated today (so re-entering a scene
# mid-day doesn't re-roll fresh content).
var _scenes_generated_today: Dictionary = {}

# spawn_id (String) → {scene_path, x, y}
var _bottle_points: Dictionary = {}
var _can_points: Dictionary = {}

# id (String) → state Dictionary, the current-day snapshot used to
# re-instantiate when the player re-enters a scene mid-day.
var _bottle_states: Dictionary = {}
var _can_states: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _next_bottle_id: int = 1
var _next_can_id: int = 1


func _ready() -> void:
	SaveSystem.register_savable("scavenge_spawner", self)
	_rng.seed = Time.get_ticks_usec()
	TimeSystem.day_rolled.connect(_on_day_rolled)
	RoomManager.room_changed.connect(_on_room_changed)


# --- Spawn point registry ----------------------------------------------

func register_bottle_point(id: StringName, scene_path: String, world_pos: Vector2) -> void:
	if id == &"":
		return
	_bottle_points[String(id)] = {
		"scene_path": scene_path, "x": world_pos.x, "y": world_pos.y,
	}


func unregister_bottle_point(id: StringName) -> void:
	_bottle_points.erase(String(id))


func register_can_point(id: StringName, scene_path: String, world_pos: Vector2) -> void:
	if id == &"":
		return
	_can_points[String(id)] = {
		"scene_path": scene_path, "x": world_pos.x, "y": world_pos.y,
	}


func unregister_can_point(id: StringName) -> void:
	_can_points.erase(String(id))


# --- Daily rollover -----------------------------------------------------

func _on_day_rolled(_dow: int, _dom: int) -> void:
	_bottle_states.clear()
	_can_states.clear()
	_scenes_generated_today.clear()
	_clear_live_instances()
	# Regenerate + materialize for the scene the player is currently standing in.
	_ensure_scene_generated()
	_materialize_for_current_scene()


# --- Room changes -------------------------------------------------------

func _on_room_changed(_room_name: String) -> void:
	_ensure_scene_generated()
	_materialize_for_current_scene()


func _ensure_scene_generated() -> void:
	var room: Node = RoomManager.current_room
	if room == null:
		return
	var scene_path: String = room.scene_file_path
	if _scenes_generated_today.get(scene_path, false):
		return
	_generate_bottles_for_scene(scene_path)
	_generate_cans_for_scene(scene_path)
	_scenes_generated_today[scene_path] = true


# --- Generation: ground bottles (random subset of points) ---------------

func _generate_bottles_for_scene(scene_path: String) -> void:
	var ids: Array = _points_in_scene(_bottle_points, scene_path)
	if ids.is_empty():
		return
	ids.shuffle()
	var target: int = _rng.randi_range(BOTTLE_POINTS_STOCKED_MIN, BOTTLE_POINTS_STOCKED_MAX)
	var count: int = min(target, ids.size())
	for i in range(count):
		var pid: String = ids[i]
		var p: Dictionary = _bottle_points[pid]
		var bid: String = "bottle_%04d" % _next_bottle_id
		_next_bottle_id += 1
		_bottle_states[bid] = {
			"bottle_id": bid,
			"bottle_count": _rng.randi_range(BOTTLES_PER_PILE_MIN, BOTTLES_PER_PILE_MAX),
			"sprite_index": _rng.randi() % BOTTLE_SPRITE_VARIANT_COUNT,
			"position_x": p["x"],
			"position_y": p["y"],
			"scene_path": scene_path,
		}


# --- Generation: cans (all points get a can; subset stocked) ------------

func _generate_cans_for_scene(scene_path: String) -> void:
	var ids: Array = _points_in_scene(_can_points, scene_path)
	if ids.is_empty():
		return
	# Decide which cans get stocked: shuffle and take the first N.
	var stocked_target: int = _rng.randi_range(CANS_STOCKED_MIN, CANS_STOCKED_MAX)
	var shuffled: Array = ids.duplicate()
	shuffled.shuffle()
	var stocked_set: Dictionary = {}
	for i in range(min(stocked_target, shuffled.size())):
		stocked_set[shuffled[i]] = true

	# Every can point gets a can; only the chosen subset gets bottles.
	for pid in ids:
		var p: Dictionary = _can_points[pid]
		var cid: String = "can_%04d" % _next_can_id
		_next_can_id += 1
		var bottles: int = 0
		if stocked_set.has(pid):
			bottles = _rng.randi_range(BOTTLES_PER_CAN_MIN, BOTTLES_PER_CAN_MAX)
		_can_states[cid] = {
			"can_id": cid,
			"bottle_count": bottles,
			"searched": false,
			"position_x": p["x"],
			"position_y": p["y"],
			"scene_path": scene_path,
		}


func _points_in_scene(points: Dictionary, scene_path: String) -> Array:
	var out: Array = []
	for pid in points:
		if points[pid].get("scene_path", "") == scene_path:
			out.append(pid)
	return out


# --- Materialization -----------------------------------------------------

func _materialize_for_current_scene() -> void:
	var room: Node = RoomManager.current_room
	if room == null:
		return
	var scene_path: String = room.scene_file_path
	var container: Node = _ensure_container(room, "Scavenge")
	# Clear stale instances from a previous visit.
	for c in container.get_children():
		c.queue_free()

	for bid in _bottle_states:
		var bs: Dictionary = _bottle_states[bid]
		if bs.get("scene_path", "") != scene_path:
			continue
		_instantiate_bottle(container, bs)

	for cid in _can_states:
		var cs: Dictionary = _can_states[cid]
		if cs.get("scene_path", "") != scene_path:
			continue
		_instantiate_can(container, cs)


func _ensure_container(room: Node, cname: String) -> Node:
	var container: Node = room.get_node_or_null(cname)
	if container == null:
		container = Node2D.new()
		container.name = cname
		container.y_sort_enabled = true
		room.add_child(container)
	return container


func _instantiate_bottle(parent: Node, state: Dictionary) -> void:
	var bottle: Bottle = BOTTLE_SCENE.instantiate()
	parent.add_child(bottle)
	bottle.from_state(state)
	bottle.collected.connect(_on_bottle_collected)


func _instantiate_can(parent: Node, state: Dictionary) -> void:
	var can: LootableCan = CAN_SCENE.instantiate()
	parent.add_child(can)
	can.from_state(state)
	can.searched.connect(func(_n): _on_can_searched(can.can_id))


# --- Live-state writeback (so re-entering a scene reflects what was taken) ---

func _on_bottle_collected(bottle_id: StringName) -> void:
	_bottle_states.erase(String(bottle_id))


func _on_can_searched(can_id: StringName) -> void:
	var key := String(can_id)
	if _can_states.has(key):
		_can_states[key]["searched"] = true
		_can_states[key]["bottle_count"] = 0


func _clear_live_instances() -> void:
	var room: Node = RoomManager.current_room
	if room == null:
		return
	var container: Node = room.get_node_or_null("Scavenge")
	if container != null:
		for c in container.get_children():
			c.queue_free()


# --- Save / load --------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"bottle_states": _bottle_states.duplicate(true),
		"can_states": _can_states.duplicate(true),
		"scenes_generated_today": _scenes_generated_today.duplicate(),
		"next_bottle_id": _next_bottle_id,
		"next_can_id": _next_can_id,
	}


func load_state(data: Dictionary) -> void:
	var bs = data.get("bottle_states", {})
	if bs is Dictionary:
		_bottle_states = bs.duplicate(true)
	var cs = data.get("can_states", {})
	if cs is Dictionary:
		_can_states = cs.duplicate(true)
	_scenes_generated_today = data.get("scenes_generated_today", {}).duplicate()
	_next_bottle_id = data.get("next_bottle_id", 1)
	_next_can_id = data.get("next_can_id", 1)
	# room_changed that loaded this scene fired BEFORE state was restored.
	call_deferred("_materialize_for_current_scene")
