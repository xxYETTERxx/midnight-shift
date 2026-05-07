extends Control

# Always visible. Holds on the "off" texture when idle, alternates between
# off and on textures while there are pending pages.

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
	PagerSystem.page_received.connect(_on_page_received)
	PagerSystem.queue_changed.connect(_refresh)
	_refresh()


func _process(delta: float) -> void:
	if PagerSystem.pending_count() <= 0:
		# Idle: hold on the off texture, don't tick the blink timer.
		return
	_blink_timer += delta
	if _blink_timer >= blink_period_seconds:
		_blink_timer = 0.0
		_blink_on = not _blink_on
		icon.texture = on_texture if _blink_on else off_texture


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
		# New pages: start the blink visibly "on" so it pulses on arrival.
		icon.texture = on_texture
		_blink_on = true
		_blink_timer = 0.0
