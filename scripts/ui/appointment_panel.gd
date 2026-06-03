extends Control

# Lists upcoming and active meetings. Opened/closed by clicking the pager icon.
# Refreshes live when meetings get scheduled, started, completed, or missed.

@onready var title_label: Label = $PanelContainer/VBoxContainer/Title
@onready var list_container: VBoxContainer = $PanelContainer/VBoxContainer/AppointmentList
@onready var close_button: Button = $PanelContainer/VBoxContainer/CloseButton

var _is_open: bool = false
# When opened "alongside" the time picker, the picker owns the pause and the
# escape-to-close. This panel just shows itself top-right and refreshes.
var _alongside: bool = false


func _ready() -> void:
	add_to_group("appointment_panel")
	visible = false
	close_button.pressed.connect(close)
	MeetingManager.meeting_scheduled.connect(_on_meetings_changed)
	MeetingManager.meeting_started.connect(_on_meetings_changed)
	MeetingManager.meeting_completed.connect(_on_meetings_changed)
	MeetingManager.meeting_missed.connect(_on_meetings_changed)
	EmploymentSystem.shift_scheduled.connect(_on_shift_changed)
	CourtSummons.court_paged.connect(_on_court_changed)
	CourtSummons.court_confirmed.connect(_on_court_confirmed)
	CourtSummons.court_resolved.connect(_on_court_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open or _alongside:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_shift_changed(_minute: int) -> void:
	if _is_open:
		_rebuild_list()


func _on_court_changed() -> void:
	if _is_open:
		_rebuild_list()


func _on_court_confirmed(_court_minute: int) -> void:
	if _is_open:
		_rebuild_list()


func toggle() -> void:
	if _is_open:
		close()
	else:
		open()


func open() -> void:
	if _is_open:
		return
	_is_open = true
	_alongside = false
	visible = true
	TimeSystem.pause()
	_rebuild_list()


# Shown next to the time picker. No pause, no input capture — the picker
# owns both. Safe to call when already open in normal mode (no-op).
func open_alongside() -> void:
	if _is_open and not _alongside:
		# Already open standalone; leave it as-is.
		return
	_is_open = true
	_alongside = true
	visible = true
	_rebuild_list()


func close_alongside() -> void:
	if not _is_open or not _alongside:
		return
	_is_open = false
	_alongside = false
	visible = false


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	if not _alongside:
		TimeSystem.resume()
	_alongside = false


func _on_meetings_changed(_m: Meeting) -> void:
	if _is_open:
		_rebuild_list()


func _rebuild_list() -> void:
	for c in list_container.get_children():
		c.queue_free()

	# Court date sits at the top — it's the obligation that overrides everything.
	if CourtSummons.has_pending():
		var court_lbl := Label.new()
		if CourtSummons.can_attend():
			court_lbl.text = "COURT — be at the bus stop @ %s" % \
				MeetingManager.format_minute(CourtSummons.court_minute())
		court_lbl.modulate = Color(1.0, 0.5, 0.5)
		list_container.add_child(court_lbl)

	if EmploymentSystem.has_shift_scheduled():
		var shift_lbl := Label.new()
		shift_lbl.text = "WORK — Bar shift @ %s" % \
			MeetingManager.format_minute(EmploymentSystem.next_shift_minute)
		list_container.add_child(shift_lbl)

	var now: int = TimeSystem.total_minutes
	var meetings: Array = []
	meetings.append_array(MeetingManager.active_meetings_now())
	meetings.append_array(MeetingManager.upcoming_meetings())
	meetings.sort_custom(func(a, b): return a.scheduled_minute < b.scheduled_minute)

	if meetings.is_empty():
		if not EmploymentSystem.has_shift_scheduled() and not CourtSummons.can_attend():
			var lbl := Label.new()
			lbl.text = "Nothing scheduled."
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
