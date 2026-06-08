extends Node

# Multi-pool wallet (design doc §5, §25.3).
#
# Two pools with a STRICT domain split:
#   "cash"  — dirty money (dealing, crime). Spends ONLY in the informal
#             economy: vendors, Hank, gas station, gifts. Cannot pay formal
#             gates (rent, property, mail-order).
#   "clean" — banked money. Spends ONLY at formal gates. Cannot be spent in
#             the informal economy.
#
# The pools never compete for the same purchase, so there is no cross-pool
# fallback. Each spend names its pool explicitly; callers that pick the wrong
# pool simply fail can_afford() against an empty pool, which is the intended
# gate behaviour.
#
# Movement between pools happens ONLY through the ATM (deposit/withdraw),
# which is the single laundering seam for later (§25.3 scrutiny hook).

const POOL_CASH: String = "cash"
const POOL_CLEAN: String = "clean"

const STARTING_CASH: int = 10000
const STARTING_CLEAN: int = 10000

var _pools: Dictionary = {
	POOL_CASH: STARTING_CASH,
	POOL_CLEAN: STARTING_CLEAN,
}

signal balance_changed(pool: String, new_balance: int)


func _ready() -> void:
	SaveSystem.register_savable("wallet", self)


# --- Reads ---

func balance(pool: String = POOL_CASH) -> int:
	return _pools.get(pool, 0)


func can_afford(amount: int, pool: String = POOL_CASH) -> bool:
	return balance(pool) >= amount


# Total across all pools — display / debug only. Never use for affordability
# of a real purchase; purchases are pool-scoped by design.
func net_worth() -> int:
	var total: int = 0
	for pool in _pools:
		total += _pools[pool]
	return total


# --- Writes ---

func add(amount: int, pool: String = POOL_CASH) -> void:
	if amount == 0:
		return
	_pools[pool] = max(0, balance(pool) + amount)
	balance_changed.emit(pool, _pools[pool])


# Returns true if the spend succeeded (sufficient balance in that pool).
func spend(amount: int, pool: String = POOL_CASH) -> bool:
	if amount < 0:
		push_warning("Wallet.spend called with negative amount; use add() instead")
		return false
	if not can_afford(amount, pool):
		return false
	_pools[pool] = balance(pool) - amount
	balance_changed.emit(pool, _pools[pool])
	return true


# --- Pool transfers (ATM only) ---
# These are the ONLY sanctioned path between dirty and clean. Plain banking
# for now: 1:1, no fee, no questions. Later, the scrutiny model hooks into
# deposit() (large/sudden deposits raise suspicion).

# Move dirty cash into the bank. Returns true on success.
func deposit(amount: int) -> bool:
	if amount <= 0:
		return false
	if not spend(amount, POOL_CASH):
		return false
	add(amount, POOL_CLEAN)
	# SCRUTINY HOOK (§25.3): future — large/frequent deposits raise suspicion.
	return true


# Pull bank money back out as spendable dirty cash. Returns true on success.
func withdraw(amount: int) -> bool:
	if amount <= 0:
		return false
	if not spend(amount, POOL_CLEAN):
		return false
	add(amount, POOL_CASH)
	return true


# --- Display ---

func format_balance(pool: String = POOL_CASH) -> String:
	return "$%d" % balance(pool)


# --- Save/load ---

func save_state() -> Dictionary:
	return {"pools": _pools.duplicate()}


func load_state(data: Dictionary) -> void:
	var loaded: Dictionary = data.get("pools", {})
	# Heal: ensure both canonical pools always exist after load.
	_pools = {
		POOL_CASH: int(loaded.get(POOL_CASH, STARTING_CASH)),
		POOL_CLEAN: int(loaded.get(POOL_CLEAN, STARTING_CLEAN)),
	}
	# Preserve any other pools a future version may have added.
	for pool in loaded:
		if not _pools.has(pool):
			_pools[pool] = int(loaded[pool])
	for pool in _pools:
		balance_changed.emit(pool, _pools[pool])
