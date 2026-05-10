class_name Door
extends StaticBody2D

const CLOSED_FRAME: int = 0
const OPEN_FRAME: int = 3

const REST_FRAME: int = 0

@export var starts_open: bool = false

@export var sprite_frames: SpriteFrames

const ANIM_OPEN := "open"
const ANIM_CLOSE := "close"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var interactable: Interactable = $Interactable

var _is_open: bool = false


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)
	if sprite_frames != null:
		sprite.sprite_frames = sprite_frames
	_is_open = starts_open
	# Resting closed = frame 0 of "open"; resting open = frame 0 of "close".
	sprite.animation = "close" if starts_open else "open"
	sprite.frame = REST_FRAME
	sprite.stop()
	body_shape.set_deferred("disabled", starts_open)
	interactable.prompt_text = "Close" if starts_open else "Open"


func _on_interacted(_player: Node) -> void:
	if _is_open:
		_close()
	else:
		_open()


func _open() -> void:
	_is_open = true
	body_shape.set_deferred("disabled", true)
	interactable.prompt_text = "Close"
	sprite.play("open")


func _close() -> void:
	_is_open = false
	interactable.prompt_text = "Open"
	sprite.play("close")
	# Re-enable collision after the close animation finishes, so the player
	if not _is_open:  # guard: player may have re-opened it during the await
		body_shape.set_deferred("disabled", false)

func _set_visual_state(open: bool, instant: bool) -> void:
	if instant:
		# Snap to resting frame of the appropriate animation
		sprite.animation = ANIM_OPEN if open else ANIM_CLOSE
		sprite.frame = OPEN_FRAME if open else CLOSED_FRAME
		sprite.stop()
	else:
		# Animate to new state
		sprite.play(ANIM_OPEN if open else ANIM_CLOSE)
