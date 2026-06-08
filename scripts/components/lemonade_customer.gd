extends Node2D

# A lemonade-stand patron. Walks in from a street edge (rounding the corner
# pivot) to a counter spot, waits while patience drains, and orders either
# lemonade (interact) or a dime bag (alt_interact). The serve is a timed
# action driven here; money/heat/crime are settled by the minigame via the
# resolved signal. After resolving (served, wrong-action, or timeout) they
# walk back out along their exit path and free.

@export var patience_seconds: float = 20.0
@export var walk_speed: float = 60.0

const SERVE_TIME_LEMONADE: float = 1.4
const SERVE_TIME_WEED: float = 2.2   # longer = riskier exposure

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _order_icon: TextureRect = $OrderBubble/OrderIcon
@onready var _patience_bar: ProgressBar = $PatienceBar
@onready var _serve_bar: ProgressBar = $ServeBar
@onready var _interactable: Interactable = $Interactable

var kind: StringName = &"lemonade"   # &"lemonade" | &"weed"

var _patience_left: float = 0.0
var _resolved: bool = false
var _icon_texture: Texture2D = null
var _pending_prompt: String = ""

# Serve-in-progress.
var _serving: bool = false
var _serve_elapsed: float = 0.0
var _serve_duration: float = 0.0

# Movement. _path is the active leg (walk-in, then swapped to walk-out on
# resolve). Each leg is [start, pivot, end] in GLOBAL space.
var _path: PackedVector2Array = PackedVector2Array()
var _path_index: int = 0
var _walk_out_path: PackedVector2Array = PackedVector2Array()
var _arrived: bool = false
var _leaving: bool = false
var facing_right: bool = true

signal resolved(served: bool, kind: StringName, customer: Node)


func _ready() -> void:
	_patience_left = patience_seconds
	_patience_bar.min_value = 0.0
	_patience_bar.max_value = 1.0
	_patience_bar.value = 1.0
	_serve_bar.min_value = 0.0
	_serve_bar.max_value = 1.0
	_serve_bar.value = 0.0
	_serve_bar.visible = false
	_interactable.interacted.connect(_on_interacted)
	_interactable.alt_interacted.connect(_on_alt_interacted)
	# Walking in — not yet orderable, no order shown, patience paused.
	_order_icon.visible = false
	_patience_bar.visible = false
	_interactable.monitoring = false
	_apply_setup()


# --- Setup (called by the minigame, possibly before _ready) ---

func setup(p_kind: StringName, icon: Texture2D, prompt: String) -> void:
	kind = p_kind
	_icon_texture = icon
	_pending_prompt = prompt
	if is_node_ready():
		_apply_setup()


func _apply_setup() -> void:
	if _icon_texture != null:
		_order_icon.texture = _icon_texture
	_interactable.prompt_text = _pending_prompt


func set_walk_in(points: PackedVector2Array) -> void:
	_path = points
	_path_index = 0
	if not _path.is_empty():
		global_position = _path[0]


func set_walk_out(points: PackedVector2Array) -> void:
	_walk_out_path = points


# --- Per-frame ---

func _process(delta: float) -> void:
	if _leaving:
		_tick_walk(delta)
		return
	if _resolved:
		return
	if not _arrived:
		_tick_walk(delta)
		return
	if _serving:
		_tick_serve(delta)
	_patience_left -= delta
	_patience_bar.value = _patience_left / patience_seconds
	if _patience_left <= 0.0:
		_storm_out()


func _tick_walk(delta: float) -> void:
	if _path_index >= _path.size():
		_on_path_done()
		return
	var target: Vector2 = _path[_path_index]
	var to_target: Vector2 = target - global_position
	var step: float = walk_speed * delta
	if to_target.length() <= step:
		global_position = target
		_path_index += 1
		if _path_index >= _path.size():
			_on_path_done()
			return
		_update_facing_from_next()
	else:
		global_position += to_target.normalized() * step
		_update_facing_from_next()


func _on_path_done() -> void:
	if _leaving:
		queue_free()
	else:
		_on_arrived()


func _on_arrived() -> void:
	_arrived = true
	_play_anim_with_fallback("idle")
	_order_icon.visible = true
	_patience_bar.visible = true
	_interactable.monitoring = true


# --- Ordering ---

func _on_interacted(_player: Node) -> void:
	if _resolved or _serving or not _arrived:
		return
	_begin_serve(&"lemonade")


func _on_alt_interacted(_player: Node) -> void:
	if _resolved or _serving or not _arrived:
		return
	_begin_serve(&"weed")


func _begin_serve(action_kind: StringName) -> void:
	# Weed offered to a lemonade buyer = suspicious misfire (controller spikes heat).
	if action_kind == &"weed" and kind == &"lemonade":
		_resolve(false, &"weed_to_innocent")
		return
	# Lemonade offered to a weed buyer = harmless decline.
	if action_kind == &"lemonade" and kind == &"weed":
		_resolve(false, &"lemonade_to_buyer")
		return
	_serving = true
	_serve_elapsed = 0.0
	_serve_duration = SERVE_TIME_WEED if kind == &"weed" else SERVE_TIME_LEMONADE
	_serve_bar.visible = true
	_serve_bar.value = 0.0


func _tick_serve(delta: float) -> void:
	_serve_elapsed += delta
	_serve_bar.value = clampf(_serve_elapsed / _serve_duration, 0.0, 1.0)
	if _serve_elapsed >= _serve_duration:
		_serving = false
		_serve_bar.visible = false
		_resolve(true, kind)


# served=true → kind is &"lemonade"/&"weed". served=false → &"weed_to_innocent",
# &"lemonade_to_buyer", or &"timeout". Settles via the controller, then walks out.
func _resolve(served: bool, outcome_kind: StringName) -> void:
	if _resolved:
		return
	_resolved = true
	_serving = false
	_patience_bar.visible = false
	_serve_bar.visible = false
	_order_icon.visible = false
	_interactable.monitoring = false
	resolved.emit(served, outcome_kind, self)
	# Walk out along the exit path. _tick_walk's facing update picks the walk anim.
	_leaving = true
	_path = _walk_out_path
	_path_index = 0
	_update_facing_from_next()


func _storm_out() -> void:
	_resolve(false, &"timeout")


func patience_fraction() -> float:
	return clampf(_patience_left / patience_seconds, 0.0, 1.0)


# --- Facing / animation ---

func _update_facing_from_next() -> void:
	if _path_index >= _path.size():
		return
	var to_target: Vector2 = _path[_path_index] - global_position
	if to_target.length() < 0.01:
		return
	_play_walk_for_dir(to_target)


func _play_walk_for_dir(dir: Vector2) -> void:
	if _sprite.sprite_frames == null:
		return
	var anim: String
	if absf(dir.x) >= absf(dir.y):
		facing_right = dir.x > 0.0
		anim = "walk_e"
		_sprite.flip_h = not facing_right
	else:
		_sprite.flip_h = false
		anim = "walk_n" if dir.y < 0.0 else "walk_s"
	_play_anim_with_fallback(anim)


func _play_anim_with_fallback(anim: String) -> void:
	var sf := _sprite.sprite_frames
	if sf == null:
		return
	if sf.has_animation(anim):
		_sprite.play(anim)
	elif sf.has_animation("walk"):
		_sprite.play("walk")
