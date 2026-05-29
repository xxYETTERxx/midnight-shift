class_name Door
extends StaticBody2D

const CLOSED_FRAME: int = 0
const OPEN_FRAME: int = 3

const REST_FRAME: int = 0

@export var starts_open: bool = false

@export var sprite_frames: SpriteFrames

@export var requires_global_flag: String = ""


# Lockable doors enforce open hours. When the current calendar minute is
# outside [time_open, time_close), interacting fires a notification with
# the door's hours and the door stays closed. Both fields are in calendar
# minute-of-day (0-1439). Leave is_lockable false for doors that should
# always work (apartments, internal doors, etc.).
@export var owner_home_scene: String = ""
@export var owner_npc: StringName = &""
@export var is_lockable: bool = false
@export var time_open: String = "09:00"
@export var time_close: String = "21:00"
@export var late_lockout: String = ""

@export_flags("Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday")
var locked_days: int = 0

var _late_lockout_min: int = -1

var _time_open_min: int = 0
var _time_close_min: int = 0

const ANIM_OPEN := "open"
const ANIM_CLOSE := "close"

@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var body_shape: CollisionShape2D = $CollisionShape2D
@onready var interactable: Interactable = $Interactable

var _is_open: bool = false


func _ready() -> void:
	_time_open_min = _parse_hhmm(time_open)
	_time_close_min = _parse_hhmm(time_close)
	_late_lockout_min = _parse_hhmm(late_lockout) if late_lockout != "" else -1
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
		return
	if is_lockable and not _is_unlocked():
		NotificationSystem.warn(_locked_message())
		return
	if requires_global_flag == "":
		_open()
	else:
		if RelationshipSystem.get_global_flag(requires_global_flag):
			_open()
			return
	NotificationSystem.warn("Locked")
	return


# Open hours run from time_open (inclusive) to time_close (exclusive).
# Wraps midnight when time_close < time_open (e.g. a bar open 18:00–02:00).
func _is_within_open_hours() -> bool:
	var now: int = (TimeSystem.total_minutes + 14 * 60) % 1440
	if _time_open_min == _time_close_min:
		return false
	if _time_open_min < _time_close_min:
		return now >= _time_open_min and now < _time_close_min
	return now >= _time_open_min or now < _time_close_min

func _is_unlocked() -> bool:
	if _is_locked_today():
		return false
	if _is_within_open_hours():
		return true
	if owner_npc != &"" \
			and owner_home_scene != "" \
			and NPCDirector.is_npc_in_scene(owner_npc, owner_home_scene) \
			and not _is_after_late_lockout():
		return true
	return false


# True if a late_lockout is configured and the current calendar minute is
# at or past it (until midnight, when it wraps and the next morning is
# back in the permissive window).
func _is_after_late_lockout() -> bool:
	if _late_lockout_min < 0:
		return false
	var now: int = (TimeSystem.total_minutes + 14 * 60) % 1440
	return now >= _late_lockout_min


func _format_time(minute_of_day: int) -> String:
	var h: int = minute_of_day / 60
	var m: int = minute_of_day % 60
	return "%d:%02d" % [h, m]


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
		
func _parse_hhmm(s: String) -> int:
	var parts: PackedStringArray = s.split(":")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		push_warning("Door at %s: invalid time '%s' (expected HH:MM)" % [get_path(), s])
		return 0
	var h: int = parts[0].to_int()
	var m: int = parts[1].to_int()
	if h < 0 or h > 23 or m < 0 or m > 59:
		push_warning("Door at %s: time '%s' out of range" % [get_path(), s])
		return 0
	return h * 60 + m
	
func _locked_message() -> String:
	if _is_locked_today():
		return "Closed today."
	if _time_open_min == _time_close_min:
		return "Locked. No one's answering."
	return "Locked. Open %s – %s." % [
		_format_time(_time_open_min), _format_time(_time_close_min),
	]

func _is_locked_today() -> bool:
	if locked_days == 0:
		return false
	var dow: int = TimeSystem.day_of_week()
	return (locked_days & (1 << dow)) != 0
