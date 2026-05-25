class_name CustomerArchetype
extends Resource

# A street-deal customer archetype. Defines visual identity and the range
# of purchase odds a spawned instance of this type might roll within.

@export var archetype_id: StringName = &""
@export var display_name: String = ""

# Sprite frames used when a customer of this archetype spawns. Pool of
# alternates allowed for visual variety within an archetype.
@export var sprite_frames_pool: Array[SpriteFrames] = []

# Inclusive purchase-chance range. Each spawn rolls a value in [min, max]
# at spawn time; that becomes the customer's is_willing roll target.
@export_range(0.0, 1.0, 0.05) var purchase_chance_min: float = 0.0
@export_range(0.0, 1.0, 0.05) var purchase_chance_max: float = 1.0


# Roll a willingness probability for a fresh spawn of this archetype.
func roll_purchase_chance(rng: RandomNumberGenerator) -> float:
	return rng.randf_range(purchase_chance_min, purchase_chance_max)
