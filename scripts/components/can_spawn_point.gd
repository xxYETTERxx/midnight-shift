class_name CanSpawnPoint
extends Node2D

# A position where a garbage can lives. Unlike bottle points, a can ALWAYS
# exists at its point — the spawner places a LootableCan here every day. What
# varies daily is whether that can is *stocked* with bottles (a random subset
# of cans is stocked each morning); unstocked cans read as empty.
#
# Self-registers on _ready, removes itself on tree_exited.

@export var spawn_id: StringName = &""


func _ready() -> void:
	if spawn_id == &"":
		push_warning("CanSpawnPoint at (%s) has no spawn_id" % global_position)
		return
	var scene_path: String = _resolve_scene_path()
	if scene_path == "":
		push_warning("CanSpawnPoint '%s' couldn't determine scene path" % spawn_id)
		return
	ScavengeSpawner.register_can_point(spawn_id, scene_path, global_position)
	tree_exited.connect(_on_tree_exited)


func _on_tree_exited() -> void:
	ScavengeSpawner.unregister_can_point(spawn_id)


func _resolve_scene_path() -> String:
	if owner != null and owner.scene_file_path != "":
		return owner.scene_file_path
	var tree := get_tree()
	if tree != null and tree.current_scene != null:
		return tree.current_scene.scene_file_path
	return ""
