extends Node

const ITEMS_FOLDER: String = "res://data/items/"

# id (StringName) → ItemDef
var _items: Dictionary = {}


func _ready() -> void:
	_load_all_items(ITEMS_FOLDER)
	print("[ItemRegistry] loaded %d items" % _items.size())


func get_item(id: StringName) -> ItemDef:
	if not _items.has(id):
		push_warning("ItemRegistry: unknown item id '%s'" % id)
		return null
	return _items[id]


func has_item(id: StringName) -> bool:
	return _items.has(id)


func all_items() -> Array:
	return _items.values()


# Recursively scans the items folder and loads every .tres file as an ItemDef.
func _load_all_items(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("ItemRegistry: failed to open %s" % path)
		return

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and not name.begins_with("."):
			_load_all_items(path + name + "/")
		elif name.ends_with(".tres"):
			_load_item(path + name)
		name = dir.get_next()
	dir.list_dir_end()


func _load_item(path: String) -> void:
	var resource := load(path)
	if not resource is ItemDef:
		# .tres files in this folder that aren't ItemDefs — skip silently
		return
	var item: ItemDef = resource
	if item.id == &"":
		push_warning("ItemRegistry: item at %s has empty id, skipping" % path)
		return
	if _items.has(item.id):
		push_warning("ItemRegistry: duplicate id '%s' (path: %s)" % [item.id, path])
	_items[item.id] = item
