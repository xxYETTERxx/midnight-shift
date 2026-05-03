extends PanelContainer

@onready var icon: TextureRect = $Icon
@onready var count_label: Label = $Count

var slot_index: int = -1
var _is_active: bool = false

# Style boxes for inactive vs active states. Built once in _ready.
var _style_inactive: StyleBoxFlat
var _style_active: StyleBoxFlat


func _ready() -> void:
	_build_styles()
	_apply_style()
	render(null)


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
