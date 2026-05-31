extends Node2D

# A bar patron. Spawns at a counter slot wanting one drink type, waits with a
# draining patience timer, and leaves — served or stormed out. Delivery itself
# is handled by the minigame controller (Step 4); this script owns the want,
# the timer, and the leave lifecycle.

@export var patience_seconds: float = 12.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _order_icon: TextureRect = $OrderBubble/OrderIcon
@onready var _patience_bar: ProgressBar = $PatienceBar
@onready var _interactable: Interactable = $Interactable

# The drink this customer wants. Set by the controller at spawn.
var order: StringName = &""

var _patience_left: float = 0.0
var _resolved: bool = false
var _order_texture: Texture2D = null

# Emitted when the customer leaves for any reason. served = got their drink.
signal resolved(served: bool, customer: Node)


func _ready() -> void:
	_patience_left = patience_seconds
	_patience_bar.min_value = 0.0
	_patience_bar.max_value = 1.0
	_patience_bar.value = 1.0
	_interactable.interacted.connect(_on_interacted)
	_interactable.prompt_text = "Serve drink"
	_apply_order_icon()


func _apply_order_icon() -> void:
	if _order_texture != null:
		_order_icon.texture = _order_texture
		
func set_order(drink_type: StringName, icon: Texture2D) -> void:
	order = drink_type
	_order_texture = icon
	

func _process(delta: float) -> void:
	if _resolved:
		return
	_patience_left -= delta
	_patience_bar.value = _patience_left / patience_seconds
	if _patience_left <= 0.0:
		_storm_out()

func can_interact(_player: Node) -> bool:
	if _resolved:
		return false
	var shift := get_tree().get_first_node_in_group("bar_shift")
	if shift == null:
		return false
	return shift.is_holding_drink() and shift.held_drink() == order

func _on_interacted(_player: Node) -> void:
	if _resolved:
		return
	var shift := get_tree().get_first_node_in_group("bar_shift")
	if shift != null:
		shift.try_deliver_to(self)

# Fraction of patience remaining, 0..1. Used by the controller to scale tips.
func patience_fraction() -> float:
	return clampf(_patience_left / patience_seconds, 0.0, 1.0)


func wants() -> StringName:
	return order


# Called by the controller when the player delivers the correct drink.
func serve() -> void:
	if _resolved:
		return
	_resolved = true
	_patience_bar.visible = false
	resolved.emit(true, self)
	_leave()


func _storm_out() -> void:
	if _resolved:
		return
	_resolved = true
	_patience_bar.visible = false
	resolved.emit(false, self)
	_leave()


func _leave() -> void:
	# Step 3: just despawn. A walk-off tween can come in polish.
	queue_free()
