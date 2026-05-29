# vendor_state_store.gd — autoload
extends Node

# vendor_id (String) -> saved vendor state dict
var _states: Dictionary = {}

func _ready() -> void:
	SaveSystem.register_savable("vendor_states", self)
	TimeSystem.day_rolled.connect(func(_d, _m): clear_all())

# Vendors call this on _exit_tree (and on confirm, if you want live persistence)
# to stash their current state centrally.
func store(vendor_id: StringName, state: Dictionary) -> void:
	if vendor_id == &"":
		return
	_states[String(vendor_id)] = state

# Vendors call this on _ready to rehydrate if we have same-day state for them.
func fetch(vendor_id: StringName) -> Dictionary:
	return _states.get(String(vendor_id), {})

func has_state(vendor_id: StringName) -> bool:
	return _states.has(String(vendor_id))

# Clear on day roll so vendors fall back to initial_stock the next morning.
func clear_all() -> void:
	_states.clear()

func save_state() -> Dictionary:
	return {"states": _states.duplicate(true)}

func load_state(data: Dictionary) -> void:
	_states = data.get("states", {}).duplicate(true)
