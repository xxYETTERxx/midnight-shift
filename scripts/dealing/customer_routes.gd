class_name CustomerRoutes
extends RefCounted

# Const customer arrival routes keyed by spot_id. Each route is a chain of
# waypoint ids the customer walks to reach the spot, ending at a waypoint
# adjacent to the MeetSpot itself. Customer stops at the last waypoint;
# existing handoff interaction takes over from there.
#
# Adding a new route: append to the array for its spot.
# Adding a new spot: new top-level key.
#
# Spot keys must match the spot_id you set on the MeetSpot node in the
# scene. Adjust the placeholder keys/waypoints below to match your map.

const ROUTES: Dictionary = {
	&"meet_spot_1": [
		[&"N_E_Entry", &"N_SE_Corner", &"meet_spot_1_corner", &"meet_spot_1"],
		[&"E_S_Entry", &"meet_spot_1_corner", &"meet_spot_1"],
	],
	&"meet_spot_2": [
		[&"SW_W_Entry", &"meet_spot_2_corner", &"meet_spot_2_corner2", &"meet_spot_2"],
		[&"N_W_Entry", &"N_NW_Corner", &"NW_NW_Corner", &"meet_spot_2_corner", &"meet_spot_2_corner2", &"meet_spot_2"],
	],
	&"meet_spot_3": [
		[&"N_W_Entry", &"N_NW_Corner", &"meet_spot_3_corner", &"meet_spot_3"],
		[&"SW_W_Entry", &"NW_NW_Corner", &"meet_spot_3_corner", &"meet_spot_3"],
	],
}


static func get_routes(spot_id: StringName) -> Array:
	return ROUTES.get(spot_id, [])


static func pick_random_route(spot_id: StringName, rng: RandomNumberGenerator) -> Array:
	var routes: Array = get_routes(spot_id)
	if routes.is_empty():
		return []
	return routes[rng.randi() % routes.size()]
