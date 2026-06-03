class_name ATM
extends Node2D

# A laundering channel: converts dirty "cash" into clean "clean" against a
# weekly cap. Depositing under the cap is clean money, no suspicion. Depositing
# over the cap still succeeds (dirty must stay spendable — we never hard-block),
# but the over-portion is reported to SuspicionSystem as proportional overage.
#
# This is the ATM channel: there is ONE bank account, so the weekly tally is a
# single shared value persisted here regardless of how many ATM props exist.
# Fronts will reuse this exact pattern with a larger cap and PER-INSTANCE tally.
#
# Withdraw (clean -> cash) is unmetered: pulling your own banked money back out
# is not a laundering event.

# Comically low on purpose — the ATM is a trickle, not a solution. Fronts are
# how you actually launder at volume.
const WEEKLY_CAP: int = 200

@onready var interactable: Interactable = $Interactable

# Dirty cash cleaned through the bank so far this calendar week. Reset on the
# week roll. Persisted — leaving the room must not wipe the tally.
var _cleaned_this_week: int = 0


func _ready() -> void:
	SaveSystem.register_savable("atm_channel", self)
	interactable.interacted.connect(_on_interacted)
	TimeSystem.week_rolled.connect(_on_week_rolled)


func _on_interacted(player: Node) -> void:
	var panel := get_tree().get_first_node_in_group("atm_panel")
	if panel == null:
		push_warning("ATM: no atm_panel in scene")
		return
	panel.open(player, self)


# --- Channel API (called by the panel) ---

func weekly_cap() -> int:
	return WEEKLY_CAP


func cleaned_this_week() -> int:
	return _cleaned_this_week


func remaining_capacity() -> int:
	return max(0, WEEKLY_CAP - _cleaned_this_week)


# Clean (deposit) dirty cash into the bank. Always succeeds if the player has
# the cash. Returns { ok, deposited, overage } so the panel can show the
# "this may flag your account" line when overage > 0.
func clean(amount: int) -> Dictionary:
	if amount <= 0:
		return {"ok": false, "deposited": 0, "overage": 0}
	if not Wallet.deposit(amount):
		# Not enough dirty cash on hand.
		return {"ok": false, "deposited": 0, "overage": 0}

	# Charge suspicion ONLY on the slice of THIS deposit that landed above the
	# cap, never recomputing against the running total (that would re-charge
	# overage already paid for earlier this week).
	#   before = max(cap, cleaned_before)  -> if already over, the whole deposit is over
	var before: int = max(WEEKLY_CAP, _cleaned_this_week)
	var after: int = _cleaned_this_week + amount
	var overage: int = clampi(after - before, 0, amount)

	_cleaned_this_week = after

	if overage > 0:
		SuspicionSystem.report_overage(overage, WEEKLY_CAP)

	return {"ok": true, "deposited": amount, "overage": overage}


func _on_week_rolled(_week: int) -> void:
	_cleaned_this_week = 0


# --- Save / load ---

func save_state() -> Dictionary:
	return {"cleaned_this_week": _cleaned_this_week}


func load_state(data: Dictionary) -> void:
	_cleaned_this_week = int(data.get("cleaned_this_week", 0))
