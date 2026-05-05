extends Node

# All interactables currently overlapping the player.
var _registered: Array = []

# The currently-winning interactable, recomputed when the set or any
# state changes. Null if no eligible interactable.
var _winner: Node = null

# Emitted when the winner changes. UI listens to this to update prompts.
signal winner_changed(winner: Node)


# An interactable calls this when the player enters its zone.
func register(interactable: Node) -> void:
	if _registered.has(interactable):
		return
	_registered.append(interactable)
	# Listen for state changes on this interactable so we re-arbitrate
	# when its eligibility might have shifted.
	if interactable.has_signal("state_changed"):
		interactable.state_changed.connect(_recompute_winner)
	_recompute_winner()


# An interactable calls this when the player exits its zone.
func unregister(interactable: Node) -> void:
	if not _registered.has(interactable):
		return
	_registered.erase(interactable)
	if interactable.has_signal("state_changed") and interactable.state_changed.is_connected(_recompute_winner):
		interactable.state_changed.disconnect(_recompute_winner)
	_recompute_winner()


# Player input changed (active inventory slot). Eligibility may have shifted.
func notify_player_state_changed() -> void:
	_recompute_winner()


# Called by the player when E is pressed.
# Returns true if an interaction fired.
func try_interact(player: Node) -> bool:
	if _winner == null:
		return false
	if not _winner.has_method("interact"):
		push_warning("Winner has no interact() method: %s" % _winner)
		return false
	_winner.interact(player)
	return true


# Backwards-compatible alias for code that reads "the active interactable."
# Prefer reading the winner_changed signal where possible.
var active: Node:
	get:
		return _winner


# --- Internals ---

func _recompute_winner() -> void:
	# Find the player to pass into can_interact().
	var player := _find_player()
	var best: Node = null
	var best_priority: int = -2_147_483_648  # min int
	var best_index: int = -1
	for i in range(_registered.size()):
		var it: Node = _registered[i]
		if not is_instance_valid(it):
			continue
		if not it.has_method("can_interact"):
			continue
		if not it.can_interact(player):
			continue
		var pri: int = it.interact_priority if "interact_priority" in it else 0
		if pri > best_priority or (pri == best_priority and i < best_index):
			best = it
			best_priority = pri
			best_index = i
	if best != _winner:
		_winner = best
		winner_changed.emit(_winner)


func _find_player() -> Node:
	# Convenience accessor; player is in the "player" group.
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.get_first_node_in_group("player")
