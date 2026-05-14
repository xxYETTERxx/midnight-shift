class_name Branch
extends Node

# A choice branch under a ChoiceStep. The label is what shows in the choice
# menu. Children of this node are the EventSteps to run if this branch is
# picked.

@export var label: String = ""
