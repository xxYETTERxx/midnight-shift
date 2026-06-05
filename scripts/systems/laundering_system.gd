extends Node

# Owns laundering-channel state. For now that's just the single bank account
# (the ATM is one prop, one account). Fronts will register here later as
# additional channels; the bank is a built-in singular channel that needs no
# roster.
#
# Channels compute their own dollar overage (the newly-over slice this week)
# and hand it to SuspicionSystem, which owns the overage->suspicion formula.
# This autoload speaks dollars; SuspicionSystem speaks suspicion.

const BANK_WEEKLY_CAP: int = 200

# Dirty cash cleaned through the bank this calendar week. Reset on week roll.
# Lives here (not on the ATM prop) so it survives room rebuilds and saves.
var _bank_cleaned_this_week: int = 0

# Owned fronts: front_id -> { cap: int, cleaned_this_week: int }. Ownership +
# weekly tally are durable (saved); the building's max_limit is copied in at
# purchase so the capacity sum works even when the front's room is unloaded.
var _fronts: Dictionary = {}


func _ready() -> void:
	SaveSystem.register_savable("laundering", self)
	TimeSystem.week_rolled.connect(_on_week_rolled)


# --- Bank channel (the ATM) --------------------------------------------

func bank_weekly_cap() -> int:
	return BANK_WEEKLY_CAP


func bank_cleaned_this_week() -> int:
	return _bank_cleaned_this_week


func bank_remaining_capacity() -> int:
	return max(0, BANK_WEEKLY_CAP - _bank_cleaned_this_week)


# Clean (deposit) dirty cash through the bank. Moves the money via Wallet,
# tracks the weekly tally, and reports any newly-over portion to
# SuspicionSystem. Returns { ok, deposited, overage } for the ATM panel.
func clean_through_bank(amount: int) -> Dictionary:
	if amount <= 0:
		return {"ok": false, "deposited": 0, "overage": 0}
	if not Wallet.deposit(amount):
		return {"ok": false, "deposited": 0, "overage": 0}

	# Charge overage only on the slice of THIS deposit above the cap — never
	# recompute against the running total (that would re-charge overage already
	# paid for earlier this week).
	var before: int = max(BANK_WEEKLY_CAP, _bank_cleaned_this_week)
	var after: int = _bank_cleaned_this_week + amount
	var overage: int = clampi(after - before, 0, amount)

	_bank_cleaned_this_week = after

	if overage > 0:
		SuspicionSystem.report_overage(overage, BANK_WEEKLY_CAP)

	return {"ok": true, "deposited": amount, "overage": overage}


# Called when the player buys a front. Idempotent — re-registering an already
# owned front is a no-op (you can't buy it twice).
func register_front(front_id: StringName, max_limit: int) -> bool:
	var key := String(front_id)
	if _fronts.has(key):
		return false
	_fronts[key] = { "cap": max_limit, "cleaned_this_week": 0 }
	return true


func owns_front(front_id: StringName) -> bool:
	return _fronts.has(String(front_id))


func front_cap(front_id: StringName) -> int:
	var key := String(front_id)
	return _fronts[key]["cap"] if _fronts.has(key) else 0


func front_cleaned_this_week(front_id: StringName) -> int:
	var key := String(front_id)
	return _fronts[key]["cleaned_this_week"] if _fronts.has(key) else 0


func front_remaining_capacity(front_id: StringName) -> int:
	var key := String(front_id)
	if not _fronts.has(key):
		return 0
	return max(0, _fronts[key]["cap"] - _fronts[key]["cleaned_this_week"])


# Clean dirty cash through an owned front. Same overage rule as the bank:
# charge only the newly-over slice this week.
func clean_through_front(front_id: StringName, amount: int) -> Dictionary:
	var key := String(front_id)
	if not _fronts.has(key):
		return {"ok": false, "deposited": 0, "overage": 0}
	if amount <= 0:
		return {"ok": false, "deposited": 0, "overage": 0}
	if not Wallet.deposit(amount):
		return {"ok": false, "deposited": 0, "overage": 0}

	var rec: Dictionary = _fronts[key]
	var cap: int = rec["cap"]
	var before: int = max(cap, rec["cleaned_this_week"])
	var after: int = rec["cleaned_this_week"] + amount
	var overage: int = clampi(after - before, 0, amount)
	rec["cleaned_this_week"] = after

	if overage > 0:
		SuspicionSystem.report_overage(overage, cap)

	return {"ok": true, "deposited": amount, "overage": overage}


func _on_week_rolled(_week: int) -> void:
	_bank_cleaned_this_week = 0
	for key in _fronts:
		_fronts[key]["cleaned_this_week"] = 0

func total_weekly_capacity() -> int:
	var total: int = BANK_WEEKLY_CAP
	for key in _fronts:
		total += _fronts[key]["cap"]
	return total

# --- Save / load -------------------------------------------------------

func save_state() -> Dictionary:
	return {
		"bank_cleaned_this_week": _bank_cleaned_this_week,
		"fronts": _fronts.duplicate(true),
	}


func load_state(data: Dictionary) -> void:
	_bank_cleaned_this_week = int(data.get("bank_cleaned_this_week", 0))
	_fronts = data.get("fronts", {}).duplicate(true)
