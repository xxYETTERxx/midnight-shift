class_name PatrolRoutes
extends RefCounted

# Const patrol routes keyed by area_id (scene basename). Each route is a
# StringName chain of waypoint ids the cop walks in order, despawning at
# the end. First and last waypoints should be map-edge "Entry" markers so
# cops spawn and despawn off-screen.
#
# These are placeholder routes — edit the chains to match actual map
# geometry. Naming convention assumed from the Waypoints container:
#   <quadrant>_<side>_Entry  → spawn/despawn points at map edges
#   <quadrant>_<corner>_Corner → interior path nodes
#
# Adding a new route: append to the array for its area.
# Adding a new area: new top-level key.

const ROUTES: Dictionary = {
	&"ext_central": [
		# North perimeter sweep, west → east
		[&"N_W_Entry", &"N_NW_Corner", &"N_NE_Corner", &"N_E_Entry"],
		# North perimeter sweep, east → west (reverse)
		[&"N_E_Entry", &"N_NE_Corner", &"N_NW_Corner", &"N_W_Entry"],
		# North quadrant loop-cut, west entry to south exit
		[&"N_W_Entry", &"N_NW_Corner", &"N_SW_Corner", &"N_SE_Corner", &"N_E_Entry"],
		# East side, north to south
		[&"E_N_Entry", &"N_NE_Corner", &"N_SE_Corner", &"E_S_Entry"],
		# South perimeter, west to east
		[&"S_W_Entry", &"SW_W_Entry", &"SW_E_Entry", &"S_E_Entry"],
		# Full Walk East -> West
		[&"E_S_Entry", &"N_SW_Corner", &"NW_SE_Corner",&"SW_E_Entry"],
		# Full Walk WEST -> EAST
		[&"S_E_Entry", &"NW_SE_Corner", &"N_NE_Corner",&"E_N_Entry"],
	],
}


static func get_routes(area_id: StringName) -> Array:
	return ROUTES.get(area_id, [])


static func pick_random_route(area_id: StringName, rng: RandomNumberGenerator) -> Array:
	var routes: Array = get_routes(area_id)
	if routes.is_empty():
		return []
	return routes[rng.randi() % routes.size()]
