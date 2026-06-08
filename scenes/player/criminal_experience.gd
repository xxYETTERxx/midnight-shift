extends Node

# Player's criminal track. Earns XP on every committed crime (car looting
# initially, plus pickpocket / B&E later). Tiers unlock criminal-track
# tools at the Fence: tier 1 = slim jim, tier 2 = electronics kit, tier 3 = chop shop.

var xp: int = 0

const TIER_THRESHOLDS: Array[int] = [0, 30, 100, 250]

signal xp_changed(new_xp: int)
signal tier_unlocked(tier: int)


func _ready() -> void:
	SaveSystem.register_savable("criminal_experience", self)


func current_tier() -> int:
	var t := 0
	for i in range(TIER_THRESHOLDS.size()):
		if xp >= TIER_THRESHOLDS[i]:
			t = i
		else:
			break
	return t


func max_tier() -> int:
	return TIER_THRESHOLDS.size() - 1


func adjust(delta: int) -> void:
	if delta == 0:
		return
	var prev_tier := current_tier()
	xp = max(0, xp + delta)
	xp_changed.emit(xp)
	# Criminal activity sharpens awareness. Scaled to the crime's XP value so
	# bigger jobs sharpen you more. Only on gains, not deductions.
	if delta > 0:
		PlayerSkills.adjust(&"awareness", delta)
	var new_tier := current_tier()
	if new_tier > prev_tier:
		for t in range(prev_tier + 1, new_tier + 1):
			tier_unlocked.emit(t)


func save_state() -> Dictionary:
	return {"xp": xp}


func load_state(data: Dictionary) -> void:
	xp = data.get("xp", 0)
	xp_changed.emit(xp)
