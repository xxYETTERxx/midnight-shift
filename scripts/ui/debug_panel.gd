extends CanvasLayer

# Dev debug overlay, built entirely in code (no scene dependency). Toggle from
# player input (F2). Polls live system state each frame. Best-guess API calls —
# fix the right side of each line in the section builders to match real
# accessors; _safe() degrades a wrong guess to "?" instead of crashing.

var _label: Label
var _visible: bool = false


func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.position = Vector2(20, 20)
	_label.add_theme_font_size_override("font_size", 10)
	add_child(_label)
	visible = false


func toggle() -> void:
	_visible = not _visible
	visible = _visible


func _process(_delta: float) -> void:
	if not _visible:
		return
	_label.text = _section_skills() + "\n" + _section_heat()


# --- Sections (plain text now — no BBCode) ------------------------------

func _section_skills() -> String:
	var s: String = "== SKILLS ==\n"
	s += _skill_line("Strength", &"strength")
	s += _skill_line("Athletics", &"athletics")
	s += _skill_line("Lockpicking", &"lockpicking")
	s += "DealerXP    %s  (tier %s)\n" % [
		_safe(func(): return DealerExperience.xp),
		_safe(func(): return DealerExperience.current_tier()),
	]
	s += "CriminalXP  %s  (tier %s)\n" % [
		_safe(func(): return CriminalExperience.xp),
		_safe(func(): return CriminalExperience.current_tier()),
	]
	return s


func _section_heat() -> String:
	var s: String = "== HEAT ==\n"
	var area: StringName = _current_area()
	s += "Area        %s\n" % String(area)
	s += "Area Heat   %s  (band %s)\n" % [
		_safe(func(): return "%.1f" % HeatSystem.get_heat(area)),
		_safe(func(): return HeatSystem.get_heat_band(area)),
	]
	s += "Cops        %s\n" % _safe(func(): return PoliceSystem._cops.size())
	s += "Suspicion   %s  (band %s)\n" % [
		_safe(func(): return "%.1f" % SuspicionSystem._suspicion),
		_safe(func(): return SuspicionSystem.band()),
	]
	s += "  perm rec  %s\n" % _safe(func(): return "%.1f" % SuspicionSystem.permanent_record())
	s += "Ledger      %s susp / %s conf\n" % [
		_safe(func(): return CrimeSystem.suspected_count()),
		_safe(func(): return CrimeSystem.confirmed_count()),
	]
	return s


# --- Helpers ------------------------------------------------------------

func _skill_line(label: String, skill_id: StringName) -> String:
	return "%-11s L%s  xp=%s\n" % [
		label,
		_safe(func(): return PlayerSkills.tier(skill_id)),
		_safe(func(): return PlayerSkills.value(skill_id)),
	]


func _current_area() -> StringName:
	if RoomManager.current_room == null:
		return &"<none>"
	return StringName(RoomManager.current_room.scene_file_path.get_file().get_basename())


func _safe(getter: Callable) -> String:
	var result = getter.call()
	if result == null:
		return "?"
	return str(result)
