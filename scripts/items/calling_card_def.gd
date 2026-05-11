class_name CallingCardDef
extends ItemDef

# Minutes a fresh card of this SKU has when first created.
@export var initial_minutes: int = 30


func initial_stack_data() -> Dictionary:
	return {"minutes": initial_minutes}
