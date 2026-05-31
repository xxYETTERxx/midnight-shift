class_name Customer
extends RefCounted


# Stable id — assigned at generation, used as the dict key in CustomerRoster
# and as the foreign key from pages, meetings, dialogue history, etc.
var id: StringName = ""

# Display name — random first + last initial. 90s deal-buyer convention is
# to give an initial rather than a last name; that's a tone choice.
var display_name: String = ""

# Tier gates this customer's availability. They only page when the player's
# DealerExperience.current_tier() >= this value. Tiers don't claw back —
# losing tier just means they stop paging until you climb back.
var tier: int = 0

# Per-order quantity range. Random within this band each page.
var quantity_min: int = 1
var quantity_max: int = 3

# Quality expectation for future strain system. 0 = anything, higher = pickier.
var quality_preference: int = 0

# Randomized appearance, assigned at creation via NPCGenerator and frozen
# for the customer's lifetime. -1 means "not assigned" (legacy save data
# or a creation path that bypassed the generator) — CharacterSprite will
# leave its default texture in place.
var head_index: int = -1
var body_index: int = -1

# A single stock dialogue line, assigned at creation. Future: split into
# four lines (one per relationship tier) and pick at runtime by trust.
var default_dialogue: String = ""

# Deprecated, kept on the dict for save compat. Was a placeholder sprite
# tag before the head/body system existed; nothing reads it now.
var sprite_id: String = ""

# Which stock-dialogue bank this buyer pulls from (placeholder).
var dialogue_bank: String = "default"

# Per-customer relationship axes — minimal mirror of the NPC system (per §7).
var affinity: int = 0
var trust: int = 0

# Tracking for buyer-progression and blacklisting decisions.
var times_dealt: int = 0
var times_flaked: int = 0
var blacklisted: bool = false



var has_referred: bool = false


func to_dict() -> Dictionary:
	return {
		"id": String(id),
		"display_name": display_name,
		"tier": tier,
		"quantity_min": quantity_min,
		"quantity_max": quantity_max,
		"quality_preference": quality_preference,
		"head_index": head_index,
		"body_index": body_index,
		"default_dialogue": default_dialogue,
		"sprite_id": sprite_id,
		"dialogue_bank": dialogue_bank,
		"affinity": affinity,
		"trust": trust,
		"times_dealt": times_dealt,
		"times_flaked": times_flaked,
		"blacklisted": blacklisted,
		"has_referred": has_referred,

	}


static func from_dict(data: Dictionary) -> Customer:
	var c := Customer.new()
	c.id = StringName(data.get("id", ""))
	c.display_name = data.get("display_name", "")
	c.tier = data.get("tier", 0)
	c.quantity_min = data.get("quantity_min", 1)
	c.quantity_max = data.get("quantity_max", 3)
	c.quality_preference = data.get("quality_preference", 0)
	c.head_index = data.get("head_index", -1)
	c.body_index = data.get("body_index", -1)
	c.default_dialogue = data.get("default_dialogue", "")
	c.sprite_id = data.get("sprite_id", "")
	c.dialogue_bank = data.get("dialogue_bank", "default")
	c.affinity = data.get("affinity", 0)
	c.trust = data.get("trust", 0)
	c.times_dealt = data.get("times_dealt", 0)
	c.times_flaked = data.get("times_flaked", 0)
	c.blacklisted = data.get("blacklisted", false)
	c.has_referred = data.get("has_referred", false)
	return c
	
	
