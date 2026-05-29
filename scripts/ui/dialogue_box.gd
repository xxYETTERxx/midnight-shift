extends CanvasLayer

# DialogueBox — driven entirely by DialogueRuntime.
# Knows how to display name + portrait + text, plus a list of choices.

# Maps single-letter portrait codes from .dlg files to filenames on disk.
# Anything not in this map falls back to "<code>.png" so $smug → smug.png.
const PORTRAIT_FILES: Dictionary = {
	"n": "neutral.png",
	"h": "happy.png",
	"s": "sad.png",
	"a": "angry.png",
	"w": "worried.png",
}

const PORTRAIT_FOLDER: String = "res://art/portraits/"

@onready var _name_label: Label = $PanelContainer/Margin/HBox/ContentVBox/NameLabel
@onready var _text_label: Label = $PanelContainer/Margin/HBox/ContentVBox/TextLabel
@onready var _portrait: TextureRect = $PanelContainer/Margin/HBox/PortraitFrame/Portrait
@onready var _choice_list: VBoxContainer = $PanelContainer/Margin/HBox/ContentVBox/ChoiceList
@onready var _panel: PanelContainer = $PanelContainer


var _texture_cache: Dictionary = {}

# Emitted when the player picks a choice via mouse or keyboard.
# Index is into the array passed to show_choices() — already filtered for
# eligibility on the runtime side.
signal choice_picked(index: int)


# --- Public API ---

func show_text(npc_id: String, display_name: String, portrait_code: String, text: String) -> void:
	# Showing new text always clears any leftover choices from a prior question.
	hide_choices()
	_name_label.text = display_name
	_text_label.text = text
	_set_portrait(npc_id, portrait_code)
	_panel.visible = true


func show_choices(texts: Array) -> void:
	_clear_choice_buttons()

	for i in range(texts.size()):
		var btn := Button.new()
		btn.text = "%d. %s" % [i + 1, texts[i]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_ALL
		btn.size_flags_horizontal = Control.SIZE_FILL
		btn.pressed.connect(_on_choice_pressed.bind(i))
		_choice_list.add_child(btn)


	# Focus the first choice so up/down navigation and ui_accept work
	# without the player needing to click first. Deferred because the
	# Button isn't fully in the tree until next idle frame.
	if _choice_list.get_child_count() > 0:
		_choice_list.get_child(0).call_deferred("grab_focus")


func hide_choices() -> void:
	_clear_choice_buttons()


# Called by DialogueRuntime when E (interact) is pressed during a question.
# Buttons natively respond to ui_accept (Enter/Space), but interact uses E,
# which is a separate input action — so the runtime asks the box to fire
# whichever button is currently focused.
func activate_focused_choice() -> bool:
	var focused: Control = get_viewport().gui_get_focus_owner()
	if focused != null and focused.get_parent() == _choice_list:
		focused.pressed.emit()
		return true

	# Fallback: nothing focused yet (e.g. player hammered E faster than the
	# deferred grab_focus could land). Fire the first choice.
	if _choice_list.visible and _choice_list.get_child_count() > 0:
		var first: Button = _choice_list.get_child(0) as Button
		if first != null:
			first.pressed.emit()
			return true

	return false

func clear() -> void:
	hide_choices()
	_name_label.text = ""
	_text_label.text = ""
	_portrait.texture = null
	visible = true         # CanvasLayer always on
	_panel.visible = false # Only the panel hides


# --- Internals ---

func _clear_choice_buttons() -> void:
	for child in _choice_list.get_children():
		_choice_list.remove_child(child)
		child.queue_free()


func _on_choice_pressed(index: int) -> void:
	choice_picked.emit(index)


func _set_portrait(npc_id: String, code: String) -> void:
	if code == "":
		return
	var key: String = "%s/%s" % [npc_id, code]
	if _texture_cache.has(key):
		_portrait.texture = _texture_cache[key]
		return
	var path: String = _portrait_path(npc_id, code)
	if not ResourceLoader.exists(path):
		var fallback: String = _portrait_path(npc_id, "n")
		if ResourceLoader.exists(fallback):
			path = fallback
		else:
			_portrait.texture = null
			return
	var tex: Texture2D = load(path)
	_texture_cache[key] = tex
	_portrait.texture = tex


func _portrait_path(npc_id: String, code: String) -> String:
	var filename: String = PORTRAIT_FILES.get(code, "%s.png" % code)
	return "%s%s/%s" % [PORTRAIT_FOLDER, npc_id, filename]
