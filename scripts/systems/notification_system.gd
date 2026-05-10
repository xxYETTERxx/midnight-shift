extends Node

# Global notification broadcaster. Any system can call notify() to surface
# a short message to the player. The HUD listens and displays.
#
# Lightweight by design — no queueing logic, no priorities. If multiple
# messages fire in quick succession, the HUD stacks/replaces them. Keeps
# all UX policy in one place (the HUD widget) rather than scattered here.

enum Kind { INFO, LOOT, WARNING, ERROR }

signal notification_posted(message: String, kind: int)


func info(message: String) -> void:
	notification_posted.emit(message, Kind.INFO)


func loot(item: ItemDef, count: int) -> void:
	var name: String = item.display_name if item != null else "?"
	if count > 1:
		notification_posted.emit("+%d %s" % [count, name], Kind.LOOT)
	else:
		notification_posted.emit("+ %s" % name, Kind.LOOT)


func warn(message: String) -> void:
	notification_posted.emit(message, Kind.WARNING)


func error(message: String) -> void:
	notification_posted.emit(message, Kind.ERROR)
