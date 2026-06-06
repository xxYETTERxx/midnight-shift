extends Node
class_name LedgerSystemType
# LedgerSystem — weekly recurring cash-flow ledger.
#
# Holds signed weekly line items ("entries"). Negative weekly_amount = expense,
# positive = income (e.g. simple property rent you collect). Entries are
# registered by whoever owns the acquisition — a progression flag (apartment,
# pager) or a component at purchase/placement (front, grow light) — and persist
# centrally so settlement never needs the source's room loaded.
#
# Settlement runs once a week (Sunday), STAGED: all income is credited to the
# Wallet first, then each EXPENSE category is debited on its own, so a category
# you can't cover still strikes even if your net week was positive. The ledger
# reports per-category results; owning systems decide consequences.
#
# Out of scope (by design): business/staff internals. Those systems compute a
# weekly dollar figure elsewhere and write it here via set_entry_amount().

# Day-of-week cadence. TimeSystem.day_of_week(): 0=Mon … 6=Sun. week_rolled
# fires on the roll INTO dow 0, so dow 6 is the last day of the week.
const SETTLE_DAY_OF_WEEK: int = 6   # Sunday — collect/settle
const WARN_DAY_OF_WEEK: int = 5     # Saturday — heads-up the day before

# entry_id (String) -> {
#   "category": StringName,   # "housing" | "pager" | "laundering_upkeep" | "utilities" | "property_income" ...
#   "weekly_amount": int,     # signed per-unit: negative = expense, positive = income
#   "count": int,             # multiplier (1 for flags; N for grow lights / staff heads)
#   "label": String,          # for UI / weekly summary
# }
var _entries: Dictionary = {}

# Per-category expense strike counters. Owning systems define what strikes mean.
var _strikes: Dictionary = {}   # category(String) -> int

# Emitted Saturday with the upcoming Sunday breakdown.
#   expense_total: int (positive number owed)
#   income_total: int
#   by_category: { category(String): signed_total }
signal week_due_warning(expense_total: int, income_total: int, by_category: Dictionary)
# Per income category actually credited at settlement.
signal income_paid(category: StringName, amount: int)
# Per expense category paid in full.
signal expense_paid(category: StringName, amount: int)
# Per expense category the player couldn't cover.
signal expense_missed(category: StringName, amount_owed: int, strikes: int)
# Fired once after a full settlement with the complete breakdown (weekly summary).
signal week_settled(summary: Dictionary)

signal net_changed(net_weekly: int)


func _ready() -> void:
	SaveSystem.register_savable("ledger", self)
	TimeSystem.day_rolled.connect(_on_day_rolled)


# --- Registration (called at acquisition / purchase / placement) --------

# Register or overwrite an entry. weekly_amount is SIGNED.
func set_entry(entry_id: StringName, category: StringName, weekly_amount: int, label: String = "", count: int = 1) -> void:
	_entries[String(entry_id)] = {
		"category": category,
		"weekly_amount": weekly_amount,
		"count": count,
		"label": label,
	}
	_notify_changed()


func remove_entry(entry_id: StringName) -> void:
	_entries.erase(String(entry_id))
	_notify_changed()


func has_entry(entry_id: StringName) -> bool:
	return _entries.has(String(entry_id))


# Update just the signed amount of an existing entry (e.g. a business system
# writing this week's net property income). No-op if the entry doesn't exist.
func set_entry_amount(entry_id: StringName, weekly_amount: int) -> void:
	var key := String(entry_id)
	if _entries.has(key):
		_entries[key]["weekly_amount"] = weekly_amount
	_notify_changed()


# Update the multiplier for a scaling entry (grow lights placed/removed, staff
# hired/fired). count <= 0 removes the entry entirely.
func set_entry_count(entry_id: StringName, count: int) -> void:
	var key := String(entry_id)
	if not _entries.has(key):
		return
	if count <= 0:
		_entries.erase(key)
		_notify_changed()
	else:
		_entries[key]["count"] = count
	_notify_changed()


# --- Aggregation --------------------------------------------------------

# category(String) -> signed total (negative = net expense, positive = income)
func _category_signed_totals() -> Dictionary:
	var totals: Dictionary = {}
	for rec in _entries.values():
		var cat := String(rec["category"])
		totals[cat] = totals.get(cat, 0) + rec["weekly_amount"] * rec["count"]
	return totals


# Sum of all negative category totals, returned as a positive "owed" figure.
func expense_total() -> int:
	var owed := 0
	for v in _category_signed_totals().values():
		if v < 0:
			owed += -v
	return owed


# Sum of all positive category totals.
func income_total() -> int:
	var inc := 0
	for v in _category_signed_totals().values():
		if v > 0:
			inc += v
	return inc


func strikes_for(category: StringName) -> int:
	return _strikes.get(String(category), 0)


func clear_strikes(category: StringName) -> void:
	_strikes[String(category)] = 0


# --- Weekly cadence -----------------------------------------------------

func _on_day_rolled(dow: int, _dom: int) -> void:
	if dow == WARN_DAY_OF_WEEK:
		var totals := _category_signed_totals()
		var exp := expense_total()
		var inc := income_total()
		if exp > 0 or inc > 0:
			week_due_warning.emit(exp, inc, totals)
	elif dow == SETTLE_DAY_OF_WEEK:
		_settle()


# Staged settlement: credit income first, then debit each expense category.
func _settle() -> void:
	var totals := _category_signed_totals()

	var income_results: Dictionary = {}   # category -> credited
	var expense_results: Dictionary = {}  # category -> { owed, paid: bool, strikes }

	# Pass 1 — credit all income to the Wallet.
	for cat in totals:
		var signed: int = totals[cat]
		if signed > 0:
			Wallet.add(signed)
			income_results[cat] = signed
			income_paid.emit(StringName(cat), signed)

	# Pass 2 — debit each expense category independently.
	for cat in totals:
		var signed: int = totals[cat]
		if signed >= 0:
			continue
		var owed: int = -signed
		if Wallet.can_afford(owed):
			Wallet.spend(owed)
			_strikes[cat] = 0
			expense_results[cat] = { "owed": owed, "paid": true, "strikes": 0 }
			expense_paid.emit(StringName(cat), owed)
		else:
			_strikes[cat] = _strikes.get(cat, 0) + 1
			expense_results[cat] = { "owed": owed, "paid": false, "strikes": _strikes[cat] }
			expense_missed.emit(StringName(cat), owed, _strikes[cat])

	week_settled.emit({
		"income": income_results,
		"expenses": expense_results,
		"income_total": income_total(),
		"expense_total": expense_total(),
	})
	_notify_changed()

func net_weekly() -> int:
	var net := 0
	for v in _category_signed_totals().values():
		net += v
	return net
	
func _notify_changed() -> void:
	net_changed.emit(net_weekly())

# --- Save / load --------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"entries": _entries.duplicate(true),
		"strikes": _strikes.duplicate(true),
	}


func load_state(data: Dictionary) -> void:
	_entries = data.get("entries", {}).duplicate(true)
	_strikes = data.get("strikes", {}).duplicate(true)
	_notify_changed()
