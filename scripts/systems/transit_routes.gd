class_name TransitRoutes
extends RefCounted

# Authored walking routes for transit NPCs — people passing through town
# with no business in the world. Each route is a chain of waypoint ids;
# the NPC spawns at [0], walks to [-1], despawns there. Routes are
# bidirectional in concept — author each direction explicitly if you
# want both ends to feed traffic, or rely on the spawner to randomly
# reverse a route (cheaper).
#
# All waypoint ids must resolve in the current room's scene. If they
# don't, the spawner skips that route quietly.

const ROUTES: Array = [
	# placeholder — replace with real entry-to-entry chains
	[&"E_S_Entry", &"N_SE_Corner", &"N_SW_Corner", &"NW_SE_Corner", &"SW_E_Entry"],
	[&"E_N_Entry", &"N_NE_Corner", &"N_NW_Corner", &"NW_NW_Corner", &"SW_W_Entry"],
	[&"E_S_Entry", &"N_SE_Corner", &"N_E_Entry"],
	[&"S_E_Entry",&"N_E_Entry"],
	[&"S_W_Entry",&"N_W_Entry"],
	[&"N_W_Entry",&"N_NW_Corner", &"NW_NW_Corner",&"SW_W_Entry"]
]


static func get_routes() -> Array:
	return ROUTES


static func pick_random_route(rng: RandomNumberGenerator) -> Array:
	if ROUTES.is_empty():
		return []
	return ROUTES[rng.randi() % ROUTES.size()]
