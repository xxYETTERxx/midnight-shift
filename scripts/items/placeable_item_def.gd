class_name PlaceableItemDef
extends ItemDef


enum Surface {
	FLOOR,    # pots, furniture, stash boxes — placed on tiles the player walks on
	CEILING,  # lamps, hanging fixtures — placed on the layer above
}

# Scene to instantiate when this item is placed in the world.
# The scene's root must extend Placeable (or implement its contract).
@export var placeable_scene: PackedScene

@export var placement_surface: Surface = Surface.FLOOR

# Size in tiles. (1, 1) is a single 32×32 footprint. Lamps will be (2, 1)
# / (2, 2) / (2, 4). Used by surface validation (sub-chunk 5) — for now,
# placement just snaps to a single tile and ignores this.
@export var footprint_tiles: Vector2i = Vector2i(1, 1)
