class_name CharacterSprite
extends Node2D

# Stacked-sprite NPC component. A static head Sprite2D sits above an
# AnimatedSprite2D body. Heads are 4 separate textures (one per facing,
# keyed "n" / "s" / "e" / "w"); animations are named "walk_n", "idle_s",
# etc. — single-letter convention matches the art file naming.

const WALK_PREFIX: String = "walk"
const IDLE_PREFIX: String = "idle"

@onready var head: Sprite2D = $Head
@onready var body: AnimatedSprite2D = $Body

@export var bob_frames: Array[int] = [2]
@export var bob_offset: float = -1.0

var _head_base_y: float = 0.0
var _category: StringName = &""
var _head_index: int = -1
var _facing: String = "s"

func _ready() -> void:
	_head_base_y = head.position.y
	body.frame_changed.connect(_on_body_frame_changed)

func apply_appearance(category: StringName, head_index: int, body_index: int) -> void:
	_category = category
	_head_index = head_index
	_refresh_head()
	var body_frames: SpriteFrames = NPCGenerator.get_body_frames(category, body_index)
	if body_frames != null:
		body.sprite_frames = body_frames
		_apply_body_anim(IDLE_PREFIX, _facing)


func play_anim(prefix: String, facing: String) -> void:
	_facing = facing
	_refresh_head()
	_apply_body_anim(prefix, facing)


func _refresh_head() -> void:
	if head == null or _head_index < 0:
		return
	var tex: Texture2D = NPCGenerator.get_head_texture(_category, _head_index, _facing)
	if tex != null:
		head.texture = tex


func _apply_body_anim(prefix: String, facing: String) -> void:
	if body == null or body.sprite_frames == null:
		return
	var candidates: Array[String] = [
		"%s_%s" % [prefix, facing],   # walk_s
		prefix,                        # walk
		"idle_%s" % facing,            # idle_s
		"idle",
	]
	for n in candidates:
		if body.sprite_frames.has_animation(n):
			if body.animation != n:
				body.play(n)
			return
			
func _on_body_frame_changed() -> void:
	var is_walking: bool = body.animation.begins_with(WALK_PREFIX)
	if is_walking and bob_frames.has(body.frame):
		head.position.y = _head_base_y + bob_offset
	else:
		head.position.y = _head_base_y
