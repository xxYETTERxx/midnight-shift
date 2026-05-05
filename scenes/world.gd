extends Node2D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
var player: Node2D = null

func _ready() -> void:
	player = PLAYER_SCENE.instantiate()
	add_child(player)
	SaveSystem.register_savable("world", self)
	if SaveSystem.has_save():
		_load_game()
	else:
		_new_game()
		
func _new_game() -> void:
	RoomManager.register_world(self, player)
	
func _load_game() -> void:
	# Initialize RoomManager with our world reference but DON'T load the
	# default room — the savable load callback will tell us what room.
	RoomManager.register_world_only(self, player)
	# Trigger the load. SaveSystem will call our load_state() during this.
	SaveSystem.load_from_disk()
	
func save_state() -> Dictionary:
	var room_path := ""
	if RoomManager.current_room:
		room_path = RoomManager.current_room.scene_file_path
	return {
		"current_room": room_path,
		"player_x": player.global_position.x,
		"player_y": player.global_position.y,
	}
	
func load_state(data: Dictionary) -> void:
	var room_path: String = data.get("current_room", "")
	var pos := Vector2(data.get("player_x", 0.0), data.get("player_y", 0.0))
	if room_path != "":
		# Load the saved room, then position the player
		RoomManager.change_room(room_path, "default")
		player.global_position = pos
	else:
		_new_game()  # fallback
	print("[WorldStateSystem] load_state called with %d rooms" % data.get("room_states", {}).size())
	

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):  # Enter key
		TimeSystem.advance_to(TimeSystem.total_minutes + 60)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: _jump_to_hour(2)    # deep night
			KEY_2: _jump_to_hour(6)    # dawn
			KEY_3: _jump_to_hour(14)   # day
			KEY_4: _jump_to_hour(19)   # golden hour
			KEY_5: _jump_to_hour(22)   # late night
			KEY_MINUS: TimeSystem.advance_to(TimeSystem.total_minutes + 10)  # +10 min
			KEY_EQUAL: TimeSystem.advance_to(TimeSystem.total_minutes + 5)   # +5 min
			KEY_F:
				await ScreenFade.fade_out(1)
				await get_tree().create_timer(1.0).timeout  # wait 1 second while black
				await ScreenFade.fade_in(1)
			KEY_F9:
				SaveSystem.save_to_disk()
			KEY_F10:  # bonus: wipe save
				SaveSystem.delete_save()
			KEY_I:
	# Debug: grant 3 soil bags
				var soil := ItemRegistry.get_item(&"soil_bag")
				if soil:
					var leftover: int = player.inventory.add(soil, 3)
					print("[Inventory] added 3 soil_bag, leftover: %d" % leftover)
					print("[Inventory] slot 0: %s" % str(player.inventory.get_slot(0)))
			KEY_O:
	# Debug: print inventory state
				for i in range(player.inventory.max_slots):
					var stack: ItemStack = player.inventory.get_slot(i)
					if stack:
						print("Slot %d: %s x%d" % [i, stack.item.id, stack.count])
					else:
						print("Slot %d: empty" % i)
				print(ItemRegistry.get_item(&"pot_basic") is PlaceableItemDef)


func _jump_to_hour(target_hour: int) -> void:
	# Jump to the next occurrence of target_hour
	var current_minute_of_day := (TimeSystem.total_minutes + 14 * 60) % 1440
	var target_minute_of_day := target_hour * 60
	var minutes_to_advance: int
	if target_minute_of_day > current_minute_of_day:
		minutes_to_advance = target_minute_of_day - current_minute_of_day
	else:
		minutes_to_advance = (1440 - current_minute_of_day) + target_minute_of_day
	TimeSystem.advance_to(TimeSystem.total_minutes + minutes_to_advance)
		
