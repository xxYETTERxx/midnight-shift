class_name PendingPage
extends RefCounted

# A page waiting in the pager queue. Created when a customer rolls a successful
# page, consumed when the player returns the call from a payphone.

var customer_id: StringName = ""
var received_at_minute: int = 0
var quantity_requested: int = 0

# Waking-time minutes the player has left to return this call. Ticked down
# by PagerSystem during non-sleep minutes only. Hits 0 → page expires,
# DEX penalty fires, customer's flake counter increments.
var minutes_remaining: int = 0


func to_dict() -> Dictionary:
	return {
		"customer_id": String(customer_id),
		"received_at_minute": received_at_minute,
		"quantity_requested": quantity_requested,
		"minutes_remaining": minutes_remaining,
	}


static func from_dict(data: Dictionary) -> PendingPage:
	var p := PendingPage.new()
	p.customer_id = StringName(data.get("customer_id", ""))
	p.received_at_minute = data.get("received_at_minute", 0)
	p.quantity_requested = data.get("quantity_requested", 0)
	p.minutes_remaining = data.get("minutes_remaining", 6 * 60)
	return p


func get_customer() -> Customer:
	return CustomerRoster.get_customer(customer_id)
