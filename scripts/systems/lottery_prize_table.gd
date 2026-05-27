class_name LotteryPrizeTable
extends Resource

# Prize tiers, ordered worst-to-best. Walked in REVERSE on roll() so jackpot
# gets first crack at the dice. Independent probabilities -- don't need to
# sum to anything. Tune in inspector.

@export var prize_amounts: Array[int] = [1, 2, 5, 20, 100, 10000]
@export var prize_chances: Array[float] = [0.30, 0.15, 0.08, 0.02, 0.002, 0.000003]

# Bypass-the-table prize on the player's first scratched ticket. 0 = disabled.
@export var first_ticket_guaranteed_prize: int = 5


func roll() -> int:
	for i in range(prize_amounts.size() - 1, -1, -1):
		var chance: float = prize_chances[i] if i < prize_chances.size() else 0.0
		if chance <= 0.0:
			continue
		if randf() < chance:
			return prize_amounts[i]
	return 0


func expected_value() -> float:
	var ev: float = 0.0
	for i in range(prize_amounts.size()):
		var chance: float = prize_chances[i] if i < prize_chances.size() else 0.0
		ev += float(prize_amounts[i]) * chance
	return ev
