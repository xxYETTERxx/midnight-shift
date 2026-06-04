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
const BUST_FINE: int = 50
const BUST_SKIP_HOURS: int = 2
const BUST_WAKE_ROOM: String = "res://scenes/rooms/city_central.tscn"
const BUST_WAKE_GROUP: StringName = &"default"   # spawn marker group
const BUST_LIE_BEAT: float = 2.0   # seconds the lying-down pose shows before fade


signal crime_began(crime_id: int, crime_type: StringName, position: Vector2, area_id: StringName)
signal crime_witnessed(crime_id: int, crime_type: StringName, position: Vector2, area_id: StringName, witness: WitnessComponent)
signal crime_ended(crime_id: int, crime_type: StringName, area_id: StringName, outcome: Outcome, was_witnessed: bool)
signal player_busted(record: Dictionary)

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
# Permanent crime ledger for the future courthouse/audit system. Each entry:
# { "crime_id": int, "minute": int, "area_id": StringName,
#   "crime_type": StringName, "status": "suspected"|"confirmed",
#   "confiscated": int }.
# A cop seeing a crime writes "suspected"; getting caught flips the most
# recent suspected entry to "confirmed". An NPC report (35% roll) also writes
# "suspected" but can never become "confirmed" (no cop = no case). The audit
# reads status counts as severity. Persisted via save_state.
var _bust_log: Array = []
var _bust_pending_respawn: bool = false
var _busted: bool = false
# NPC witness report chance — a nosy straight who saw it tells someone.
const NPC_REPORT_CHANCE: float = 0.35


func _ready() -> void:
	set_process(true)
	TimeSkipSystem.time_skipped.connect(_on_time_skipped)


func _process(delta: float) -> void:
	if _active.is_empty():
		return
	if int(Time.get_ticks_msec() / 1000) % 2 == 0 and _eval_timer == 0.0:
		print("[CrimeSystem] active crimes: %s" % str(_active))
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
		print("no crime IDd")
		return
	print("crimeID YES")
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
	
func report_timed_crime(crime_type: StringName, position: Vector2, area_id: StringName = &"", duration: float = 3.0) -> void:
	var crime_id := begin_crime(crime_type, null, position, area_id)
	if _active.has(crime_id):
		_active[crime_id]["expires_at"] = Time.get_ticks_msec() / 1000.0 + duration


# --- Busts & confiscation -----------------------------------------------

func execute_bust(crime_type: StringName = &"pursuit", area_id: StringName = &"") -> void:
	if _busted:
		return
	_busted = true
	var player: Node = RoomManager.get_player()

	# Beat 1 — lying-down pose, briefly, before the screen blacks out.
	if player != null:
		_play_bust_pose(player)
		await get_tree().create_timer(BUST_LIE_BEAT).timeout

	# Beat 2 — confiscate + fine while we're about to fade (order doesn't
	# matter to the player; it's all resolved behind black).
	var confiscated: int = confiscate_drugs()
	var fine_paid: int = _apply_fine()

	# Log the bust (confirmed; flips a suspected entry by recency if present).
	record_bust(crime_type, area_id)

	# Beat 3 — skip 2 hours; TimeSkipSystem owns the fade. Reposition the
	# player while the screen is black, via the time_skipped listener below.
	_bust_pending_respawn = true
	TimeSkipSystem.skip_to(TimeSystem.total_minutes + BUST_SKIP_HOURS * 60, {
		"kind": "arrest",
		"safe": false,
		"voluntary": false,
	})

	# Beat 4 — notification.
	var summary := "BUSTED. Lost all drugs"
	if fine_paid > 0:
		summary += " and fined $%d" % fine_paid
	summary += "."
	NotificationSystem.warn(summary)

# $50 fine: clean first, then cash for whatever clean couldn't cover. Returns
# the total actually taken (may be less than the fine if the player's broke).
func _apply_fine() -> int:
	var owed: int = BUST_FINE
	var paid: int = 0
	var clean: int = Wallet.balance(Wallet.POOL_CLEAN)
	var from_clean: int = min(clean, owed)
	if from_clean > 0:
		Wallet.spend(from_clean, Wallet.POOL_CLEAN)
		paid += from_clean
		owed -= from_clean
	if owed > 0:
		var cash: int = Wallet.balance(Wallet.POOL_CASH)
		var from_cash: int = min(cash, owed)
		if from_cash > 0:
			Wallet.spend(from_cash, Wallet.POOL_CASH)
			paid += from_cash
	return paid


func _play_bust_pose(player: Node) -> void:
	# Disable the player's own movement/animation processing so it doesn't
	# overwrite the lie-down pose each frame, then play the pose if it exists.
	player.set_process(false)
	player.set_physics_process(false)
	var dir = player.last_direction
	var sprite = player.get_node_or_null("AnimatedSprite2D")  # AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null \
			and sprite.sprite_frames.has_animation("fall_s"):
		sprite.play("fall_" + dir)



func _on_time_skipped(_from: int, _to: int, context: Dictionary) -> void:
	if not _bust_pending_respawn:
		return
	if context.get("kind", "") != "arrest":
		return
	_bust_pending_respawn = false

	# change_room rebuilds the room (even if it's the same one) and positions
	# the player at SpawnPoints/default itself — no manual placement needed.
	_busted = false
	RoomManager.change_room(BUST_WAKE_ROOM, "default")

	# Re-enable player control now that they've been moved.
	var player: Node = RoomManager.get_player()
	if player != null:
		player.set_process(true)
		player.set_physics_process(true)

func _on_room_changed(room_name: String) -> void:
	end_crime(0,Outcome.COMPLETED)

# Central bust handler. Confiscates all DRUG-category items from the player,
# logs the bust for the courthouse ledger, and emits player_busted.
# crime_type/area_id are recorded; pass what you know (defaults derive area).
func record_bust(crime_type: StringName = &"", area_id: StringName = &"") -> void:
	if area_id == &"":
		area_id = _current_area_id()
	var confiscated: int = confiscate_drugs()

	# The bust path lost the originating crime_id, so reconcile by recency:
	# flip the most recent still-suspected entry to confirmed. If none exists,
	# append a fresh confirmed entry.
	var record: Dictionary = {}
	for i in range(_bust_log.size() - 1, -1, -1):
		if _bust_log[i].get("status", "confirmed") == "suspected":
			_bust_log[i]["status"] = "confirmed"
			_bust_log[i]["confiscated"] = confiscated
			_bust_log[i]["minute"] = TimeSystem.total_minutes
			record = _bust_log[i]
			break

	if record.is_empty():
		record = {
			"crime_id": -1,
			"minute": TimeSystem.total_minutes,
			"area_id": area_id,
			"crime_type": crime_type,
			"status": "confirmed",
			"confiscated": confiscated,
		}
		_bust_log.append(record)

	print("[CrimeSystem] BUST confirmed: %s" % str(record))
	player_busted.emit(record)

func record_ditched_court() -> void:
	_bust_log.append({
		"crime_id": _next_id,
		"minute": TimeSystem.total_minutes,
		"area_id": _current_area_id(),
		"crime_type": &"ditched_court",
		"status": "confirmed",
		"confiscated": 0,
	})
	_next_id += 1
	print("[CrimeSystem] DITCHED COURT logged (confirmed)")

# Removes every DRUG-category item from the player's inventory. Returns the
# total count confiscated. Safe to call when there's nothing to take.
func confiscate_drugs() -> int:
	var player: Node = RoomManager.get_player()
	if player == null or not ("inventory" in player) or player.inventory == null:
		return 0
	var inv = player.inventory
	var confiscated: int = 0
	for i in range(inv.slots.size()):
		var stack = inv.get_slot(i)
		if stack == null or stack.item == null:
			continue
		if stack.item.category == ItemDef.Category.DRUG:
			confiscated += stack.count
			inv.consume_from_slot(i, stack.count)
	return confiscated


# Read-only access for the courthouse / scrutiny systems (future).
func get_bust_log() -> Array:
	return _bust_log.duplicate()

# --- Evaluation ---------------------------------------------------------

func _evaluate_all(delta: float) -> void:
	for crime_id in _active.keys():
		_evaluate_one(crime_id, delta)


func _evaluate_one(crime_id: int, delta: float) -> void:
	if not _active.has(crime_id):
		return
	var entry: Dictionary = _active[crime_id]
	if entry.has("expires_at") and Time.get_ticks_msec() / 1000.0 >= entry["expires_at"]:
		end_crime(crime_id, Outcome.COMPLETED)
		return
	
	if entry["source"] != null and not is_instance_valid(entry["source"]):
		end_crime(crime_id, Outcome.CANCELLED)
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
		_record_witness(crime_id, entry["type"], entry["area_id"], witness)

	var owner_node: Node = witness.get_witness_owner()
	if owner_node is CopNPC:
		PoliceSystem.dispatch_pursuit(owner_node)


func _current_area_id() -> StringName:
	if RoomManager.current_room == null:
		return &""
	return StringName(RoomManager.current_room.scene_file_path.get_file().get_basename())
	
	
func _record_witness(crime_id: int, crime_type: StringName, area_id: StringName, witness: WitnessComponent) -> void:
	var is_cop: bool = witness.get_witness_owner() is CopNPC
	if not is_cop and randf() >= NPC_REPORT_CHANCE:
		return  # NPC saw it, said nothing
	_bust_log.append({
		"crime_id": crime_id,
		"minute": TimeSystem.total_minutes,
		"area_id": area_id,
		"crime_type": crime_type,
		"status": "suspected",
		"confiscated": 0,
	})
	print("[CrimeSystem] SUSPECTED logged: id=%d %s (cop=%s)" % [crime_id, crime_type, is_cop])
	SuspicionSystem.report_witnessed_crime(is_cop)	

func suspected_count() -> int:
	var n: int = 0
	for e in _bust_log:
		if e.get("status", "confirmed") == "suspected":
			n += 1
	return n


func confirmed_count() -> int:
	var n: int = 0
	for e in _bust_log:
		if e.get("status", "confirmed") == "confirmed":
			n += 1
	return n


func save_state() -> Dictionary:
	return { "bust_log": _bust_log }


func load_state(data: Dictionary) -> void:
	_bust_log = data.get("bust_log", [])
