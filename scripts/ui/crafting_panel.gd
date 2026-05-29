extends CanvasLayer

# Mirrors VendorPanel's lifecycle: scene-placed singleton in the "crafting_panel"
# group, stations call open_with_station() on it.

@onready var _title_label: Label = $Panel/VBox/Title
@onready var _recipe_list: VBoxContainer = $Panel/VBox/Scroll/RecipeList
@onready var _close_button: Button = $Panel/VBox/CloseButton

var _player: Node = null
var _station: Node = null
var _inventory: Inventory = null


func _ready() -> void:
	add_to_group("crafting_panel")
	visible = false
	_close_button.pressed.connect(close)


func open_with_station(station: Node, player: Node) -> void:
	_station = station
	_player = player
	_inventory = player.get("inventory")
	if _inventory == null:
		push_warning("CraftingPanel: player has no inventory")
		return
	_title_label.text = station.get("display_name") if "display_name" in station else "Crafting"
	_rebuild_list()

	visible = true


func close() -> void:
	visible = false
	_player = null
	_station = null
	_inventory = null


# --- List rendering ---

func _rebuild_list() -> void:
	for child in _recipe_list.get_children():
		_recipe_list.remove_child(child)
		child.queue_free()

	var tag: StringName = _station.station_tag if "station_tag" in _station else &""
	var recipes: Array = RecipeRegistry.recipes_for_station(tag)

	if recipes.is_empty():
		var lbl := Label.new()
		lbl.text = "Nothing to craft here yet."
		_recipe_list.add_child(lbl)
		return

	for r in recipes:
		_recipe_list.add_child(_build_recipe_row(r))


func _build_recipe_row(r: Recipe) -> Control:
	var row := PanelContainer.new()
	var v := VBoxContainer.new()
	row.add_child(v)

	# --- Header: name + quantity + craft button ---
	var header := HBoxContainer.new()
	v.add_child(header)

	var title := Label.new()
	title.text = _recipe_display_name(r)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var qty := SpinBox.new()
	qty.min_value = 1
	qty.max_value = r.max_batch
	qty.value = 1
	qty.step = 1
	header.add_child(qty)

	var craft_btn := Button.new()
	craft_btn.text = "Craft"
	header.add_child(craft_btn)

	# --- Output line ---
	var output_lbl := Label.new()
	v.add_child(output_lbl)

	# --- Inputs (one label per input, updated on qty change) ---
	var input_labels: Array = []
	for inp in r.inputs:
		var line := Label.new()
		v.add_child(line)
		input_labels.append(line)

	# --- Tools ---
	for tool in r.required_tools:
		var line := Label.new()
		if _inventory.has_item(tool.id):
			line.text = "  ✓ %s" % tool.display_name
		else:
			line.text = "  ✗ needs %s" % tool.display_name
			line.modulate = Color(1, 0.4, 0.4)
		v.add_child(line)

	# --- Cost preview ---
	var cost_lbl := Label.new()
	v.add_child(cost_lbl)

	# Closure that refreshes everything that depends on quantity.
	var refresh := func():
		var q: int = int(qty.value)
		output_lbl.text = "→ %s ×%d" % [r.output_item.display_name, r.output_count * q]

		var missing: Array = []
		for i in range(r.inputs.size()):
			var inp: RecipeInput = r.inputs[i]
			var need: int = inp.count * q
			var have: int = _count_in_inventory(inp.item.id)
			input_labels[i].text = "  %s: %d / %d" % [inp.item.display_name, have, need]
			if have < need:
				input_labels[i].modulate = Color(1, 0.4, 0.4)
				missing.append("%d more %s" % [need - have, inp.item.display_name])
			else:
				input_labels[i].modulate = Color.WHITE

		for tool in r.required_tools:
			if not _inventory.has_item(tool.id):
				missing.append(tool.display_name)

		var cost: Vector2 = _compute_cost(r, q)
		var stamina_have: float = StaminaSystem.current_value()
		cost_lbl.text = "Time: %s  Stamina: %d / %d" % [
			_format_time(cost.x), int(cost.y), int(stamina_have)
		]
		if stamina_have < cost.y:
			cost_lbl.modulate = Color(1, 0.4, 0.4)
			missing.append("more stamina")
		else:
			cost_lbl.modulate = Color.WHITE

		craft_btn.disabled = not missing.is_empty()
		if not missing.is_empty():
			craft_btn.tooltip_text = "Need: " + ", ".join(missing)
		else:
			craft_btn.tooltip_text = ""

	qty.value_changed.connect(func(_v): refresh.call())
	craft_btn.pressed.connect(_on_craft_pressed.bind(r, qty))
	refresh.call()
	return row


func _format_time(seconds: float) -> String:
	var s: int = int(round(seconds))
	if s < 60:
		return "%ds" % s
	var m: int = s / 60
	var rem: int = s % 60
	if rem == 0:
		return "%dm" % m
	return "%dm %ds" % [m, rem]


# --- Craft execution ---

func _on_craft_pressed(r: Recipe, qty_box: SpinBox) -> void:
	var quantity: int = int(qty_box.value)
	if not _can_craft(r, quantity):
		NotificationSystem.warn("Can't craft that right now.")
		_rebuild_list()
		return

	var cost: Vector2 = _compute_cost(r, quantity)

	# Consume inputs first.
	for inp in r.inputs:
		_consume_from_inventory(inp.item.id, inp.count * quantity)

	# Apply stamina. Player API — adjust to match your project; this is
	# the pattern used by sleep/other drain sources.
	if _player.has_method("spend_stamina"):
		_player.spend_stamina(cost.y)

	# Advance time. Time is in seconds; convert to minutes (the unit
	# TimeSystem deals in). Round up so a 30s craft doesn't show as 0m.
	var minutes: int = int(ceil(cost.x / 60.0))
	if minutes > 0:
		var target: int = TimeSystem.total_minutes + minutes
		TimeSkipSystem.skip_to(target, {
			"kind": "craft",
			"safe": true,
			"voluntary": true,
		})

	# Add output.
	var leftover: int = _inventory.add(r.output_item, r.output_count * quantity)
	if leftover > 0:
		NotificationSystem.warn("Inventory full — %d %s lost." % [leftover, r.output_item.display_name])

	_rebuild_list()


func _can_craft(r: Recipe, quantity: int = 1) -> bool:
	for inp in r.inputs:
		if _count_in_inventory(inp.item.id) < inp.count * quantity:
			return false
	for tool in r.required_tools:
		if not _inventory.has_item(tool.id):
			return false
	var cost: Vector2 = _compute_cost(r, quantity)
	if cost.y > 0:
		StaminaSystem.spend(cost.y)
	return true


# --- Inventory helpers ---

func _count_in_inventory(item_id: StringName) -> int:
	var total: int = 0
	for stack in _inventory.slots:
		if stack != null and stack.item != null and stack.item.id == item_id:
			total += stack.count
	return total


func _consume_from_inventory(item_id: StringName, count: int) -> void:
	var needed: int = count
	for i in range(_inventory.slots.size()):
		if needed <= 0:
			break
		var stack: ItemStack = _inventory.get_slot(i)
		if stack == null or stack.item == null or stack.item.id != item_id:
			continue
		var taken: int = min(stack.count, needed)
		_inventory.consume_from_slot(i, taken)
		needed -= taken


func _recipe_display_name(r: Recipe) -> String:
	if r.display_name != "":
		return r.display_name
	if r.output_item != null:
		return r.output_item.display_name
	return String(r.id)
	
# Compute (time_seconds, stamina) for crafting `quantity` units of recipe r.
# Tool per-unit costs sum across all required_tools; base cost is added once.
func _compute_cost(r: Recipe, quantity: int) -> Vector2:
	var time: float = r.base_time_seconds
	var stamina: float = r.base_stamina
	for tool in r.required_tools:
		time += tool.craft_time_per_unit_seconds * quantity
		stamina += tool.craft_stamina_per_unit * quantity
	return Vector2(time, stamina)
