class_name EventStep
extends Node

# Abstract base. Subclasses override run(). Director awaits each step in order.
# Each step receives the event scene's root so it can resolve NodePaths
# scoped to the event (cast actors, markers, etc.).
func run(_event_root: Node) -> void:
	push_warning("EventStep: base run() called — subclass forgot to override")
