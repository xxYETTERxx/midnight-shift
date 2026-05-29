extends Node

const RECIPES_FOLDER: String = "res://data/recipes/weed/"

# id (StringName) → Recipe
var _recipes: Dictionary = {}


func _ready() -> void:
	_load_all_recipes(RECIPES_FOLDER)
	print("[RecipeRegistry] loaded %d recipes" % _recipes.size())


func get_recipe(id: StringName) -> Recipe:
	if not _recipes.has(id):
		push_warning("RecipeRegistry: unknown recipe id '%s'" % id)
		return null
	return _recipes[id]


func has_recipe(id: StringName) -> bool:
	return _recipes.has(id)


func all_recipes() -> Array:
	return _recipes.values()


# Returns every recipe a player at the given station could potentially see —
# matched by station tag, gated by unlock_flag. Does NOT filter by inputs or
# tools; the panel shows uncraftable recipes greyed out so the player learns
# what's possible.
func recipes_for_station(station_tag: StringName) -> Array:
	var out: Array = []
	print("[RecipeRegistry] looking for station_tag=", station_tag, " among ", _recipes.size(), " recipes")
	for r in _recipes.values():
		print("  recipe '", r.id, "' station_tags=", r.station_tags, " unlock_flag='", r.unlock_flag, "'")
		if not r.station_tags.is_empty() and not station_tag in r.station_tags:
			print("    filtered: station tag mismatch")
			continue
		if r.unlock_flag != "" and not RelationshipSystem.get_global_flag(r.unlock_flag):
			print("    filtered: unlock_flag not set")
			continue
		out.append(r)
	print("  → returned ", out.size(), " recipes")
	return out


# --- Internals ---

func _load_all_recipes(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		push_error("RecipeRegistry: failed to open %s" % path)
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if dir.current_is_dir() and not name.begins_with("."):
			_load_all_recipes(path + name + "/")
		elif name.ends_with(".tres"):
			_load_recipe(path + name)
		name = dir.get_next()
	dir.list_dir_end()


func _load_recipe(path: String) -> void:
	var resource := load(path)
	if not resource is Recipe:
		return
	var r: Recipe = resource
	if r.id == &"":
		push_warning("RecipeRegistry: recipe at %s has empty id, skipping" % path)
		return
	if _recipes.has(r.id):
		push_warning("RecipeRegistry: duplicate id '%s' (path: %s)" % [r.id, path])
	_recipes[r.id] = r
