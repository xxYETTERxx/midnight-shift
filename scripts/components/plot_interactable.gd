class_name PlotInteractable
extends Interactable

# Set in the pot scene to point at the Pot root.
@export var pot: NodePath


func can_interact(player: Node) -> bool:
	var pot_node := get_node_or_null(pot)
	if pot_node == null:
		return false
	if not pot_node.has_method("would_accept"):
		return true
	var result: bool = pot_node.would_accept(player)
	return result
