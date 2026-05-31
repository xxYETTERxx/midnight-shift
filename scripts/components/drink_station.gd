extends Node2D

# A single drink-prep station. Drop three of these (Beer / Whiskey / Cocktail),
# each with its own drink_type and prep_time. On interact: if the player isn't
# already carrying a drink, run a prep progress bar; on completion the player
# is "holding" this station's drink (tracked by the minigame controller).

@export var drink_type: StringName = &"beer"
@export var prep_time: float = 2.0

@onready var interactable: Interactable = $Interactable
@onready var _progress_bar: ProgressBar = $ProgressBar

var _prepping: bool = false
var _elapsed: float = 0.0

# Set on ready by finding the minigame controller in the tree.
var _shift: Node = null


func _ready() -> void:
	interactable.interacted.connect(_on_interacted)
	_progress_bar.visible = false
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.value = 0.0

func _exit_tree() -> void:
	if _prepping:
		_set_player_locked(false)

func _process(delta: float) -> void:
	if not _prepping:
		return
	_elapsed += delta
	_progress_bar.value = _elapsed / prep_time
	if _elapsed >= prep_time:
		_finish_prep()

func can_interact(_player: Node) -> bool:
	if _prepping:
		return false
	var shift := get_tree().get_first_node_in_group("bar_shift")
	if shift == null:
		return true
	return not shift.is_holding_drink()

func _on_interacted(_player: Node) -> void:
	if _prepping:
		return
	var shift := get_tree().get_first_node_in_group("bar_shift")
	if shift == null:
		push_warning("DrinkStation: no bar_shift controller found")
		return
	if shift.is_holding_drink():
		NotificationSystem.warn("Hands full — deliver that first.")
		return
	_prepping = true
	_elapsed = 0.0
	_progress_bar.value = 0.0
	_progress_bar.visible = true
	_set_player_locked(true)


func _finish_prep() -> void:
	_prepping = false
	_progress_bar.visible = false
	_set_player_locked(false)
	var shift := get_tree().get_first_node_in_group("bar_shift")
	if shift != null:
		shift.set_held_drink(drink_type)
	NotificationSystem.warn("Poured a %s." % String(drink_type))
	
func _set_player_locked(locked: bool) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and "input_locked" in player:
		player.input_locked = locked
