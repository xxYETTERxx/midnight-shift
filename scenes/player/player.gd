extends CharacterBody2D

@export var speed: float = 80.0

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

# --- Stamina ---
@export var stamina_max: float = 100.0
@export var passive_drain_per_minute: float = 0.07
@export var movement_drain_per_minute: float = 0.05

var stamina: float = 100.0

signal stamina_changed(current: float, maximum: float)

var last_direction: String = "s"

func _ready() -> void:
	TimeSkipSystem.time_skipped.connect(_on_time_skipped)
	TimeSystem.hour_tick.connect(_on_hour_tick)
	SaveSystem.register_savable("player", self)


func _physics_process(_delta: float) -> void:
	var input_vector := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_up", "move_down")
	)

	if input_vector.length() > 1.0:
		input_vector = input_vector.normalized()

	velocity = input_vector * speed
	move_and_slide()

	_update_animation(input_vector)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		InteractionManager.try_interact(self)

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
	}


func load_state(data: Dictionary) -> void:
	stamina = data.get("stamina", stamina_max)
	stamina_max = data.get("stamina_max", 100.0)
	last_direction = data.get("last_direction", "s")
	stamina_changed.emit(stamina, stamina_max)
	# Position and room are handled by World on load — see below.
	# We can't change rooms from here because RoomManager state is mid-flight.
