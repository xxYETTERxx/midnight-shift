extends Node

# Scratch-ticket resolver. Called from player.gd's tool dispatch when the
# player uses a scratch ticket. Pays out directly to Wallet and fires the
# notification. Caller is responsible for consuming the ticket from inventory.

const PRIZE_TABLE_PATH := "res://data/loot_tables/lottery_prize_table.tres"

@export var prize_table: LotteryPrizeTable

var total_scratched: int = 0
var total_won: int = 0
var biggest_win: int = 0

signal ticket_scratched(prize: int, was_first_ticket: bool)


func _ready() -> void:
	if prize_table == null:
		prize_table = load(PRIZE_TABLE_PATH)
	SaveSystem.register_savable("lottery", self)


func scratch() -> int:
	if prize_table == null:
		push_warning("LotterySystem: no prize_table assigned")
		return 0

	var was_first := (total_scratched == 0)
	var prize: int = 0

	if was_first and prize_table.first_ticket_guaranteed_prize > 0:
		prize = prize_table.first_ticket_guaranteed_prize
	else:
		prize = prize_table.roll()

	total_scratched += 1
	print(prize)
	if prize > 0:
		total_won += prize
		biggest_win = max(biggest_win, prize)
		Wallet.add(prize)
		if prize >= 1000:
			pass
			NotificationSystem.warn("JACKPOT! Won $%d!" % prize)
		else:
			pass
			NotificationSystem.warn("Won $%d!" % prize)
	else:
		pass
		NotificationSystem.warn("No win.")

	ticket_scratched.emit(prize, was_first)
	return prize


func save_state() -> Dictionary:
	return {
		"total_scratched": total_scratched,
		"total_won": total_won,
		"biggest_win": biggest_win,
	}


func load_state(data: Dictionary) -> void:
	total_scratched = data.get("total_scratched", 0)
	total_won = data.get("total_won", 0)
	biggest_win = data.get("biggest_win", 0)
