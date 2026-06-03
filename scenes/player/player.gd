extends CharacterBody2D

@export var speed: float = 80.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var inventory: Inventory = $Inventory

# --- Stamina ---
@export var stamina_max: float = 100.0
@export var passive_drain_per_minute: float = 0.07
@export var movement_drain_per_minute: float = 0.05

@export var sprint_multiplier: float = 1.5
@export var sprint_drain_per_second: float = 10.0
var _is_sprinting: bool = false

# --- Vault ---
const VAULT_DURATION_BY_TIER: Array[float] = [0.6, 0.8, 1.3]
const VAULT_ARC_HEIGHT_BY_TIER: Array[float] = [15.0, 18.0, 32.0]
const TILE_SIZE: int = 32
const VAULT_STAMINA_COST: float = 2.0
const VAULT_XP_BY_TIER: Array[int] = [5, 10, 20]
const VAULT_LANDING_OFFSET_HORIZONTAL: float = 10.0
const VAULT_LANDING_OFFSET_VERTICAL: float = 0.0

const MOVEMENT_TOOL_SCENES: Array[String] = [
	"res://scenes/rooms/city_central.tscn",
]

var _is_vaulting: bool = false

var active_mode: StringName = &""
var active_mode_speed: float = 0.0

var stamina: float = 100.0

var input_locked: bool = false

var last_direction: String = "s"

var has_pager: bool = false



func _ready() -> void:
	TimeSystem.hour_tick.connect(_on_hour_tick)
	TimeSkipSystem.time_skipped.connect(_on_time_skipped)
	RoomManager.room_changed.connect(_on_room_changed)
	SaveSystem.register_savable("player", self)
	inventory.active_slot_changed.connect(_on_active_slot_changed)
	inventory.slot_changed.connect(_on_inventory_slot_changed)
	#RelationshipSystem.set_global_flag("has_job")
	_settle_idle()


func _physics_process(delta: float) -> void:
	if not TimeSystem.is_running():
		return
	if _is_vaulting:
		return
	if input_locked:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_animation(Vector2.ZERO)
		return
	
	var input_vector := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)

	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()

	var moving: bool = input_vector.length_squared() > 0.01
	var on_skateboard: bool = active_mode == &"skateboard"
	
	# Skateboard only works on pavement — ride off it and you step off.
	if on_skateboard and not _is_on_pavement():
		_exit_active_mode()
		on_skateboard = false
		NotificationSystem.warn("Can't skate off the pavement.")

	# Sprint is disabled while riding — you're already moving fast, and you
	# can't push off a board you're coasting on.
	var wants_sprint: bool = Input.is_action_pressed("sprint") and not on_skateboard
	_is_sprinting = wants_sprint and moving and stamina > 0.0

	var move_multiplier: float = PlayerSkills.speed_multiplier()
	if _is_sprinting:
		move_multiplier *= sprint_multiplier
		StaminaSystem.spend(sprint_drain_per_second * delta)

	# Active modes (skateboard) override the base walk speed; otherwise use it.
	var base_speed: float = active_mode_speed if on_skateboard else speed
	velocity = input_vector * base_speed * move_multiplier * _survival_speed_multiplier()
	move_and_slide()

	# Tell StaminaSystem what state we're in so passive/movement decay knows.
	StaminaSystem.set_movement_state(velocity.length() > 0.1, active_mode)

	# Athletics XP from distance actually moved (post-collision velocity).
	var dist := velocity.length() * delta
	if dist > 0.0:
		PlayerSkills.adjust_f(&"athletics", dist * PlayerSkills.ATHLETICS_XP_PER_PIXEL)
		var load: int = inventory.filled_slot_count()
		if load > 0:
			PlayerSkills.adjust_f(&"strength", dist * load * PlayerSkills.STRENGTH_XP_PER_PIXEL_PER_SLOT)

	_update_animation(input_vector)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		if _try_tool_interact():
			return
		if not InteractionManager.try_interact(self):
			PlacementSystem.try_place_active(self)
	
	
	# Hotbar cycling
	if event.is_action_pressed("hotbar_prev"):
		inventory.cycle_active_slot(-1)
	if event.is_action_pressed("hotbar_next"):
		inventory.cycle_active_slot(1)
	# Hotbar direct selection
	if event.is_action_pressed("hotbar_cycle_row"):
		inventory.cycle_hotbar_row()
	if event.is_action_pressed("vault"):
			_try_vault()
	for i in range(12):
		if event.is_action_pressed("hotbar_slot_%d" % (i + 1)):
			inventory.set_active_slot(i)
			break
	if event.is_action_pressed("alt_interact"):
		print("[alt] player pressed, winner=", InteractionManager._winner)
		var handled := InteractionManager.try_alt_interact(self)
		print("[alt] try_alt_interact returned=", handled)
		if not handled:
			PlacementSystem.try_pickup_targeted(self)

func _update_animation(input_vector: Vector2) -> void:
	if input_vector == Vector2.ZERO:
		sprite.pause()
		sprite.frame = 0
		return

	# Pick the animation based on the dominant axis.
	# Vertical wins on ties so diagonal up/down feels natural.
	var direction: String
	if abs(input_vector.y) >= abs(input_vector.x):
		direction = "n" if input_vector.y < 0 else "s"
	else:
		direction = "w" if input_vector.x < 0 else "e"

	last_direction = direction
	var anim_name: String = _movement_animation_name(direction)
	if sprite.animation != anim_name:
		sprite.play(anim_name)
	elif not sprite.is_playing():
		sprite.play()




func _survival_speed_multiplier() -> float:
	# Worst-of policy: hunger and thirst each impose a penalty independently;
	# we use the more punishing of the two rather than stacking multiplicatively.
	return min(HungerSystem.speed_multiplier(), ThirstSystem.speed_multiplier())

func is_exhausted() -> bool:
	return stamina <= 0.0

func _on_time_skipped(_from: int, _to: int, _context: Dictionary) -> void:
	# Stamina restore on sleep is handled by StaminaSystem itself.
	pass


func _on_hour_tick(hour: int, _dow: int, _dom: int) -> void:
	if hour == 6:
		_force_sleep()


func _force_sleep() -> void:
	if not TimeSystem.is_running():
		return  # already in a skip
	var safe := _is_in_safe_room()
	TimeSkipSystem.skip_to(_next_wake_minute(), {
		"kind": "sleep",
		"safe": safe,
		"voluntary": false,
	})


func _is_in_safe_room() -> bool:
	if RoomManager.current_room == null:
		return false
	return "apartment" in RoomManager.current_room.name.to_lower()


func _next_wake_minute() -> int:
	var current := TimeSystem.total_minutes
	var minutes_per_day := 24 * 60
	var days_passed := current / minutes_per_day
	return (days_passed + 1) * minutes_per_day

func _movement_animation_name(direction: String) -> String:
	if active_mode == &"skateboard":
		var skate_name := "skate_" + direction
		if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(skate_name):
			return skate_name
	return "walk_" + direction
	
# Snap the sprite to a known idle pose so we don't briefly show whatever
# animation was selected in the editor when the sceane was saved.
func _settle_idle() -> void:
	var anim_name: String = _movement_animation_name(last_direction)
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim_name):
		sprite.animation = anim_name
		sprite.frame = 0
		sprite.pause()

func _debug_replay_event(event_id: String) -> void:
	RelationshipSystem.mark_event_undone(event_id)
	EventDirector.force_fire(event_id)

	
#---- Save Systems ------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"position_x": global_position.x,
		"position_y": global_position.y,
		"current_room": RoomManager.current_room.scene_file_path if RoomManager.current_room else "",
		"last_direction": last_direction,
		"inventory": inventory.save_state(),
		"active_mode": String(active_mode),
		"active_mode_speed": active_mode_speed,
	}


func load_state(data: Dictionary) -> void:
	last_direction = data.get("last_direction", "s")
	if data.has("inventory"):
		inventory.load_state(data["inventory"])
	active_mode = StringName(data.get("active_mode", ""))
	active_mode_speed = data.get("active_mode_speed", 0.0)
	# Legacy save migration: older saves stored stamina under "player".
	# Forward to StaminaSystem so people don't lose state on the first load
	# after this refactor.
	if data.has("stamina") or data.has("stamina_max"):
		StaminaSystem.load_state({
			"current": data.get("stamina", StaminaSystem.MAX_VALUE),
			"max": data.get("stamina_max", StaminaSystem.MAX_VALUE),
		})
	_settle_idle()
	
#---- Inventory------------------------------------------------------
func _on_active_slot_changed(_slot: int) -> void:
	InteractionManager.notify_player_state_changed()

func _on_inventory_slot_changed(slot: int) -> void:
	if slot == inventory.active_slot:
		InteractionManager.notify_player_state_changed()
		
func is_holding(item_id: StringName) -> bool:
	var stack := inventory.get_active_stack()
	return stack != null and stack.item != null and stack.item.id == item_id

func is_holding_anything() -> bool:
	var stack := inventory.get_active_stack()
	return stack != null and stack.item != null

func is_holding_category(category: int) -> bool:
	var stack := inventory.get_active_stack()
	return stack != null and stack.item != null and stack.item.category == category

func _current_speed() -> float:
	if active_mode != &"":
		return active_mode_speed
	return speed * PlayerSkills.speed_multiplier()

# True if the player is currently standing over a tile in the room's
# "pavement" TileMapLayer. Used to gate the skateboard — it only works on
# pavement. If there's no pavement layer in the room, returns false (no
# pavement = nowhere to skate).
func _is_on_pavement() -> bool:
	if RoomManager.current_room == null:
		return false
	var layer = RoomManager.current_room.find_child("pavement", false, false)
	if layer == null or not (layer is TileMapLayer):
		return false
	var cell: Vector2i = layer.local_to_map(layer.to_local(global_position))
	return layer.get_cell_source_id(cell) != -1

# --- Vault ---

func _try_vault() -> void:
	if _is_vaulting:
		return
	if RoomManager.current_room == null:
		return
	var layer = RoomManager.current_room.find_child("Vaultables", false, false)
	if layer == null:
		return
	var dir_vec := _direction_vector(last_direction)
	var current_tile: Vector2i = layer.local_to_map(layer.to_local(global_position))
	
		# Vaultables are 1 tile thick in the traversal axis. Look at the player's
	# current tile and the tile immediately ahead — exactly one of them
	# should be a vault tile.
	var step0_tile: Vector2i = current_tile
	var step1_tile: Vector2i = current_tile + dir_vec
	var step0_data : TileData = layer.get_cell_tile_data(0, step0_tile)
	var step1_data : TileData = layer.get_cell_tile_data(0, step1_tile)
	
	var vault_step: int = -1
	if step0_data != null:
		vault_step = 0
	elif step1_data != null:
		vault_step = 1
	
	if vault_step < 0:
		return  # nothing to vault
	
	# Reject stacked vaultables (two in a row in the traversal direction).
	# Authoring rule: 1 tile thick. If broken, fail loudly.
	var beyond_tile: Vector2i = current_tile + dir_vec * (vault_step + 1)
	var beyond_data: TileData = layer.get_cell_tile_data(0, beyond_tile)
	if beyond_data != null:
		NotificationSystem.warn("Too thick to vault.")
		return
	
	var tier: int = (step0_data if vault_step == 0 else step1_data).get_custom_data("vault_tier")
	var capability: StringName = _capability_for_tier(tier)
	if capability == &"" or not PlayerSkills.has_capability(capability):
		NotificationSystem.warn("You can't get over that yet.")
		return
	
	# Land 1 tile past the vault tile. Always 1-2 tiles of motion total.
	_begin_vault(dir_vec, tier, vault_step + 1)


func _begin_vault(dir_vec: Vector2i, tier: int, landing_distance: int) -> void:
	_is_vaulting = true
	velocity = Vector2.ZERO
	
	# Straight-line displacement, with per-axis landing offset to compensate
	# for player origin sitting at feet rather than center.
	var raw_offset := Vector2(dir_vec) * (TILE_SIZE * landing_distance)
	if dir_vec.x != 0:
		raw_offset.x -= sign(dir_vec.x) * VAULT_LANDING_OFFSET_HORIZONTAL
	if dir_vec.y != 0:
		raw_offset.y -= sign(dir_vec.y) * VAULT_LANDING_OFFSET_VERTICAL
	var end_pos := global_position + raw_offset
	
	var collision := find_child("CollisionShape2D", false, false) as CollisionShape2D
	if collision != null:
		collision.disabled = true
	
	
	var duration: float = VAULT_DURATION_BY_TIER[clampi(tier, 0, VAULT_DURATION_BY_TIER.size() - 1)]
	var arc_height: float = VAULT_ARC_HEIGHT_BY_TIER[clampi(tier, 0, VAULT_ARC_HEIGHT_BY_TIER.size() - 1)]
	
	
	# Animation, scaled to match duration.
	var anim_name := "vault_" + last_direction
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim_name):
		var anim_fps: float = sprite.sprite_frames.get_animation_speed(anim_name)
		var anim_frames: int = sprite.sprite_frames.get_frame_count(anim_name)
		if anim_fps > 0.0 and anim_frames > 0:
			var anim_length: float = anim_frames / anim_fps
			sprite.speed_scale = anim_length / duration
		sprite.play(anim_name)
	
	# Position tween moves the body in a straight line.
	# Position and arc share one tween so they finish in lockstep. The
	# arc runs in parallel with the position step; the completion callback
	# is chained (not parallel) so it fires after both are done.
	var sprite_base_y: float = sprite.position.y
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_parallel(true)
	tween.tween_property(self, "global_position", end_pos, duration)
	tween.tween_method(
		_apply_vault_arc.bind(sprite_base_y, arc_height, dir_vec.y),
		0.0, 1.0, duration,
	)
	tween.chain().tween_callback(func() -> void:
		sprite.position.y = sprite_base_y
		_complete_vault(tier, collision)
	)

func _apply_vault_arc(t: float, base_y: float, arc_height: float, dir_y: int) -> void:
	var arc: float = sin(t * PI) * arc_height
	sprite.position.y = base_y - arc
	
	if dir_y < 0:
		z_index = 10 if t < 0.5 else -10
	elif dir_y > 0:
		z_index = -10 if t < 0.5 else 10


func _complete_vault(tier: int, collision: CollisionShape2D) -> void:
	if collision != null:
		collision.disabled = false
	_is_vaulting = false
	StaminaSystem.spend(VAULT_STAMINA_COST)
	if tier >= 0 and tier < VAULT_XP_BY_TIER.size():
		PlayerSkills.adjust(&"athletics", VAULT_XP_BY_TIER[tier])
	z_index = 0
	sprite.speed_scale = 1.0


func _direction_vector(dir: String) -> Vector2i:
	match dir:
		"n": return Vector2i(0, -1)
		"s": return Vector2i(0, 1)
		"e": return Vector2i(1, 0)
		"w": return Vector2i(-1, 0)
		_: return Vector2i(0, 1)


func _capability_for_tier(tier: int) -> StringName:
	match tier:
		0: return &"vault_low"
		1: return &"vault_medium"
		2: return &"vault_high"
		_: return &""

#----------------Tool Use---------------

# Routes the "interact" key when holding an item.
# Returns true if the key was consumed (don't fall through to world interaction).
#
# Resolution order:
#   1. Exit active mode if one is active (skateboard, etc.)
#   2. Tool activation (anything with a tool_id) -- dispatch by tool_id
#   3. Consumable (food, drink, hunger_restore or thirst_restore != 0)
#   4. Not handled -- fall through
func _try_tool_interact() -> bool:
	# 1. Mode exit
	if active_mode != &"":
		_exit_active_mode()
		return true

	var stack := inventory.get_active_stack()
	if stack == null or stack.item == null:
		return false
	var item: ItemDef = stack.item

	# 2. Tool activation
	if item.tool_id != &"":
		return _try_use_tool(item)

	# 3. Consumable. Either restore field being nonzero (positive OR negative)
	# qualifies the item -- chips give hunger but take thirst, that's fine.
	if item.hunger_restore != 0.0 or item.thirst_restore != 0.0 or item.stamina_restore != 0.0:
		_consume_active_food(item)
		return true
	# 4. Not a recognized use
	return false


# Dispatch by tool_id. Each arm explicitly decides whether to consume.
# Add new tool items here as you build them out.
func _try_use_tool(item: ItemDef) -> bool:
	match item.tool_id:
		&"skateboard":
			_try_enter_skateboard(item)
			return true
		&"pager":
			PagerSystem.activate()
			RelationshipSystem.set_global_flag("has_pager")
			inventory.consume_active(1)
			return true
		&"lottery_scratchers":
			LotterySystem.scratch()
			inventory.consume_active(1)
			return true
		&"box_dime_bags":
			inventory.add(ItemRegistry.get_item("empty_dime_bag"),99)
			inventory.consume_active(1)
			return true
		&"weed_oz":
			inventory.add(ItemRegistry.get_item("weed_buds"),28)
			inventory.consume_active(1)
			return true
		&"box_ziplock":
			inventory.add(ItemRegistry.get_item("large_ziplock"),30)
			inventory.consume_active(1)
			return true
		_:
			return false


# Consumable handler. Handles both positive restore (food, drink) and
# negative side-effects (chips: +hunger, -thirst). Negatives are routed
# through the same restore call with a negative value -- if your
# HungerSystem/ThirstSystem clamp negatives, swap these for explicit
# drain() calls instead.
func _consume_active_food(item: ItemDef) -> void:
	if item.hunger_restore != 0.0:
		HungerSystem.restore(item.hunger_restore)
	if item.thirst_restore != 0.0:
		ThirstSystem.restore(item.thirst_restore)
	if item.stamina_restore != 0.0:
		StaminaSystem.restore(item.stamina_restore)
	inventory.consume_active(1)

	# Phrasing reflects the dominant positive effect.
	var verb := "Used"
	if item.thirst_restore > item.hunger_restore and item.thirst_restore > item.stamina_restore:
		verb = "Drank"
	elif item.hunger_restore > 0.0 or item.thirst_restore > 0.0:
		verb = "Ate"
	NotificationSystem.warn("%s %s." % [verb, item.display_name])


func _try_enter_skateboard(item: ItemDef) -> void:
	if not _in_movement_tool_scene():
		NotificationSystem.warn("Not here.")
		return
	if item.movement_speed <= 0.0:
		push_warning("Skateboard item has no movement_speed set")
		return
	if not _is_on_pavement():
		NotificationSystem.warn("Need to be on pavement to ride.")
		return
	active_mode = &"skateboard"
	active_mode_speed = item.movement_speed


func _exit_active_mode() -> void:
	active_mode = &""
	active_mode_speed = 0.0


func _in_movement_tool_scene() -> bool:
	if RoomManager.current_room == null:
		return false
	return RoomManager.current_room.scene_file_path in MOVEMENT_TOOL_SCENES


# Auto-dismount when entering a scene where the active mode isn't allowed.
func _on_room_changed(_room_path: String) -> void:
	if active_mode != &"" and not _in_movement_tool_scene():
		_exit_active_mode()
