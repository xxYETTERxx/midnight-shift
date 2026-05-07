extends Node

# Rent due day-of-week. 0=Mon, 6=Sun (matches TimeSystem.day_of_week()).
const RENT_DAY_OF_WEEK: int = 6   # Sunday
const WARN_DAY_OF_WEEK: int = 5   # Saturday — heads-up the day before

@export var weekly_rent: int = 100

# Strikes accumulate when the player can't pay on Sunday. 2 strikes = evicted.
# Eviction is wired but a no-op for MVP — just emits the signal and logs.
# Post-MVP: kicks player to shanty-town tent (per design doc §5).
var strikes: int = 0

signal rent_paid(amount: int)
signal rent_missed(amount_owed: int, total_strikes: int)
signal rent_due_warning(amount: int)
signal evicted()


func _ready() -> void:
	SaveSystem.register_savable("rent_system", self)
	TimeSystem.day_rolled.connect(_on_day_rolled)


func _on_day_rolled(dow: int, _dom: int) -> void:
	if dow == WARN_DAY_OF_WEEK:
		rent_due_warning.emit(weekly_rent)
		print("[Rent] Due tomorrow: $%d" % weekly_rent)
	elif dow == RENT_DAY_OF_WEEK:
		_collect()


func _collect() -> void:
	if Wallet.can_afford(weekly_rent):
		Wallet.spend(weekly_rent)
		strikes = 0  # paying clears the slate
		rent_paid.emit(weekly_rent)
		print("[Rent] Paid $%d" % weekly_rent)
	else:
		strikes += 1
		rent_missed.emit(weekly_rent, strikes)
		print("[Rent] MISSED. Strikes: %d/2" % strikes)
		if strikes >= 2:
			evicted.emit()
			print("[Rent] EVICTED (MVP: no consequence wired yet)")


# --- Save/load ---

func save_state() -> Dictionary:
	return {
		"strikes": strikes,
		"weekly_rent": weekly_rent,
	}


func load_state(data: Dictionary) -> void:
	strikes = data.get("strikes", 0)
	weekly_rent = data.get("weekly_rent", 100)
