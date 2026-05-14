extends Control

const HotbarSlot := preload("res://scenes/ui/hotbar_slot.tscn")

@onready var _header: Label = $Panel/VBox/Header
@onready var _grid: GridContainer = $Panel/VBox/Grid

var _target_npc_id: String = ""
var _target_display_name: String = ""
var _inventory: Inventory = null

signal closed



func open(npc_id: String, display_name: String) -> void:
	if _inventory == null:
		var player := get_tree().get_first_node_in_group("player")
		if player == null:
			push_warning("GiftPanel: no player in tree")
			return
		_inventory = player.inventory

	_target_npc_id = npc_id
	_target_display_name = display_name
	_header.text = "Give to %s" % display_name
	_rebuild()
	visible = true


func close() -> void:
	visible = false
	closed.emit()


func _rebuild() -> void:
	for child in _grid.get_children():
		child.queue_free()
	if _inventory == null:
		print("[GiftPanel] no inventory ref")
		return
	var added := 0
	for i in range(_inventory.max_slots):
		var stack: ItemStack = _inventory.get_slot(i)
		if stack == null or stack.is_empty():
			continue
		if not stack.item.giftable:
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(64, 64)
		btn.icon = stack.item.icon
		btn.expand_icon = true
		btn.text = "x%d" % stack.count
		btn.tooltip_text = stack.item.display_name
		btn.pressed.connect(_on_slot_pressed.bind(i))
		_grid.add_child(btn)
		added+=1
	print("[GiftPanel] rebuild added=", added, " grid children=", _grid.get_child_count())


func _on_slot_pressed(slot_index: int) -> void:
	if not RelationshipSystem.can_receive_gift(_target_npc_id):
		close()
		return

	var stack: ItemStack = _inventory.get_slot(slot_index)
	if stack == null or stack.is_empty():
		return
	var item: ItemDef = stack.item
	if not _inventory.consume_from_slot(slot_index, 1):
		return

	var result: Dictionary = GiftSystem.give_gift(_target_npc_id, item)
	close()
	_play_reaction(result["line"])


func _play_reaction(line: String) -> void:
	var entry := {
		"body": [
			{"kind": "text", "portrait": "n", "text": line},
		],
	}
	DialogueRuntime.start(_target_npc_id, _target_display_name, entry)


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
