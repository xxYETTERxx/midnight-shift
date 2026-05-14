class_name CutsceneActor
extends Node2D

# A puppet sprite used inside event scenes. Wraps an AnimatedSprite2D and
# exposes the small set of methods event steps need to drive it. Not a real
# NPC — no schedule, no dialogue queue, no AI.

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D

# Portrait code used by DialogueStep when this actor speaks. Matches whatever
# vocabulary your dialogue box's portrait map already uses ('n', 's', ...).
@export var default_portrait: String = "n"
@export var display_name: String = ""
@export var dialogue_npc_id: String = ""

var _facing: String = "south"


func face(direction: String) -> void:
	_facing = direction
	_play_idle()


func get_facing() -> String:
	return _facing


# Tween-walk to a world position. Awaitable: `await actor.walk_to(...)`.
func walk_to(target_position: Vector2, speed: float = 60.0) -> void:
	print("[CutsceneActor] %s walk_to %s (dist %.1f)" % [name, target_position, global_position.distance_to(target_position)])
	var distance: float = global_position.distance_to(target_position)
	if distance < 0.5:
		return
	var duration: float = distance / max(speed, 1.0)

	# Pick walk animation from dominant axis of travel.
	var delta := target_position - global_position
	if absf(delta.y) >= absf(delta.x):
		_facing = "n" if delta.y < 0.0 else "s"
	else:
		_facing = "w" if delta.x < 0.0 else "e"
	_play_walk()

	var tween := create_tween()
	tween.tween_property(self, "global_position", target_position, duration)
	await tween.finished
	_play_idle()


# Play a specific animation. If await_finish, blocks until it ends or loops.
func play_animation(anim_name: String, await_finish: bool = false) -> void:
	if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(anim_name):
		push_warning("CutsceneActor '%s': no animation '%s'" % [name, anim_name])
		return
	sprite.play(anim_name)
	if await_finish:
		await sprite.animation_finished


func _play_idle() -> void:
	var anim := "walk_" + _facing
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
		sprite.pause()
		sprite.frame = 0


func _play_walk() -> void:
	var anim := "walk_" + _facing
	if sprite.sprite_frames != null and sprite.sprite_frames.has_animation(anim):
		sprite.play(anim)
