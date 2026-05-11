class_name HotbarSlot
extends PanelContainer

@onready var icon: TextureRect = $Icon
@onready var count_label: Label = $Count

var slot_index: int = -1
var _is_active: bool = false

# Style boxes for inactive vs active states. Built once in _ready.
var _style_inactive: StyleBoxFlat
var _style_active: StyleBoxFlat

signal clicked(slot_index: int, action: int)
signal hover_entered(slot_index: int)

signal hovered(slot_index: int)
signal unhovered(slot_index: int)

enum Action { INTERACT, SPLIT, TRANSFER, MOVE_ONE }


func _ready() -> void:
	_build_styles()
	_apply_style()
	render(null)
	mouse_entered.connect(func(): hover_entered.emit(slot_index))
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func _build_styles() -> void:
	# Inactive: dim border (matches editor default)
	_style_inactive = StyleBoxFlat.new()
	_style_inactive.bg_color = Color(0, 0, 0, 0.5)
	_style_inactive.border_color = Color(0.4, 0.4, 0.4, 0.8)
	_style_inactive.border_width_left = 1
	_style_inactive.border_width_right = 1
	_style_inactive.border_width_top = 1
	_style_inactive.border_width_bottom = 1

	# Active: bright border, slightly lighter background
	_style_active = StyleBoxFlat.new()
	_style_active.bg_color = Color(0, 0, 0, 0.7)
	_style_active.border_color = Color(1.0, 0.9, 0.5, 1.0)  # warm yellow
	_style_active.border_width_left = 2
	_style_active.border_width_right = 2
	_style_active.border_width_top = 2
	_style_active.border_width_bottom = 2


func render(stack: ItemStack) -> void:
	if stack == null or stack.item == null:
		icon.texture = null
		count_label.text = ""
		return
	icon.texture = stack.item.icon
	# Only show count if > 1
	if stack.count > 1:
		count_label.text = str(stack.count)
	else:
		count_label.text = ""


func set_active(is_active: bool) -> void:
	_is_active = is_active
	_apply_style()


func _apply_style() -> void:
	if _is_active:
		add_theme_stylebox_override("panel", _style_active)
	else:
		add_theme_stylebox_override("panel", _style_inactive)

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if not event.pressed:
		return
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			# CTRL wins over SHIFT if both held.
			if Input.is_key_pressed(KEY_CTRL):
				clicked.emit(slot_index, Action.INTERACT)
			elif Input.is_key_pressed(KEY_SHIFT):
				clicked.emit(slot_index, Action.TRANSFER)
			else:
				clicked.emit(slot_index, Action.MOVE_ONE)
		MOUSE_BUTTON_RIGHT:
			clicked.emit(slot_index, Action.SPLIT)

# Called when the panel wants to highlight this slot as the selection.
func set_hovered(is_hovered: bool) -> void:
	if is_hovered:
		add_theme_stylebox_override("panel", _style_active)  # reuse active style
	elif _is_active:
		add_theme_stylebox_override("panel", _style_active)
	else:
		add_theme_stylebox_override("panel", _style_inactive)

func _on_mouse_entered() -> void:
	hovered.emit(slot_index)
	
func _on_mouse_exited() -> void:
	unhovered.emit(slot_index)
