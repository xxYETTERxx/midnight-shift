extends CanvasLayer

@onready var black: ColorRect = $Black


func fade_out(duration: float = 0.5) -> void:
	black.mouse_filter = Control.MOUSE_FILTER_STOP  # block input while fading
	var tween := create_tween()
	tween.tween_property(black, "color:a", 1.0, duration)
	await tween.finished


func fade_in(duration: float = 0.5) -> void:
	var tween := create_tween()
	tween.tween_property(black, "color:a", 0.0, duration)
	await tween.finished
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE  # clear input block when transparent


# Convenience wrapper: fade out, run a callable, fade back in.
# Used by sleep, arrests, etc.
func cover(action: Callable, fade_duration: float = 0.5) -> void:
	await fade_out(fade_duration)
	await action.call()
	await fade_in(fade_duration)
