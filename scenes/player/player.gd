extends CharacterBody2D

@export var speed: float = 80.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var inventory: Inventory = $Inventory

# --- Stamina ---
@export var stamina_max: float = 100.0
@export var passive_drain_per_minute: float = 0.07
@export var movement_drain_per_minute: float = 0.05

# --- Vault ---
const VAULT_DURATION_BY_TIER: Array[float] = [0.6, 0.8, 1.3]
const VAULT_ARC_HEIGHT_BY_TIER: Array[float] = [15.0, 18.0, 32.0]
const TILE_SIZE: int = 32
const VAULT_STAMINA_COST: float = 2.0
const VAULT_XP_BY_TIER: Array[int] = [5, 10, 20]
const VAULT_LANDING_OFFSET_HORIZONTAL: float = 10.0
const VAULT_LANDING_OFFSET_VERTICAL: float = 0.0

var _is_vaulting: bool = false

var stamina: float = 100.0

signal stamina_changed(current: float, maximum: float)

var last_direction: String = "s"

func _ready() -> void:
	TimeSystem.minute_tick.connect(_on_minute_tick)
	TimeSystem.hour_tick.connect(_on_hour_tick)
	TimeSkipSystem.time_skipped.connect(_on_time_skipped)
	stamina_changed.emit(stamina, stamina_max)
	SaveSystem.register_savable("player", self)
	# NEW: re-arbitrate interactions when the player's held item changes
	inventory.active_slot_changed.connect(_on_active_slot_changed)
	inventory.slot_changed.connect(_on_inventory_slot_changed)
	inventory.add(ItemRegistry.get_item(&"weed_seed"), 4)
	inventory.add(ItemRegistry.get_item(&"watering_can"), 1)
	inventory.add(ItemRegistry.get_item(&"slim_jim"), 1)
	inventory.add_with_data(ItemRegistry.get_item(&"calling_card_30"), 1, {"minutes": 20})


func _physics_process(delta: float) -> void:
	if not TimeSystem.is_running():
		return
	if _is_vaulting:
		return
	
	var input_vector := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)

	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()

	velocity = input_vector * speed * PlayerSkills.speed_multiplier()
	move_and_slide()

	# Athletics XP from distance actually moved (post-collision velocity).
	var dist := velocity.length() * delta
	if dist > 0.0:
		PlayerSkills.adjust_f(&"athletics", dist * PlayerSkills.ATHLETICS_XP_PER_PIXEL)
		var load: int = inventory.filled_slot_count()
		if load > 0:
			PlayerSkills.adjust_f(&"strength", dist * load * PlayerSkills.STRENGTH_XP_PER_PIXEL_PER_SLOT)

	_update_animation(input_vector)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12:
			RelationshipSystem.push_dialogue("mira", "bodega_intro")
			print("[debug] queued bodega_intro for mira")
		elif event.keycode == KEY_F2:
			RelationshipSystem.set_global_flag("greeting", true)
			RelationshipSystem.set_trust("mira", 0)
			print("[debug] set greeting flag + trust=0")
		elif event.keycode == KEY_F3:
			RelationshipSystem.set_global_flag("greeting", false)
			print("[debug] cleared greeting flag")
		elif event.keycode == KEY_F4:
			PlayerSkills.adjust(&"athletics", 200)
			print("[debug] +200 athletics XP -> ", PlayerSkills.value(&"athletics"),
				" (L", PlayerSkills.tier(&"athletics"), ")")
		elif event.keycode == KEY_F5:
			PlayerSkills.adjust(&"athletics", -PlayerSkills.value(&"athletics"))
			print("[debug] reset athletics")
		elif event.keycode == KEY_F6:
			PlayerSkills.adjust(&"strength", 200)
			print("[debug] +200 strength XP -> ", PlayerSkills.value(&"strength"),
				" (L", PlayerSkills.tier(&"strength"), ", slots=",
				PlayerSkills.inventory_slot_count(), ")")
		elif event.keycode == KEY_F7:
			PlayerSkills.adjust(&"lockpicking", 50)
			print("[debug] +50 lockpicking XP -> ", PlayerSkills.value(&"lockpicking"),
				" (L", PlayerSkills.tier(&"lockpicking"),
				", mult=%.2f)" % PlayerSkills.lockpick_duration_multiplier())
		elif event.keycode == KEY_F1:
			CallingCardSystem.try_spend(1)
			print("[debug] burned 1 minute -> total=", CallingCardSystem.total_minutes(),
				", cards=", CallingCardSystem.card_count())
	
	if event.is_action_pressed("interact"):
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
	var anim_name := "walk_" + direction
	if sprite.animation != anim_name:
		sprite.play(anim_name)
	elif not sprite.is_playing():
		sprite.play()

func _on_minute_tick(_total: int) -> void:
	var drain := passive_drain_per_minute
	if velocity.length() > 0.1:
		drain += movement_drain_per_minute
	spend_stamina(drain)


func spend_stamina(amount: float) -> void:
	stamina = clampf(stamina - amount, 0.0, stamina_max)
	stamina_changed.emit(stamina, stamina_max)


func restore_stamina(amount: float) -> void:
	stamina = clampf(stamina + amount, 0.0, stamina_max)
	stamina_changed.emit(stamina, stamina_max)


func is_exhausted() -> bool:
	return stamina <= 0.0

func _on_time_skipped(_from: int, _to: int, context: Dictionary) -> void:
	# Stamina restore on sleep
	if context.get("kind") == "sleep":
		var safe: bool = context.get("safe", true)
		if safe:
			restore_stamina(stamina_max)
		else:
			restore_stamina(stamina_max * 0.5)


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

#---- Save Systems ------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"position_x": global_position.x,
		"position_y": global_position.y,
		"current_room": RoomManager.current_room.scene_file_path if RoomManager.current_room else "",
		"stamina": stamina,
		"stamina_max": stamina_max,
		"last_direction": last_direction,
		"inventory": inventory.save_state(),  # NEW
	}


func load_state(data: Dictionary) -> void:
	stamina = data.get("stamina", stamina_max)
	stamina_max = data.get("stamina_max", 100.0)
	last_direction = data.get("last_direction", "s")
	if data.has("inventory"):
		inventory.load_state(data["inventory"])
	stamina_changed.emit(stamina, stamina_max)
	
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
	
	var sort_offset: float = arc_height
	
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
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_SINE)
	tween.tween_property(self, "global_position", end_pos, duration)
	tween.tween_callback(_complete_vault.bind(tier, collision))
	
	# Sprite Y-offset tween for the arc. Runs in parallel via a second tween
	# so it's independent of the position tween's ease curve.
	var arc_tween := create_tween()
	arc_tween.set_parallel(false)
	var sprite_base_y: float = sprite.position.y
	arc_tween.tween_method(_apply_vault_arc.bind(sprite_base_y, arc_height), 0.0, 1.0, duration)
	arc_tween.tween_callback(func(): sprite.position.y = sprite_base_y)

func _apply_vault_arc(t: float, base_y: float, arc_height: float) -> void:
	var arc: float = sin(t * PI) * arc_height
	sprite.position.y = base_y - arc


func _complete_vault(tier: int, collision: CollisionShape2D) -> void:
	if collision != null:
		collision.disabled = false
	_is_vaulting = false
	spend_stamina(VAULT_STAMINA_COST)
	if tier >= 0 and tier < VAULT_XP_BY_TIER.size():
		PlayerSkills.adjust(&"athletics", VAULT_XP_BY_TIER[tier])


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
