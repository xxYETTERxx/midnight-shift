extends VBoxContainer

# Listens to NotificationSystem and displays messages as a vertical stack
# of labels that fade out after a few seconds. New notifications push down;
# old ones expire on their own.

const DISPLAY_DURATION: float = 3.0
const FADE_DURATION: float = 0.6
const MAX_VISIBLE: int = 5

const COLOR_INFO: Color = Color(1.0, 1.0, 1.0)
const COLOR_LOOT: Color = Color(0.7, 1.0, 0.7)
const COLOR_WARNING: Color = Color(1.0, 0.9, 0.5)
const COLOR_ERROR: Color = Color(1.0, 0.5, 0.5)


func _ready() -> void:
	NotificationSystem.notification_posted.connect(_on_notification)


func _on_notification(message: String, kind: int) -> void:
	var label := Label.new()
	label.text = message
	label.modulate = _color_for(kind)
	add_child(label)
	# Push new ones to the top so latest is most visible.
	move_child(label, 0)
	_trim_excess()
	_schedule_fade(label)


func _color_for(kind: int) -> Color:
	match kind:
		NotificationSystem.Kind.LOOT: return COLOR_LOOT
		NotificationSystem.Kind.WARNING: return COLOR_WARNING
		NotificationSystem.Kind.ERROR: return COLOR_ERROR
		_: return COLOR_INFO


func _trim_excess() -> void:
	while get_child_count() > MAX_VISIBLE:
		var oldest := get_child(get_child_count() - 1)
		oldest.queue_free()


func _schedule_fade(label: Label) -> void:
	var tween := create_tween()
	tween.tween_interval(DISPLAY_DURATION)
	tween.tween_property(label, "modulate:a", 0.0, FADE_DURATION)
	tween.tween_callback(label.queue_free)
