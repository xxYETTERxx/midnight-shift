extends Node

# Active-crime registry. Crimes can be instantaneous (a completed deal) or
# sustained (a car loot in progress). For sustained crimes, CrimeSystem
# periodically re-runs witness checks against PoliceSystem while the crime
# is active; this is the chokepoint where "seen by a cop" actually gets
# decided.
#
# Crimes have three outcomes:
#   COMPLETED — the act finished (loot succeeded, deal handed off)
#   CANCELLED — the act was aborted (player walked away from the car)
# HeatSystem decides what to do with the witnessed/unwitnessed/completed
# combinations based on per-crime-type config.

signal crime_began(crime_id: int, crime_type: StringName, position: Vector2, area_id: StringName)
signal crime_witnessed(crime_id: int, crime_type: StringName, position: Vector2, area_id: StringName, witness: WitnessComponent)
signal crime_ended(crime_id: int, crime_type: StringName, area_id: StringName, outcome: Outcome, was_witnessed: bool)

enum Outcome { COMPLETED, CANCELLED }

const EVAL_INTERVAL: float = 0.5

# crime_id (int) → {
#   "type": StringName, "position": Vector2, "area_id": StringName,
#   "source": Object (optional, weakref-safe — used to skip dead sources),
#   "witnessed": bool,
# }
var _active: Dictionary = {}
var _next_id: int = 1
var _eval_timer: float = 0.0


func _ready() -> void:
	set_process(true)


func _process(delta: float) -> void:
	if _active.is_empty():
		return
	_eval_timer += delta
	if _eval_timer < EVAL_INTERVAL:
		return
	var elapsed: float = _eval_timer
	_eval_timer = 0.0
	_evaluate_all(elapsed)


# --- Public API ---------------------------------------------------------

# Start a sustained crime. Returns the crime_id used to end it.
func begin_crime(crime_type: StringName, source: Object, position: Vector2, area_id: StringName = &"") -> int:
	if area_id == &"":
		area_id = _current_area_id()
	var crime_id := _next_id
	_next_id += 1
	_active[crime_id] = {
		"type": crime_type,
		"position": position,
		"area_id": area_id,
		"source": source,
		"witnessed": false,
	}
	print("[CrimeSystem] begin %s id=%d at %s in %s" % [crime_type, crime_id, position, area_id])
	crime_began.emit(crime_id, crime_type, position, area_id)
	# Immediate first evaluation — a cop standing right next to the car
	# shouldn't wait up to 0.5s to notice.
	_evaluate_one(crime_id, 0.0)
	return crime_id


func end_crime(crime_id: int, outcome: Outcome) -> void:
	if not _active.has(crime_id):
		return
	var entry: Dictionary = _active[crime_id]
	_active.erase(crime_id)
	for w in WitnessRegistry._witnesses.values():
		if is_instance_valid(w):
			var owner_node: Node = w.get_witness_owner()
			if owner_node is CopNPC and owner_node.has_method("clear_notice"):
				owner_node.clear_notice(crime_id)
	print("[CrimeSystem] end %s id=%d outcome=%s witnessed=%s" % [
		entry["type"], crime_id, Outcome.keys()[outcome], entry["witnessed"],
	])
	crime_ended.emit(crime_id, entry["type"], entry["area_id"], outcome, entry["witnessed"])


# Convenience for crimes that are inherently instantaneous (a completed
# handoff). Wraps begin + immediate evaluation + end-completed.
func report_instant_crime(crime_type: StringName, position: Vector2, area_id: StringName = &"") -> void:
	var crime_id := begin_crime(crime_type, null, position, area_id)
	end_crime(crime_id, Outcome.COMPLETED)


# --- Evaluation ---------------------------------------------------------

func _evaluate_all(delta: float) -> void:
	for crime_id in _active.keys():
		_evaluate_one(crime_id, delta)


func _evaluate_one(crime_id: int, delta: float) -> void:
	if not _active.has(crime_id):
		return
	var entry: Dictionary = _active[crime_id]
	if entry["source"] != null and not is_instance_valid(entry["source"]):
		_active.erase(crime_id)
		return

	var player: Node2D = RoomManager.get_player()
	if player == null:
		return

	var witness: WitnessComponent = WitnessRegistry.find_witness(entry["type"], player, crime_id, delta)
	if witness == null:
		return

	if not entry["witnessed"]:
		entry["witnessed"] = true
		crime_witnessed.emit(crime_id, entry["type"], entry["position"], entry["area_id"], witness)

	var owner_node: Node = witness.get_witness_owner()
	if owner_node is CopNPC:
		PoliceSystem.dispatch_pursuit(owner_node)


func _current_area_id() -> StringName:
	if RoomManager.current_room == null:
		return &""
	return StringName(RoomManager.current_room.scene_file_path.get_file().get_basename())
