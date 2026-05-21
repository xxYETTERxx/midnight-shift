class_name PlacementPreview
extends Node2D

const TILE_SIZE: int = 16

const COLOR_VALID: Color = Color(0.4, 1.0, 0.4, 0.35)
const COLOR_INVALID: Color = Color(1.0, 0.4, 0.4, 0.35)

var _color: Color = COLOR_VALID


func _ready() -> void:
	# Render above the floor but stay clear of Y-sort so the highlight
	# always sits cleanly on the tile it represents.
	z_index = 1
	y_sort_enabled = false


func _draw() -> void:
	var rect := Rect2(-TILE_SIZE / 2.0, -TILE_SIZE / 2.0, TILE_SIZE, TILE_SIZE)
	draw_rect(rect, _color, true)
	# Slightly stronger outline to keep the edge readable on busy tiles.
	var outline := Color(_color.r, _color.g, _color.b, 0.9)
	draw_rect(rect, outline, false, 1.0)


func set_valid(valid: bool) -> void:
	var new_color := COLOR_VALID if valid else COLOR_INVALID
	if new_color != _color:
		_color = new_color
		queue_redraw()
