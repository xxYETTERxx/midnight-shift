extends Node2D

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
var player: Node2D = null
@onready var _debug_panel: CanvasLayer = $HUD/DebugPanel

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
	CarSpawner._materialize_cars_for_current_scene()
	RelationshipSystem.set_npc_flag("erik","no_money",true)
	RelationshipSystem.set_npc_flag("erik","deal_tut",true)
	
	
	
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
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: TimeSystem.advance_to(TimeSystem.total_minutes + 60)
			KEY_F2: _debug_panel.toggle()
			KEY_F3: SuspicionSystem._add(10.0)
			KEY_F4: 
				CriminalExperience.adjust(10)
				print("CriminalXP: " + str(CriminalExperience.current_tier()))
			KEY_F9:
				SaveSystem.save_to_disk()
			KEY_F11:  # bonus: wipe save
				SaveSystem.delete_save()
			
			KEY_X:
	# Debug: bump DEX by 10 (TIER_THRESHOLDS = [0, 25, 75, 150, 300])
				DealerExperience.adjust(10)
				print("[Debug] DEX=%d (tier %d)" %
					[DealerExperience.xp, DealerExperience.current_tier()])


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
