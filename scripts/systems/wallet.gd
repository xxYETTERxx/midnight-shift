extends Node

# Multi-pool wallet (per design doc §5). MVP only uses "cash". Future pools
# include "clean" (banked/checks for catalogue mail-order) and any laundering
# bookkeeping. All read/write APIs take a pool name defaulting to "cash" so
# the dirty/clean expansion is additive, not a refactor.

const STARTING_CASH: int = 0

var _pools: Dictionary = {"cash": STARTING_CASH}

signal balance_changed(pool: String, new_balance: int)


func _ready() -> void:
	SaveSystem.register_savable("wallet", self)


func balance(pool: String = "cash") -> int:
	return _pools.get(pool, 0)


func can_afford(amount: int, pool: String = "cash") -> bool:
	return balance(pool) >= amount


func add(amount: int, pool: String = "cash") -> void:
	if amount == 0:
		return
	_pools[pool] = max(0, balance(pool) + amount)
	balance_changed.emit(pool, _pools[pool])


# Returns true if the spend succeeded (sufficient balance).
func spend(amount: int, pool: String = "cash") -> bool:
	if amount < 0:
		push_warning("Wallet.spend called with negative amount; use add() instead")
		return false
	if not can_afford(amount, pool):
		return false
	_pools[pool] = balance(pool) - amount
	balance_changed.emit(pool, _pools[pool])
	return true


func format_balance(pool: String = "cash") -> String:
	return "$%d" % balance(pool)


# --- Save/load ---

func save_state() -> Dictionary:
	return {"pools": _pools.duplicate()}


func load_state(data: Dictionary) -> void:
	_pools = data.get("pools", {"cash": STARTING_CASH}).duplicate()
	for pool in _pools:
		balance_changed.emit(pool, _pools[pool])
