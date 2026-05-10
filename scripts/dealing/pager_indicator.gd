extends Control

@export var blink_period_seconds: float = 0.6
@export var off_texture: Texture2D
@export var on_texture: Texture2D

@onready var icon: TextureRect = $Icon
@onready var count_label: Label = $CountLabel
@onready var beep_player: AudioStreamPlayer = $BeepPlayer

var _blink_timer: float = 0.0
var _blink_on: bool = false


func _ready() -> void:
	count_label.visible = false
	icon.mouse_filter = Control.MOUSE_FILTER_STOP
	icon.gui_input.connect(_on_icon_gui_input)
	PagerSystem.page_received.connect(_on_page_received)
	PagerSystem.queue_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if PagerSystem.pending_count() <= 0:
		return
	_blink_timer += delta
	if _blink_timer >= blink_period_seconds:
		_blink_timer = 0.0
		_blink_on = not _blink_on
		icon.texture = on_texture if _blink_on else off_texture


func _on_icon_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
	and event.button_index == MOUSE_BUTTON_LEFT:
		var panel := get_tree().get_first_node_in_group("appointment_panel")
		if panel != null:
			panel.toggle()
		get_viewport().set_input_as_handled()


func _on_page_received(_page: PendingPage) -> void:
	if beep_player.stream != null:
		beep_player.play()


func _refresh() -> void:
	var count := PagerSystem.pending_count()
	if count > 1:
		count_label.visible = true
		count_label.text = "%d" % count
	else:
		count_label.visible = false
	if count <= 0:
		icon.texture = off_texture
		_blink_on = false
	else:
		icon.texture = on_texture
		_blink_on = true
		_blink_timer = 0.0
