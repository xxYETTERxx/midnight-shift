extends Node

# The currently active interactable, or null if none.
# An interactable is "active" when the player is in range of it.
var active: Node = null

# Emitted when the active interactable changes (or clears).
# UI listens to this to show/hide the prompt label.
signal active_changed(interactable: Node)


# An interactable calls this when the player enters its trigger zone.
func set_active(interactable: Node) -> void:
	if active == interactable:
		return
	active = interactable
	active_changed.emit(active)


# An interactable calls this when the player leaves its trigger zone.
# Only clears if the passed node matches — prevents zone B's exit
# from clearing zone A when the player crosses overlapping zones.
func clear_active(interactable: Node) -> void:
	if active != interactable:
		return
	active = null
	active_changed.emit(active)


# Called by the player when E is pressed.
# Returns true if an interaction fired.
func try_interact(player: Node) -> bool:
	if active == null:
		return false
	if not active.has_method("interact"):
		push_warning("Active interactable has no interact() method: %s" % active)
		return false
	active.interact(player)
	return true
