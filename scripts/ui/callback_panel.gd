extends Control

@onready var title_label: Label = $PanelContainer/VBoxContainer/Title
@onready var list_container: VBoxContainer = $PanelContainer/VBoxContainer/PageList
@onready var status_label: Label = $PanelContainer/VBoxContainer/Status
@onready var close_button: Button = $PanelContainer/VBoxContainer/CloseButton

var _is_open: bool = false


func _ready() -> void:
	add_to_group("callback_panel")
	visible = false
	close_button.pressed.connect(close)
	PagerSystem.queue_changed.connect(_on_queue_changed)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func open() -> void:
	if _is_open:
		return
	_is_open = true
	visible = true
	TimeSystem.pause()
	status_label.text = ""
	_rebuild_list()


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	visible = false
	TimeSystem.resume()


func _on_queue_changed() -> void:
	if _is_open:
		_rebuild_list()


func _rebuild_list() -> void:
	for c in list_container.get_children():
		c.queue_free()
	var pages := PagerSystem.pending_pages()
	if pages.is_empty():
		var lbl := Label.new()
		lbl.text = "No messages."
		list_container.add_child(lbl)
		return
	for p in pages:
		var customer: Customer = p.get_customer()
		if customer == null:
			continue
		var row := HBoxContainer.new()
		var info := Label.new()
		info.text = "%s — wants %d  (%dm left)" % [
			customer.display_name, p.quantity_requested, p.minutes_remaining,
		]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var btn := Button.new()
		btn.text = "Return Call"
		btn.pressed.connect(_on_return_call_pressed.bind(p))
		row.add_child(btn)
		list_container.add_child(row)


func _on_return_call_pressed(page: PendingPage) -> void:
	var customer: Customer = page.get_customer()
	if customer == null:
		return
	var meeting: Meeting = MeetingManager.schedule_meeting(customer, page.quantity_requested)
	if meeting == null:
		status_label.text = "No spots available right now."
		return
	PagerSystem.consume_page(page)
	status_label.text = "Meet %s at %s, %s." % [
		customer.display_name,
		MeetingManager.get_spot_display_name(meeting.spot_id),
		MeetingManager.format_minute(meeting.scheduled_minute),
	]
