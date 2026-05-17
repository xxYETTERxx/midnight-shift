extends Control

# Lists upcoming and active meetings. Opened/closed by clicking the pager icon.
# Refreshes live when meetings get scheduled, started, completed, or missed.

@onready var title_label: Label = $PanelContainer/VBoxContainer/Title
@onready var list_container: VBoxContainer = $PanelContainer/VBoxContainer/AppointmentList
@onready var close_button: Button = $PanelContainer/VBoxContainer/CloseButton

var _is_open: bool = false


func _ready() -> void:
	add_to_group("appointment_panel")
	visible = false
	close_button.pressed.connect(close)
	MeetingManager.meeting_scheduled.connect(_on_meetings_changed)
	MeetingManager.meeting_started.connect(_on_meetings_changed)
	MeetingManager.meeting_completed.connect(_on_meetings_changed)
	MeetingManager.meeting_missed.connect(_on_meetings_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	TimeSystem.pause()
	_rebuild_list()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	TimeSystem.resume()


func _on_meetings_changed(_m: Meeting) -> void:
	if _is_open:
		_rebuild_list()


func _rebuild_list() -> void:
	for c in list_container.get_children():
		c.queue_free()

	var now: int = TimeSystem.total_minutes
	var meetings: Array = []
	meetings.append_array(MeetingManager.active_meetings_now())
	meetings.append_array(MeetingManager.upcoming_meetings())
	meetings.sort_custom(func(a, b): return a.scheduled_minute < b.scheduled_minute)

	if meetings.is_empty():
		var lbl := Label.new()
		lbl.text = "No upcoming appointments."
		list_container.add_child(lbl)
		return

	for m in meetings:
		var customer: Customer = m.get_customer()
		if customer == null:
			continue
		var lbl := Label.new()
		var prefix: String = "[NOW] " if m.is_visible_at(now) else ""
		lbl.text = "%s%s — %s @ %s, qty %d" % [
			prefix,
			customer.display_name,
			MeetingManager.get_spot_display_name(m.spot_id),
			MeetingManager.format_minute(m.scheduled_minute),
			m.quantity_requested,
		]
		list_container.add_child(lbl)
