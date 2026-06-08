extends Node2D


func _ready() -> void:
	$Interactable.interacted.connect(_on_interacted)
	

# On whatever you attach to the test interactable in the world:
func _on_interacted(_player: Node) -> void:
	var bar := get_tree().get_first_node_in_group("timing_bar_test")
	if bar == null:
		return
	if not bar.resolved.is_connected(_on_bar_resolved):
		bar.resolved.connect(_on_bar_resolved)
	bar.start()   # uses the exported speed/width/band you set in the inspector

func _on_bar_resolved(quality: int, accuracy: float) -> void:
	var name = ["MISS", "GOOD", "PERFECT"][quality]
	print("[TimingBar] %s  accuracy=%.2f" % [name, accuracy])
