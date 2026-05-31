extends Control

# Shown after the player taps "Return Call" on a pending page. Displays the
# single chosen spot and 3-5 free future time slots. Player picks one to
# commit the meeting. Owns the time pause while open and toggles the
# appointment panel alongside (top-right) without letting it touch pause.

@onready var title_label: Label = $PanelContainer/VBoxContainer/Title
@onready var spot_label: Label = $PanelContainer/VBoxContainer/SpotLabel
@onready var slot_container: VBoxContainer = $PanelContainer/VBoxContainer/SlotList
@onready var status_label: Label = $PanelContainer/VBoxContainer/Status
@onready var close_button: Button = $PanelContainer/VBoxContainer/CloseButton

const SLOT_COUNT: int = 5

var _is_open: bool = false
var _customer: Customer = null
var _quantity: int = 0
var _spot_id: StringName = ""
# Called back into the callback panel on success so it can consume the page.
var _on_committed: Callable = Callable()


func _ready() -> void:
	add_to_group("time_picker_panel")
	visible = false
	close_button.pressed.connect(close)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


# Opens the picker for one page. `on_committed` is invoked (no args) only on a
# successful schedule, so the caller can consume the page and update its UI.
func open_for(customer: Customer, quantity: int, on_committed: Callable) -> void:
	if customer == null:
		return
	_customer = customer
	_quantity = quantity
	_on_committed = on_committed

	if _is_open:
		_rebuild()
		return
	_is_open = true
	visible = true
	TimeSystem.pause()
	status_label.text = ""
	_show_appointment_panel()
	_rebuild()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	_hide_appointment_panel()
	TimeSystem.resume()
	_customer = null
	_on_committed = Callable()


func _rebuild() -> void:
	for c in slot_container.get_children():
		c.queue_free()

	title_label.text = "Set up meet — %s (wants %d)" % [
		_customer.display_name, _quantity,
	]

	var offer: Dictionary = MeetingManager.offer_slots(SLOT_COUNT)
	if offer.is_empty():
		_spot_id = &""
		spot_label.text = "No spots available right now."
		return

	_spot_id = offer["spot_id"]
	spot_label.text = "Location: %s" % MeetingManager.get_spot_display_name(_spot_id)

	for minute in offer["slots"]:
		var btn := Button.new()
		btn.text = MeetingManager.format_minute(minute)
		btn.pressed.connect(_on_slot_pressed.bind(minute))
		slot_container.add_child(btn)


func _on_slot_pressed(minute: int) -> void:
	if _customer == null or _spot_id == &"":
		return
	var meeting: Meeting = MeetingManager.schedule_meeting_at(
		_customer, _quantity, _spot_id, minute,
	)
	if meeting == null:
		# Slot got taken or otherwise invalid — refresh the offer and let the
		# player pick again.
		status_label.text = "That time's no longer free — pick another."
		_rebuild()
		return
	if _on_committed.is_valid():
		_on_committed.call()
	close()


func _show_appointment_panel() -> void:
	var ap: Node = get_tree().get_first_node_in_group("appointment_panel")
	if ap != null and ap.has_method("open_alongside"):
		ap.open_alongside()


func _hide_appointment_panel() -> void:
	var ap: Node = get_tree().get_first_node_in_group("appointment_panel")
	if ap != null and ap.has_method("close_alongside"):
		ap.close_alongside()
