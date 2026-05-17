extends Node

# Random NPC identity generator. Owns the head/body texture pools, name
# lists, and stock dialogue lines for each NPC category. Tracks which
# heads have been claimed so two customers don't share a face.
#
# Pools are keyed by category (&"customer", &"transit", ...). To add a
# new category: add a top-level key with the same shape. To grow a pool:
# append entries. Never reorder existing entries — head_index/body_index
# stored on Customers reference these positions.
#
# Head frame layout: each head texture is a 4-frame strip (hframes=4)
# in order south, west, east, north. CharacterSprite handles the indexing.

const POOLS: Dictionary = {
			&"customer": {
					"heads": [
			{
				"s": preload("res://art/sprites/NPCs/Random/Heads/head1_s.png"),
				"w": preload("res://art/sprites/NPCs/Random/Heads/head1_w.png"),
				"e": preload("res://art/sprites/NPCs/Random/Heads/head1_e.png"),
				"n": preload("res://art/sprites/NPCs/Random/Heads/head1_n.png"),
			},
			{
				"s": preload("res://art/sprites/NPCs/Random/Heads/head2_s.png"),
				"w": preload("res://art/sprites/NPCs/Random/Heads/head2_w.png"),
				"e": preload("res://art/sprites/NPCs/Random/Heads/head2_e.png"),
				"n": preload("res://art/sprites/NPCs/Random/Heads/head2_n.png"),
			},
			{
				"s": preload("res://art/sprites/NPCs/Random/Heads/head3_s.png"),
				"w": preload("res://art/sprites/NPCs/Random/Heads/head3_w.png"),
				"e": preload("res://art/sprites/NPCs/Random/Heads/head3_e.png"),
				"n": preload("res://art/sprites/NPCs/Random/Heads/head3_n.png"),
			},
			{
				"s": preload("res://art/sprites/NPCs/Random/Heads/head4_s.png"),
				"w": preload("res://art/sprites/NPCs/Random/Heads/head4_w.png"),
				"e": preload("res://art/sprites/NPCs/Random/Heads/head4_e.png"),
				"n": preload("res://art/sprites/NPCs/Random/Heads/head4_n.png"),
			},
		],
		"bodies": [
			preload("res://art/npc_frames/random/body_0.tres"),
			preload("res://art/npc_frames/random/body_1.tres"),
			preload("res://art/npc_frames/random/body_2.tres"),
			preload("res://art/npc_frames/random/body_3.tres"),
		],
		"first_names": [
			"Marco", "Tonya", "Dee", "Kev", "Reggie", "Sam", "Tasha", "Vince",
			"Lou", "Cynthia", "Marcus", "Trish", "Ed", "Lonnie", "Janelle", "Curtis",
		],
		"last_names": [
			"P.", "M.", "T.", "B.", "Z.", "C.", "R.", "K.",
		],
		"dialogue": [
			"You got the stuff?",
			"Hey, hey. Right on time.",
			"Make it quick, man.",
			# ... add up to 20 placeholders
		],
	},
			&"transit": {
				"heads": [
					{
					"s": preload("res://art/sprites/NPCs/Random/Heads/head1_s.png"),
					"w": preload("res://art/sprites/NPCs/Random/Heads/head1_w.png"),
					"e": preload("res://art/sprites/NPCs/Random/Heads/head1_e.png"),
					"n": preload("res://art/sprites/NPCs/Random/Heads/head1_n.png"),
				},
				{
					"s": preload("res://art/sprites/NPCs/Random/Heads/head2_s.png"),
					"w": preload("res://art/sprites/NPCs/Random/Heads/head2_w.png"),
					"e": preload("res://art/sprites/NPCs/Random/Heads/head2_e.png"),
					"n": preload("res://art/sprites/NPCs/Random/Heads/head2_n.png"),
				},
				{
					"s": preload("res://art/sprites/NPCs/Random/Heads/head3_s.png"),
					"w": preload("res://art/sprites/NPCs/Random/Heads/head3_w.png"),
					"e": preload("res://art/sprites/NPCs/Random/Heads/head3_e.png"),
					"n": preload("res://art/sprites/NPCs/Random/Heads/head3_n.png"),
				},
				{
					"s": preload("res://art/sprites/NPCs/Random/Heads/head4_s.png"),
					"w": preload("res://art/sprites/NPCs/Random/Heads/head4_w.png"),
					"e": preload("res://art/sprites/NPCs/Random/Heads/head4_e.png"),
					"n": preload("res://art/sprites/NPCs/Random/Heads/head4_n.png"),
				},
				# ... however many you want, mix-and-match with customer heads is fine
			],
			"bodies": [
				preload("res://art/npc_frames/random/body_0.tres"),
				preload("res://art/npc_frames/random/body_1.tres"),
				preload("res://art/npc_frames/random/body_2.tres"),
				preload("res://art/npc_frames/random/body_3.tres"),
				# ...
			],
			"first_names": [],   # unused — transit names aren't displayed
			"last_names": [],
			"dialogue": [
				"Out of my way.",
				"Where's the bus stop?",
				"Late again.",
				# placeholders
			],
		},
}

# category (StringName) → Dictionary[int, bool] of claimed head indices.
# Not persisted directly — rebuilt by CustomerRoster.load_state from the
# head_index of each saved customer.
var _claimed_heads: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = Time.get_ticks_usec()


# --- Public generation API ---------------------------------------------

# Returns { display_name, head_index, body_index, dialogue_line }.
# Claims the head — caller must call release_head(category, idx) if the
# customer is ever permanently removed from the roster.
func generate_customer_identity() -> Dictionary:
	return _generate(&"customer", true)


# Same shape as generate_customer_identity, but the head is not claimed —
# transit NPCs are ephemeral, so two passing-through randos sharing a
# face on different days is fine.
func generate_transit_identity() -> Dictionary:
	return _generate(&"transit", false)


# --- Head-claim bookkeeping -------------------------------------------

func release_head(category: StringName, head_index: int) -> void:
	if head_index < 0:
		return
	var claimed: Dictionary = _claimed_heads.get(category, {})
	claimed.erase(head_index)
	_claimed_heads[category] = claimed


# Called by CustomerRoster on save load — rebuilds the claim set from
# the head_index of each persisted customer.
func reclaim_head(category: StringName, head_index: int) -> void:
	if head_index < 0:
		return
	var claimed: Dictionary = _claimed_heads.get(category, {})
	claimed[head_index] = true
	_claimed_heads[category] = claimed


# --- Pool lookup (used by CharacterSprite) -----------------------------

func get_head_texture(category: StringName, head_index: int, facing: String) -> Texture2D:
	var pool: Dictionary = POOLS.get(category, {})
	var heads: Array = pool.get("heads", [])
	if head_index < 0 or head_index >= heads.size():
		return null
	var entry: Variant = heads[head_index]
	if not (entry is Dictionary):
		push_warning("NPCGenerator: head pool entry %d is not a Dictionary" % head_index)
		return null
	var head_set: Dictionary = entry
	var result: Variant = head_set.get(facing, head_set.get("s", null))
	if result is Texture2D:
		return result
	return null


func get_body_frames(category: StringName, body_index: int) -> SpriteFrames:
	var pool: Dictionary = POOLS.get(category, {})
	var bodies: Array = pool.get("bodies", [])
	if body_index < 0 or body_index >= bodies.size():
		return null
	return bodies[body_index]


# --- Internal ---------------------------------------------------------

func _generate(category: StringName, claim_head: bool) -> Dictionary:
	var pool: Dictionary = POOLS.get(category, {})
	var heads: Array = pool.get("heads", [])
	var bodies: Array = pool.get("bodies", [])
	var firsts: Array = pool.get("first_names", [])
	var lasts: Array = pool.get("last_names", [])
	var lines: Array = pool.get("dialogue", [])

	var head_idx: int = -1
	if heads.size() > 0:
		head_idx = _claim_random_head(category, heads.size()) if claim_head \
			else _rng.randi() % heads.size()

	var body_idx: int = -1
	if bodies.size() > 0:
		body_idx = _rng.randi() % bodies.size()

	var name_str: String = ""
	if firsts.size() > 0 and lasts.size() > 0:
		name_str = "%s %s" % [
			firsts[_rng.randi() % firsts.size()],
			lasts[_rng.randi() % lasts.size()],
		]

	var line: String = ""
	if lines.size() > 0:
		line = lines[_rng.randi() % lines.size()]

	return {
		"display_name": name_str,
		"head_index": head_idx,
		"body_index": body_idx,
		"dialogue_line": line,
	}


func _claim_random_head(category: StringName, pool_size: int) -> int:
	if pool_size <= 0:
		return -1
	var claimed: Dictionary = _claimed_heads.get(category, {})
	if claimed.size() >= pool_size:
		push_warning("NPCGenerator: head pool exhausted for '%s' (%d/%d claimed) — recycling" %
			[category, claimed.size(), pool_size])
		return _rng.randi() % pool_size
	# Linear pass to build the free list, then pick uniformly. Fast enough
	# at any pool size we'll plausibly hit.
	var free: Array[int] = []
	for i in range(pool_size):
		if not claimed.has(i):
			free.append(i)
	var idx: int = free[_rng.randi() % free.size()]
	claimed[idx] = true
	_claimed_heads[category] = claimed
	return idx
