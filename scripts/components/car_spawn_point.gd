class_name CarSpawnPoint
extends Node2D

# A position where the spawner can place a car each day. Drop instances in
# outdoor scenes. Self-registers with CarSpawner on _ready, deregisters on
# tree_exited so cars don't try to spawn into unloaded scenes.

enum Orientation { NORTH, SOUTH, EAST, WEST }

@export var spawn_id: StringName = ""
@export_enum("North", "South", "East", "West") var orientation: int = Orientation.WEST



func _ready() -> void:
	if spawn_id == &"":
		push_warning("CarSpawnPoint at (%s) has no spawn_id" % global_position)
		return
	var scene_path: String = ""
	# Prefer the owning scene (the room this point was authored in).
	if owner != null and owner.scene_file_path != "":
		scene_path = owner.scene_file_path
	# Fall back to current_scene only if owner is unhelpful.
	if scene_path == "":
		var tree := get_tree()
		if tree != null and tree.current_scene != null:
			scene_path = tree.current_scene.scene_file_path
	if scene_path == "":
		push_warning("CarSpawnPoint '%s' couldn't determine scene path" % spawn_id)
		return
	CarSpawner.register_spawn_point(spawn_id, scene_path, global_position, orientation)
	tree_exited.connect(_on_tree_exited)


func _on_tree_exited() -> void:
	CarSpawner.unregister_spawn_point(spawn_id)
