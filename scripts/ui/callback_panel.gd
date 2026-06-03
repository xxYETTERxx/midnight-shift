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
	CourtSummons.court_paged.connect(_on_court_changed)
	CourtSummons.court_confirmed.connect(_on_court_confirmed)
	CourtSummons.court_resolved.connect(_on_court_changed)


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


func _on_court_changed() -> void:
	if _is_open:
		_rebuild_list()


func _on_court_confirmed(_court_minute: int) -> void:
	if _is_open:
		_rebuild_list()


func _rebuild_list() -> void:
	for c in list_container.get_children():
		c.queue_free()

	# Court summons sits at the top — an Unknown caller. Only shown while the
	# date hasn't been acknowledged yet (PAGED, not CONFIRMED).
	var has_court_row: bool = CourtSummons.has_pending() and not CourtSummons.can_attend()
	if has_court_row:
		_add_court_row()

	var pages := PagerSystem.pending_pages()
	if pages.is_empty() and not has_court_row:
		var lbl := Label.new()
		lbl.text = "No messages."
		list_container.add_child(lbl)
		return

	for p in pages:
		var customer: Customer = p.get_customer()
		if customer == null:
			continue
		var entry := VBoxContainer.new()

		var top := HBoxContainer.new()
		var info := Label.new()
		info.text = "%s — wants %d  (%dm left)" % [
			customer.display_name, p.quantity_requested, p.minutes_remaining,
		]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		top.add_child(info)
		var btn := Button.new()
		btn.text = "Return Call"
		btn.pressed.connect(_on_return_call_pressed.bind(p))
		top.add_child(btn)
		entry.add_child(top)

		if customer.default_dialogue != "":
			var quote := Label.new()
			quote.text = "  \"%s\"" % customer.default_dialogue
			quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			quote.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			entry.add_child(quote)

		list_container.add_child(entry)


# The court row: no customer, no quantity, no time-picker. Returning the call
# spends a card and confirms the imposed date outright.
func _add_court_row() -> void:
	var entry := VBoxContainer.new()

	var top := HBoxContainer.new()
	var info := Label.new()
	info.text = "UNKNOWN CALLER"
	info.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 1.0))
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(info)
	var btn := Button.new()
	btn.text = "Return Call"
	btn.pressed.connect(_on_return_court_call_pressed)
	top.add_child(btn)
	entry.add_child(top)

	list_container.add_child(entry)


func _on_return_call_pressed(page: PendingPage) -> void:
	if not CallingCardSystem.try_spend(1):
		return
	var customer: Customer = page.get_customer()
	if customer == null:
		return
	var picker: Node = get_tree().get_first_node_in_group("time_picker_panel")
	if picker == null or not picker.has_method("open_for"):
		push_warning("CallbackPanel: no time_picker_panel in scene tree")
		status_label.text = "Can't set up a meet right now."
		return
	# Close ourselves (releasing our time pause) and hand off to the picker,
	# which owns the pause for the rest of the flow. Consume the page only
	# once a meeting actually commits.
	close()
	picker.open_for(customer, page.quantity_requested, _make_commit_callback(page))


func _make_commit_callback(page: PendingPage) -> Callable:
	return func() -> void:
		PagerSystem.consume_page(page)


func _on_return_court_call_pressed() -> void:
	if not CallingCardSystem.try_spend(1):
		status_label.text = "You need a calling card to make that call."
		return
	# Court time is imposed — no picker. Returning the call just confirms.
	CourtSummons.return_call()
	# The row vanishes on rebuild (state moves PAGED → CONFIRMED). Stay open so
	# the player reads the confirmation; CourtSummons already notified the time.
	_rebuild_list()
