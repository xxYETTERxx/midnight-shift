class_name MeetSpot
extends Waypoint   # was Node2D

@export var display_name: String = "Meet Spot"
# spot_id and waypoint_id are the same thing now — inherit waypoint_id
# from the parent class.

func _ready() -> void:
	if waypoint_id == &"":
		push_warning("MeetSpot: waypoint_id is empty, skipping registration")
		return
	var scene_path := ""
	if owner != null and owner.scene_file_path != "":
		scene_path = owner.scene_file_path
	MeetingManager.register_spot(waypoint_id, display_name, scene_path, global_position)
	_register_route_distances()


# Walk every authored route for this spot and hand the measured lengths to
# MeetingManager. Done here (in-scene) because the player isn't necessarily
# in this room when schedule_meeting() runs — the waypoints we need to
# measure only resolve from this scene.
func _register_route_distances() -> void:
	var routes: Array = CustomerRoutes.get_routes(waypoint_id)
	if routes.is_empty():
		return
	var distances: Array[float] = []
	for route_ids in routes:
		distances.append(_measure_route(route_ids))
	MeetingManager.register_route_distances(waypoint_id, distances)


func _measure_route(waypoint_ids: Array) -> float:
	if waypoint_ids.size() < 2:
		return 0.0
	var positions: Array[Vector2] = []
	for wp_id in waypoint_ids:
		var pos = _find_waypoint(wp_id)
		if pos == null:
			push_warning("MeetSpot '%s': route waypoint '%s' not in scene" %
				[waypoint_id, wp_id])
			return 0.0
		positions.append(pos)
	var total: float = 0.0
	for i in range(1, positions.size()):
		total += positions[i - 1].distance_to(positions[i])
	return total


func _find_waypoint(target_id: StringName):
	var root: Node = owner if owner != null else get_tree().current_scene
	if root == null:
		return null
	# Check the conventional Waypoints container first.
	var container: Node = root.get_node_or_null("Waypoints")
	if container != null:
		for child in container.get_children():
			if child is Waypoint and child.waypoint_id == target_id:
				return child.global_position
	# Fall back to a full subtree walk — handles MeetSpots living outside
	# the Waypoints container (they're waypoints themselves).
	return _find_in_subtree(root, target_id)


func _find_in_subtree(node: Node, target_id: StringName):
	if node is Waypoint and node.waypoint_id == target_id:
		return node.global_position
	for child in node.get_children():
		var hit = _find_in_subtree(child, target_id)
		if hit != null:
			return hit
	return null
