class_name BottleSpawnPoint
extends Node2D

# A position where the ScavengeSpawner may place a loose ground bottle each
# day. Drop instances in outdoor scenes. Self-registers on _ready, removes
# itself on tree_exited so bottles don't try to spawn into unloaded scenes.
#
# Mirrors CarSpawnPoint, minus orientation (bottles have no facing).

@export var spawn_id: StringName = &""


func _ready() -> void:
	if spawn_id == &"":
		push_warning("BottleSpawnPoint at (%s) has no spawn_id" % global_position)
		return
	var scene_path: String = _resolve_scene_path()
	if scene_path == "":
		push_warning("BottleSpawnPoint '%s' couldn't determine scene path" % spawn_id)
		return
	ScavengeSpawner.register_bottle_point(spawn_id, scene_path, global_position)
	tree_exited.connect(_on_tree_exited)


func _on_tree_exited() -> void:
	ScavengeSpawner.unregister_bottle_point(spawn_id)


func _resolve_scene_path() -> String:
	if owner != null and owner.scene_file_path != "":
		return owner.scene_file_path
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene.scene_file_path
	return ""
