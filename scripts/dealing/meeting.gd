class_name Meeting
extends RefCounted

enum Status { SCHEDULED, COMPLETED, MISSED }

var id: StringName = ""
var customer_id: StringName = ""
var spot_id: StringName = ""

# Absolute total_minutes when the customer arrives at the spot.
var scheduled_minute: int = 0
# Minutes the customer waits at the spot before giving up.
var window_minutes: int = 60
var quantity_requested: int = 0
var spawn_minute: int = 0
var route_waypoints: Array = []
var status: int = Status.SCHEDULED


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"customer_id": String(customer_id),
		"spot_id": String(spot_id),
		"scheduled_minute": scheduled_minute,
		"window_minutes": window_minutes,
		"quantity_requested": quantity_requested,
		"status": status,
		"spawn_minute": spawn_minute,
		"route_waypoints": _route_to_strings(),
	}
func _route_to_strings() -> Array:
	var out: Array = []
	for wp in route_waypoints:
		out.append(String(wp))
	return out

static func from_dict(data: Dictionary) -> Meeting:
	var m := Meeting.new()
	m.id = StringName(data.get("id", ""))
	m.customer_id = StringName(data.get("customer_id", ""))
	m.spot_id = StringName(data.get("spot_id", ""))
	m.scheduled_minute = data.get("scheduled_minute", 0)
	m.window_minutes = data.get("window_minutes", 60)
	m.quantity_requested = data.get("quantity_requested", 0)
	m.status = data.get("status", Status.SCHEDULED)
	m.spawn_minute = data.get("spawn_minute", m.scheduled_minute)
	var wp_strings: Array = data.get("route_waypoints", [])
	m.route_waypoints = []
	for s in wp_strings:
		m.route_waypoints.append(StringName(s))
	return m


func get_customer() -> Customer:
	return CustomerRoster.get_customer(customer_id)


func is_active_at(minute: int) -> bool:
	return status == Status.SCHEDULED \
		and minute >= scheduled_minute \
		and minute < scheduled_minute + window_minutes
		
func is_visible_at(minute: int) -> bool:
	return status == Status.SCHEDULED \
		and minute >= spawn_minute \
		and minute < scheduled_minute + window_minutes
		
