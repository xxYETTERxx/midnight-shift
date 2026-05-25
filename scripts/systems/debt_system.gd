extends Node

# Tracks debts owed to vendors. Keyed by vendor_id.
# Interest: rolling 7 game-days from incurrence, +10% per week.
# Save-scoped: lives in the save file.

const WEEK_MINUTES: int = 7 * 24 * 60
const INTEREST_MULTIPLIER: float = 1.10

# vendor_id (String) -> { amount: int, last_interest_at_minute: int, creditor_name: String }
var _debts: Dictionary = {}

signal debt_incurred(vendor_id: StringName, amount: int)
signal debt_paid(vendor_id: StringName)
signal debt_changed(vendor_id: StringName, new_amount: int)


func _ready() -> void:
	SaveSystem.register_savable("debt_system", self)
	TimeSystem.day_rolled.connect(_on_day_rolled)


# --- Public API ---

func has_debt(vendor_id: StringName) -> bool:
	return _debts.has(String(vendor_id))


func amount(vendor_id: StringName) -> int:
	var key := String(vendor_id)
	if not _debts.has(key):
		return 0
	return _debts[key].amount


func creditor_name(vendor_id: StringName) -> String:
	var key := String(vendor_id)
	if not _debts.has(key):
		return ""
	return _debts[key].creditor_name


# Returns false if a debt already exists for this vendor (no stacking).
func incur(vendor_id: StringName, debt_amount: int, vendor_name: String) -> bool:
	if vendor_id == &"" or debt_amount <= 0:
		return false
	var key := String(vendor_id)
	if _debts.has(key):
		push_warning("DebtSystem: debt to %s already exists" % key)
		return false
	_debts[key] = {
		"amount": debt_amount,
		"last_interest_at_minute": TimeSystem.total_minutes,
		"creditor_name": vendor_name,
	}
	print("[Debt] Incurred $%d to %s" % [debt_amount, vendor_name])
	debt_incurred.emit(vendor_id, debt_amount)
	debt_changed.emit(vendor_id, debt_amount)
	return true


# Full payment only. Returns false if no debt or can't afford.
func pay(vendor_id: StringName) -> bool:
	var key := String(vendor_id)
	if not _debts.has(key):
		return false
	var owed: int = _debts[key].amount
	if not Wallet.can_afford(owed):
		return false
	if not Wallet.spend(owed):
		return false
	_debts.erase(key)
	print("[Debt] Paid $%d to %s" % [owed, vendor_id])
	debt_paid.emit(vendor_id)
	debt_changed.emit(vendor_id, 0)
	return true


# --- Interest ---

func _on_day_rolled(_dow: int, _dom: int) -> void:
	var now: int = TimeSystem.total_minutes
	for key in _debts.keys():
		var d: Dictionary = _debts[key]
		while now - d.last_interest_at_minute >= WEEK_MINUTES:
			var new_amount: int = int(round(d.amount * INTEREST_MULTIPLIER))
			# Guarantee at least +1 in pathological tiny-debt cases.
			if new_amount <= d.amount:
				new_amount = d.amount + 1
			d.amount = new_amount
			d.last_interest_at_minute += WEEK_MINUTES
			print("[Debt] Interest applied: %s now owes $%d" % [d.creditor_name, d.amount])
			debt_changed.emit(StringName(key), d.amount)


# --- Save/load ---

func save_state() -> Dictionary:
	return {
		"debts": _debts.duplicate(true),
	}


func load_state(data: Dictionary) -> void:
	_debts = data.get("debts", {}).duplicate(true)
