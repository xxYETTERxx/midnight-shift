extends Node

# Global set of live WitnessComponents. CrimeSystem queries this during
# its eval loop to find the first witness that sees the crime. Cops,
# pedestrians, defined NPCs — anything with a WitnessComponent child
# is in here.

var _witnesses: Dictionary = {}  # instance_id → WitnessComponent


func register(witness: WitnessComponent) -> void:
	if witness == null:
		return
	_witnesses[witness.get_instance_id()] = witness


func unregister(witness: WitnessComponent) -> void:
	if witness == null:
		return
	_witnesses.erase(witness.get_instance_id())


# Returns the first eligible WitnessComponent that can see the player and
# has a non-zero reaction weight for this crime type. First-match for now;
# we can sort by distance or weight later if it matters.
func find_witness(crime_type: StringName, player: Node2D, crime_id: int = 0, delta: float = 0.0) -> WitnessComponent:
	if player == null:
		return null
	var hit: WitnessComponent = null
	for w in _witnesses.values():
		if not is_instance_valid(w):
			continue
		var sees: bool = w.can_witness(player)
		if not sees:
			# LOS lost — reset any in-progress noticing on cops.
			var owner_node: Node = w.get_witness_owner()
			if owner_node is CopNPC and owner_node.has_method("clear_notice"):
				owner_node.clear_notice(crime_id)
			continue
		if hit != null:
			continue  # already found a hit, but keep iterating to clear LOS-loss on others
		if w.reaction_weight(crime_type, crime_id, delta) <= 0.0:
			continue
		hit = w
	return hit
