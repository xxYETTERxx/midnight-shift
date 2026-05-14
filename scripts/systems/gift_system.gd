extends Node

# Loads per-NPC gift preferences and grades gift-giving attempts.
# Inline reaction dialogue is the caller's responsibility (gift_panel triggers
# it); GiftSystem just resolves the tier, delta, and line.

const PREFS_DIR: String = "res://data/gifts/"

enum Tier { HATE, DISLIKE, NEUTRAL, LIKE, LOVE, PERFECT }

const TIER_DELTAS: Dictionary = {
	Tier.HATE:    -40,
	Tier.DISLIKE: -20,
	Tier.NEUTRAL:   0,
	Tier.LIKE:     20,
	Tier.LOVE:     80,
	Tier.PERFECT: 200,
}

# Fallback reaction lines if neither the per-NPC override nor a special case
# applies. NEUTRAL is intentionally "Thanks." per design.
const DEFAULT_LINES: Dictionary = {
	Tier.HATE:    "Why would you give me this?",
	Tier.DISLIKE: "Uh... thanks, I guess.",
	Tier.NEUTRAL: "Thanks.",
	Tier.LIKE:    "Hey, this is great. Thanks.",
	Tier.LOVE:    "Wow. You really get me. Thank you.",
	Tier.PERFECT: "...I don't know what to say. This means everything.",
}

# npc_id (String) -> {category_to_tier: Dictionary, lines: Dictionary}
var _prefs: Dictionary = {}

signal gift_given(npc_id: String, item_id: StringName, tier: int)
signal perfect_gift_given(npc_id: String, item_id: StringName)


func _ready() -> void:
	_load_preferences()


# --- Loading ---

func _load_preferences() -> void:
	_prefs.clear()
	var dir := DirAccess.open(PREFS_DIR)
	if dir == null:
		push_warning("GiftSystem: %s not found — no preferences loaded" % PREFS_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			var res := load(PREFS_DIR + fname)
			if res is GiftPreferences:
				_register(res)
		fname = dir.get_next()
	dir.list_dir_end()
	print("[GiftSystem] loaded %d preference set(s)" % _prefs.size())


func _register(prefs: GiftPreferences) -> void:
	if prefs.npc_id == "":
		push_warning("GiftSystem: preference file has empty npc_id — skipped")
		return
	var category_map: Dictionary = {}
	for cat in prefs.like_categories:
		category_map[cat] = Tier.LIKE
	for cat in prefs.love_categories:
		category_map[cat] = Tier.LOVE
	for cat in prefs.dislike_categories:
		category_map[cat] = Tier.DISLIKE
	for cat in prefs.hate_categories:
		category_map[cat] = Tier.HATE
	var lines: Dictionary = {
		Tier.HATE:    prefs.hate_line,
		Tier.DISLIKE: prefs.dislike_line,
		Tier.NEUTRAL: prefs.neutral_line,
		Tier.LIKE:    prefs.like_line,
		Tier.LOVE:    prefs.love_line,
		Tier.PERFECT: prefs.perfect_line,
	}
	_prefs[String(prefs.npc_id)] = {
		"category_to_tier": category_map,
		"lines": lines,
	}


# --- Public API ---

# Returns true if this NPC has not received a gift today.
func can_receive_gift(npc_id: String) -> bool:
	return RelationshipSystem.can_receive_gift(npc_id)


# Grades the gift, applies the affinity delta, records cooldown, emits signals,
# returns a result dict { tier, delta, line } for the caller to display.
func give_gift(npc_id: String, item: ItemDef) -> Dictionary:
	var tier: int = _grade(npc_id, item)
	var delta: int = TIER_DELTAS[tier]
	var line: String = _resolve_line(npc_id, tier)

	RelationshipSystem.add_affinity(npc_id, delta)
	RelationshipSystem.record_gift(npc_id)

	gift_given.emit(npc_id, item.id, tier)
	if tier == Tier.PERFECT:
		RelationshipSystem.set_global_flag("%s_perfect_gift_received" % npc_id)
		perfect_gift_given.emit(npc_id, item.id)

	return {"tier": tier, "delta": delta, "line": line}


# --- Internals ---

func _grade(npc_id: String, item: ItemDef) -> int:
	if String(item.perfect_gift_for) == npc_id:
		return Tier.PERFECT
	var prefs: Dictionary = _prefs.get(npc_id, {})
	var map: Dictionary = prefs.get("category_to_tier", {})
	return map.get(item.category, Tier.NEUTRAL)


func _resolve_line(npc_id: String, tier: int) -> String:
	var prefs: Dictionary = _prefs.get(npc_id, {})
	var lines: Dictionary = prefs.get("lines", {})
	var override: String = lines.get(tier, "")
	if not override.is_empty():
		return override
	return DEFAULT_LINES[tier]
