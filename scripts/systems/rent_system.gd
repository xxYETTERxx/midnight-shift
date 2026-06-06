extends Node
# RentSystem — housing facade over LedgerSystem. Owns the "housing" category:
# registers apartment rent entries, tracks eviction, and re-emits the legacy
# rent_* signals the HUD already listens to. Real settlement happens in the
# ledger; this just reacts to housing-category results.

const HOUSING_CATEGORY: StringName = &"housing"
const APT1_ENTRY: StringName = &"apartment_1"
const APT2_ENTRY: StringName = &"apartment_2"

@export var weekly_rent: int = 100   # per-apartment weekly rent

var strikes: int = 0   # mirrors ledger's housing strikes for HUD/eviction

signal rent_paid(amount: int)
signal rent_missed(amount_owed: int, total_strikes: int)
signal rent_due_warning(amount: int)
signal evicted()


func _ready() -> void:
	SaveSystem.register_savable("rent_system", self)
	LedgerSystem.week_due_warning.connect(_on_week_due_warning)
	LedgerSystem.expense_paid.connect(_on_expense_paid)
	LedgerSystem.expense_missed.connect(_on_expense_missed)


# --- Apartment ownership (progression flags) ----------------------------

func rent_first_apartment() -> void:
	LedgerSystem.set_entry(APT1_ENTRY, HOUSING_CATEGORY, -weekly_rent, "Apartment rent")


func rent_second_apartment() -> void:
	LedgerSystem.set_entry(APT2_ENTRY, HOUSING_CATEGORY, -weekly_rent, "Second apartment rent")


# --- Ledger reactions ---------------------------------------------------

func _on_week_due_warning(_expense_total: int, _income_total: int, by_category: Dictionary) -> void:
	var housing: int = by_category.get(String(HOUSING_CATEGORY), 0)
	if housing < 0:
		rent_due_warning.emit(-housing)
		print("[Rent] Due tomorrow: $%d" % -housing)


func _on_expense_paid(category: StringName, amount: int) -> void:
	if category != HOUSING_CATEGORY:
		return
	strikes = 0
	rent_paid.emit(amount)
	print("[Rent] Paid $%d" % amount)


func _on_expense_missed(category: StringName, amount_owed: int, total_strikes: int) -> void:
	if category != HOUSING_CATEGORY:
		return
	strikes = total_strikes
	rent_missed.emit(amount_owed, strikes)
	print("[Rent] MISSED. Strikes: %d/2" % strikes)
	if strikes >= 2:
		evicted.emit()
		print("[Rent] EVICTED (MVP: no consequence wired yet)")


# --- Save/load ---

func save_state() -> Dictionary:
	return { "strikes": strikes, "weekly_rent": weekly_rent }


func load_state(data: Dictionary) -> void:
	strikes = data.get("strikes", 0)
	weekly_rent = data.get("weekly_rent", 100)
