# MIDNIGHT SHIFT — MVP Design Document

**Status:** Living document. MVP scope only. Story content deferred.
**Last updated:** v0.3

---

## 0. What's in this doc

This is a forward-looking design reference, not a build log. Feed it to a new chat instance to get back up to speed. It captures the high-level concept, the systems we've designed, the technical approach, what's actually been built so far, and the open questions. It does not capture art assets created, specific tile layouts, or per-line code — those live in the project itself.

**Changes from v0.2:** Stages 1 and 2 are complete; Stage 3 is in progress. §17 has been updated with the actual implemented architecture (autoload list, scene structure, signal flow). New §21 "Build Status & Architecture Decisions" captures decisions made during building that were not in v0.2. New §22 "Gotchas & Conventions" captures Godot-specific things worth knowing.

---

## 1. High Concept

A 90s-set, urban, pixel-art life sim about scraping by — and building yourself up — through a mix of hustles, relationships, and risk management. Imagine **Stardew Valley's** loop and craft systems welded onto **Schedule I's** subject matter and **Disco Elysium's** willingness to sit with adult themes.

The player starts in a shitty apartment in a rough neighborhood. They earn money through a mix of legal and illegal means: growing weed in their apartment, pickpocketing, breaking into homes in adjacent neighborhoods, dealing to a network of pager-summoned buyers. The shine isn't in the mechanics — those are deliberately simple. The shine is in the characters, the dialogue, the relationships, and the texture of the world.

**MVP goal:** A vertical slice that proves the loop is fun. One handcrafted neighborhood, the player's apartment, ~6 characters with full dialogue/relationship support, three or four income sources, a working day/calendar, and a basic heat system. No story arcs yet. No moving up. No combat depth.

**Tone references:**
- Schedule I (criminal life sim, irreverence)
- Stardew Valley (loop, dialogue system, relationships)
- Disco Elysium (adult themes treated seriously)
- Kentucky Route Zero (melancholy of place)
- GTA: Vice City / San Andreas (90s urban texture)

---

## 2. Setting & Aesthetic

**Setting:** A fictional US city, mid-1990s. Player's home neighborhood is run-down — boarded windows, weed-cracked sidewalks, neon signs missing letters. Other neighborhoods (procedural, see §13) range from working-class to affluent.

**Why the 90s:**
- No smartphones — pagers, payphones, paper maps create gameplay friction (this is now a load-bearing design choice, see §7)
- Weed is unambiguously illegal everywhere, raises stakes
- Aesthetic is well-trodden and pixel-art-friendly
- Lets the writing engage with the era's specific anxieties

**Visual direction:**
- Stardew Valley as the structural reference (top-down, similar character proportions)
- Palette pivots hard from Stardew's saturated greens/yellows to greys, browns, sodium-vapor oranges, dirty teals
- **Palette baseline: Waldgeist** (39 colors, Lospec — warm desaturated, tagged murky/dark/nostalgic). Expect to drop 3-5 colors and add 3-5 (specifically: a pure black for UI/outlines, a saturated red for blood/brake lights/neon punctuation, a sodium-orange streetlight color)
- Strong use of warm interior light vs. cold exterior light for mood
- Rain and night are visual events, not just lighting toggles

**Asset pipeline:**
1. Generate base assets in Pixel Lab
2. Aseprite for cleanup, palette enforcement (indexed mode), animation, tilemap edits
3. Export PNG spritesheets to Godot, lock palette early
4. Tile size: **32×32**. Tileset PNG canvas: 512×512 (room to grow)
5. Viewport: **640×360** (chosen during build; see §22)

**Art layering convention:** Light from upper-left. 2-3 tones per surface (base + highlight + shadow). Drop shadows under all freestanding objects. For MVP: baked-in lighting on tiles plus a global day/night tint as a postprocess shader. No dynamic Godot 2D lights yet.

---

## 3. Core Loop

### Time structure
- **Wake at 2 PM, forced sleep at 6 AM.** (This was a v0.2 design hangover; the actual game wakes at 2 PM. The criminal-life-sim framing makes night-shift hours load-bearing thematically.)
- **Real-time:** ~0.7 real seconds per in-game minute. Full wake-cycle (2 PM to 6 AM = 16 hours) ≈ 11 real minutes.
- **Display granularity:** clock shows time rounded to nearest 10 minutes (Stardew style). Internal logic uses true minutes.
- **Pause** in menus, dialogue, minigames, fades.
- **Calendar rolls** at the wake hour (2 PM), not midnight. So "Monday Day 1" runs 2 PM Mon through 1:59 PM Tue.
- **Alarm clock (post-MVP):** trade off stamina recovered against more day to work with. Wake earlier than 2 PM = less stamina restored.

### Minute-to-minute (typical day)

The pager loop and hangouts make this much richer than a pure farm-sim. Example day (re-skinned for 2 PM wake):

| Time | Activity |
|---|---|
| 2:00 PM | Wake, water plants, eat |
| 3:00 PM | Bodega for supplies, chat with shopkeeper |
| 4:30 PM | **Pager goes off** — regular wants an eighth |
| 5:00 PM | Travel to payphone, return call, set the meet |
| 6:00 PM | Drop yesterday's harvest at the fence |
| 7:00 PM | Meet buyer, $80 |
| 8:00 PM | Travel to affluent neighborhood, case a house for an hour |
| 9:00 PM | Home, harvest mature plants, start new |
| 10:00 PM | Eat |
| 12:00 AM | Romance interest is at the diner — go talk |
| 1:00 AM | **Pager** — unknown number, sketchy vibe |
| 2:30 AM | Take the risk, gas station meet, $120 but felt off |
| 4:00 AM | Hit the house you cased? Or quit while ahead? |
| 5:30 AM | Home, sleep before forced 6 AM crash |

The day is *almost* full. That's the design target — see §6.

### Failure states (escalating severity)

- **Petty:** lose cash on hand, lose carried stash, small relationship hits to witnesses
- **Medium:** overnight in lockup, lose 1-3 days, lose all carried stash, larger relationship hits, "known to police" flag raised (heat system)
- **Severe (post-MVP):** real jail time, certain characters cut you off, save-significant consequences

---

## 4. Time & Calendar

- Day: Mon-Sun. Rent due Sundays.
- Month: ~28 days. Drives long-arc events (post-MVP).
- **Stamina** drains with effort actions, resets on sleep. Out of stamina = slower movement, can't do skill checks.
- **Sleep at home** = full restore. **Pass out elsewhere** = wake up with reduced stamina cap, possibly robbed.
- **Forced sleep at 6 AM** if player hasn't slept yet. Player passes out where they stand; safe sleep only if currently in a "safe room" (apartment for now). Unsafe sleep restores 50% stamina; safe sleep restores full.

---

## 5. Economy

### Income sources (MVP)

| Source | Risk | Setup Cost | Skill Ceiling | Time Cost | Day-fill role |
|---|---|---|---|---|---|
| Weed growing | Low | Medium | Medium | Slow (multi-day cycles) | Background maintenance |
| **Pager dealing** | Medium | None (after first crop) | Medium-high | Variable, schedule-disrupting | **The schedule engine** |
| Pickpocketing | Medium | None | High (timing) | Fast (seconds) | Filler / opportunistic |
| B&E | High | Low (tools) | High (planning) | Medium (minutes per house) | Big-payoff session activity |

These are intentionally varied across **risk × time × schedule-impact**. The player should genuinely choose between them based on situation, stamina, heat level, time of day, and what else is going on.

### Expenses
- Rent: weekly, eviction if missed twice
- Food: stamina maintenance — skip too long and tomorrow's stamina cap drops
- Supplies: soil, seeds, lockpicks, baggies, etc.
- Gifts: social currency
- Bribes / fines: when caught

### Selling
- **Wholesale:** the fence buys product in bulk at low margin. Reliable but unexciting.
- **Retail (pager dealing):** sell direct to buyers at much higher margin, with all the schedule chaos that brings. See §7.

### Dirty vs. clean cash
Deferred post-MVP, but architect the wallet to support multiple currency pools so it's not a refactor later.

---

## 6. The Day-Filling Principle

The single most important design principle in the project.

**Stardew's secret is that the day is always slightly too short to do everything you want.** That tension is the engine of "one more day" engagement. If the player ever finishes their list with hours of in-game time left, the loop has failed.

Every activity falls into one of four time-cost categories:

1. **Maintenance** — non-negotiable but predictable (plants, eating, sleeping, hygiene/appearance, apartment upkeep)
2. **Income** — varied risk/time profiles (weed, pager dealing, pickpocket, B&E, day labor as the legal grind option)
3. **Social** — relationship maintenance (NPC schedules, gifts, hangouts, phone calls)
4. **Exploration / Long-term** — pays off over many days (casing, hanging at the bar overhearing gossip, reading/skills, apartment improvements)

**Tuning principle 1:** Time costs should feel real but not punishing. A trip across town to a payphone is ~20-30 in-game minutes — felt but not crippling.

**Tuning principle 2:** The schedule should *almost* fit, not comfortably fit. If a productive day is ~16 in-game hours (2 PM to 6 AM), the player's want-to-do list should average 20-22 hours. The 4-6 hour overflow is what makes them want to play tomorrow.

---

## 7. The Pager Dealing Loop

This is the **schedule-disrupting engine** of the game. It's not just income — it's the system that creates moment-to-moment dramatic choices.

### The loop

1. **Page arrives** — pure interruption, you don't control timing
2. **Find a payphone** — physical travel, time burned
3. **Return the call** — short dialogue, negotiate location, time, quantity, price
4. **Commit to a window** — "Shell parking lot, one hour"
5. **Travel and execute** — get there on time, hand off, get paid; risk of being seen
6. **Back to whatever you were doing**

### Why this is good design

The page doesn't tell you to do something — it *disrupts your existing plan*. You were watering plants. You were on your way to the bar to meet the romance interest. Now what?

### Mechanical details

- **Pager codes.** A page is a callback number plus a numeric code. Codes signal quantity, urgency, or warnings ("bring nothing — heat"). Learning the code system is early-game progression.
- **Payphones are at fixed locations** in the world. Map memorization matters.
- **The window matters.** Show up late, the buyer's pissed or already gone. Show up early, you're loitering visibly.
- **Standing buyers up has consequences.** Trust drops, they stop paging. Repeat flakes get blacklisted.

### Buyer relationship system

Mirrors the NPC relationship system in miniature. Each recurring buyer has:

- **Affinity** (forgiveness about lateness, willingness to negotiate price)
- **Trust** (would they introduce you to their friends?)
- **Heat exposure** (some buyers are intrinsically hotter — closer to law enforcement, undercover risk)

Buyers progress: unknown number → tentative regular → reliable customer → vouches for you → introduces friends. Your buyer network grows organically through good behavior.

### Buyer archetypes (3-4 named recurring buyers in MVP)

These are *not* part of the 6-character cast — they're a separate ambient layer. Each gets a voice and a pattern but no full relationship system.

Examples:
- The college kid who pages every Friday afternoon, predictable
- The middle-aged woman who calls late at night and is weirdly chatty
- The guy who always tries to short you on price
- The new contact your fence vouched for — could be great or could be the cops

### Risk variables

- **Time of day** — daylight deals are riskier
- **Location heat** — meeting in a high-heat area is dangerous
- **Buyer's heat exposure** — sketchy buyers attract attention
- **Quantity carried** — more on you = bigger bust if caught
- **Repetition** — meeting the same buyer at the same place repeatedly raises area heat

---

## 8. Income System: Weed Growing

The player's apartment has space for grow containers. Significant design evolution from v0.2 — see "Plant containers" below.

### Growth cycle

```
empty container slot → [+ soil] → soiled slot → [+ seed] → seeded slot
→ [+ water, daily, until next stage] → seedling → vegetative → flowering → mature
→ [harvest] → buds + new seed (chance) → soiled slot (with -1 soil use)
```

### Stages
1. Seedling (2 days)
2. Vegetative (4 days)
3. Flowering (4 days)
4. Mature — harvest window (3 days, declining quality if missed)

Growth is **discrete**, advancing at day rollover (2 PM). Naps don't progress plants.

### Plant containers and slots

Plants grow in **containers**, not "pots." A container has 1+ slots; each slot independently holds one plant. This unifies the data model across:

- 1-slot pot (starter)
- 4-slot planter bed (mid-tier)
- 24-slot outdoor plot (late-tier)

Per-slot interaction: each slot is its own Interactable with its own state (empty/soiled/seeded/growing/mature) and prompt. Walk up to slot 2 of a 4-slot planter, the prompt addresses that slot specifically.

### Soil mechanic

Soil has **uses** — when you fill a slot with soil, that soil supports N plant cycles. After N harvests, the slot is empty again (no soil). Player must re-soil. This creates a small recurring expense and a "rotate vs. continuous-grow" decision.

### Composable plant art

Plant art is **separate from container art**. The container sprite is fixed; the plant sprite is layered on top, positioned at the slot's offset. This means:

- One set of plant-stage sprites works across all container sizes
- New strains require only plant-stage art, not container variants
- Plants growing taller than the container footprint is supported

Y-sort origin on plant sprites must point to the *container's base*, not the plant's base, so plants in tall containers sort correctly relative to the player.

### Quality factors (MVP keeps simple, but architect for §21 quality system)

- Watering consistency (missed days reduce yield) — implemented in MVP
- Light source (basic lamp = baseline, grow lamp = +quality, requires upgrade) — Stage 4+
- Strain-specific requirements (post-MVP — see §21)

Each plant tracks a `modifiers` array — "events that affect quality." MVP only adds `water_missed` modifiers. Post-MVP adds: wrong light hours, wrong indoor/outdoor, spacing violations, etc. Quality at harvest is a function over this array.

### Selling pipeline
- Raw buds → fence at base price
- **Packaging (in MVP if time permits):** raw buds + baggies → packaged product, sells at higher margin via pager dealing. This is what makes pager dealing meaningfully more profitable than wholesaling, justifying its complexity.
- Curing, edibles, multi-strain — post-MVP

### Mechanic style
Stardew-direct. Held item + interactable container slot = action. No menus. Soil bag on empty slot, seed on soiled slot, watering can on seeded slot, harvest mature plant by interacting with a slot that has one. Muscle memory; *interest* comes from balancing water cycles against everything else competing for your day.

---

## 9. Income System: Pickpocketing

(Unchanged from v0.1)

**Target selection:** NPCs in public spaces have a pocket value and an awareness stat.

**Minigame proposal:** Approach undetected → timing-based stop-the-bar → three outcomes (clean, detected & fled, caught with cop in line of sight).

**Risk variables:** target awareness, witness count, cop proximity, player's Sleight skill.

---

## 10. Income System: B&E

### Casing as a day-fill activity
B&E has an explicit prerequisite: **casing**. You can't B&E a house cold. You spend in-game time (an hour or two, possibly across multiple days) watching from a park bench, learning the occupant's schedule, noting alarm wires, dogs, etc. This is *another way to spend time* and turns B&E from a single-action into a multi-day arc.

### The full loop
1. Travel to an adjacent neighborhood
2. Case targets (time cost, may span days)
3. Pick entry approach: door / window / back (lockpick difficulty / noise / visibility tradeoff)
4. Enter and search containers (stamina cost, rising heat with time inside)
5. Exit before heat caps

### Minigames
- Lockpicking (skill-gated, mechanic TBD — explicit open question, see §18)
- Searching (timed container interactions)
- Stealth (footstep noise, sleeping occupants, dogs)

### Risk / reward
Bigger / nicer houses = better loot, more security, faster cop dispatch. **Area heat persists** — hitting the same neighborhood repeatedly raises baseline difficulty there for in-game weeks.

---

## 11. Relationships & Dialogue

This is the heart of the game. Mechanics elsewhere are simple precisely so writing and relationships can carry weight.

### Relationship model — *not* hearts

Three axes per NPC:

- **Affinity** (-100 to +100): how much they like the player
- **Trust** (0 to 100): how much they'd bet on the player's word/competence
- **Knows** (flag): aware of player's criminal activity (specific or general)

Examples:
- Romance interest: high affinity, low trust, doesn't know — "I like you but you're shady"
- Criminal mentor: medium affinity, high trust, knows everything
- Straight-world neighbor: high affinity, high trust, *doesn't know* — fear of finding out is the dramatic engine

### Dialogue system

Stardew-style key-lookup, plus modifications:

- Each NPC has a dialogue dictionary (JSON or Godot Resource files for hot-reload)
- Keys encode conditions through naming convention: `Apartment_Mon_rainy`, `summer_Wed`, `Wed`
- Lookup walks priority list, picks first match
- Per-line **preconditions** (mini-DSL): `affinity Mira 60/trust Mira 40/!knows Mira/time 1800 2400`
- In-string formatting: `$h` (happy portrait), `$b` (page break), `$q`/`$r` (question/response), `%name`/`%nbhd` (substitutions)
- **Hot-reload from disk** during development — non-negotiable for writer iteration

### Events (post-MVP, but architect for it now)

Stardew-style cutscenes triggered by location + time + precondition. They can `pushDialogue()` follow-up lines onto an NPC's stack. Don't author events yet, but the dialogue system must support push-stack from day one. Events scheduled during a time-skip that the player wasn't present for are **left in queue** — they fire next time conditions are met, rather than firing in compressed sequence or being silently lost.

### Gifts
Universal Loves/Likes/Neutral/Dislikes/Hates with per-NPC overrides. Gifts include cash, drugs, favors, contraband — different from Stardew's wholesome eggs. Giving a recovering addict drugs destroys the relationship; giving an undercover cop a baggie is a disaster.

**Explicit gift-giving:** Unlike Stardew's hold-item-and-talk pattern (which causes accidental gifts), our gift-giving is via an explicit "Give a gift" sub-menu in NPC dialogue. Two confirmations between "I have a gift" and "she now has a gift."

### Hangouts
Beyond bumping into NPCs at scheduled locations, the player can commit to **scheduled hangouts**: "Want to get a beer Friday night?" Burns 3-4 hours, gives big affinity gain, conflicts with everything else on the schedule. This is a Schedule I-style adult-life mechanic and integrates with the day-filling principle: hangouts are the social-layer equivalent of the pager loop's income disruption.

### Phone calls
NPCs can also page you, not just buyers. The romance interest paging "you doing anything tonight?" while you have a deal scheduled is the *core dramatic situation* the game is designed to produce.

---

## 12. Cast (MVP — 6 Characters)

Roles, not specific characters. Each chosen to stress-test a different relationship/dialogue facet.

| # | Role | System purpose |
|---|---|---|
| 1 | **The Fence** | Economy node — buys product. Tests trust system, gates progression. |
| 2 | **The Mentor / Old Hand** | Tests "knows everything" relationship, criminal advice. |
| 3 | **The Romance** | Tests affinity scaling, gift system, branching dialogue under pressure. |
| 4 | **The Straight-World Anchor** | Tests "doesn't know" tension, secret-keeping. |
| 5 | **The Rival / Antagonist** | Tests negative affinity, conflict dialogue. |
| 6 | **The Wildcard** | Pick to fill the gap the cast is missing once others are written. |

Each gets: schedule, birthday, gift preferences, dialogue dictionary covering time/weather/weekday/location/affinity/trust/knows-flag variants.

**Plus 3-4 named recurring buyers** as a separate ambient layer (see §7) — voice and pattern, not full relationship system.

---

## 13. Locations (MVP)

**Handcrafted:**
1. Player's Apartment (multi-room: living, bedroom)
2. The Neighborhood (street + adjacent buildings)
3. The Bar / Diner — late-night socializing
4. The Bodega / Corner Store — supplies, food, Straight-World Anchor's workplace
5. The Fence's Spot — pawn shop back room

**Plus:**
- **Payphones** — fixed locations across the city. Map-memorization gameplay.
- **Public space for casing** — a park bench, bus stop, or similar in adjacent neighborhoods where you can sit and watch houses

**Procedural:**
6. Adjacent Neighborhood(s) — see §14

Six handcrafted areas is ambitious for MVP. Bodega and bar are most cuttable.

---

## 14. Procedural Generation for B&E

**Ambition: low.** Handcrafted rooms, procedurally assembled and dressed (Spelunky chunk approach).

- Author ~10-20 room templates (living room, kitchen, bedroom, bathroom, hallway) at multiple sizes
- Author ~3 house layouts as connection graphs (1-bed apt, 2-bed house, 3-bed house)
- At runtime: pick layout, fill slots with random matching room templates, dress with theme-tagged loot/decor pools
- Occupants generated with simple schedules (sleeping, watching TV, out)

Variety from: wealth tier, occupancy state, security tier.

---

## 15. Heat / Police System (MVP-light)

Two heat pools:

- **Personal heat** (0-100): cops' interest in *you specifically*. Rises from witnessed crimes, decays slowly.
- **Area heat** (per neighborhood, 0-100): how alert a neighborhood is. Rises from B&Es and visible crimes there. Decays over a week or two.

**Affects (MVP):** patrol density, police response time, arrest severity tier.

**Doesn't yet (post-MVP):** detective investigations, named cop NPCs, news stories, witnesses identifying you.

---

## 16. Systems Deferred Post-MVP

- Combat (caught = arrest, no fistfights yet; architect inventory for weapons)
- Money laundering (build wallet to support multiple pools)
- Hunger and detailed needs (stamina is the only need; food just maintains stamina cap)
- Inventory weight / limits (stack-based slot limits only)
- Moving up (apartment fixed in MVP)
- Story arcs and named events (system supports them; no content authored)
- Multiple fences / dealer relationships (single fence)
- Romance progression to physical content (relationship curve supports it; content not authored)
- More characters, more income sources, more locations
- Dynamic Godot 2D lighting (baked + day/night tint only for MVP)
- Detective AI, news system, reputation, gangs, territory
- Manual inventory rearrangement / drag-drop UI (auto-stack only for now; `swap_slots` API exists for future use)
- Strain-specific quality requirements beyond watering (architecture supports `modifiers`; only `water_missed` implemented)

---

## 17. Technical Architecture (Godot)

**Engine:** Godot 4.3+ (using `TileMapLayer`, not legacy `TileMap`). Forward+ renderer.

### Project structure (current state)
```
res://
├── scenes/
│   ├── player/                # player.tscn, player.gd
│   ├── rooms/                 # apartment_living.tscn, apartment_bedroom.tscn
│   ├── components/            # bed.tscn, doorway.tscn, interactable.tscn
│   │                          # (placeable scenes will go here too)
│   ├── ui/                    # hotbar_slot.tscn (more to come)
│   └── world.tscn             # the scene that owns RoomManager and Player
├── scripts/
│   ├── systems/               # autoload singletons
│   │   ├── time_system.gd
│   │   ├── time_skip_system.gd
│   │   ├── room_manager.gd
│   │   ├── interaction_manager.gd
│   │   ├── screen_fade.gd / .tscn
│   │   ├── save_system.gd
│   │   └── item_registry.gd
│   ├── components/            # interactable.gd, bed.gd
│   ├── items/                 # item_def.gd, item_stack.gd, inventory.gd
│   └── ui/                    # hud.gd, day_night_tint.gd, hotbar.gd, hotbar_slot.gd
├── data/
│   ├── items/                 # ItemDef .tres files (custom resources)
│   └── (future: strains, schedules, dialogue, loot tables)
├── art/
│   ├── tilesets/
│   ├── sprites/
│   ├── icons/                 # hotbar icons (16×16)
│   └── ui/
└── data/items/                # ItemDef Custom Resources (.tres files)
```

### Autoloads (in initialization order)

The order matters because some autoloads depend on others being available in their `_ready`.

1. **SaveSystem** — must be first; other systems register themselves with it during their own `_ready`
2. **ItemRegistry** — scans `res://data/items/` and builds id→ItemDef map at startup
3. **TimeSystem** — clock; registers self with SaveSystem
4. **RoomManager** — owns current room scene and player references
5. **InteractionManager** — arbitrates which Interactable wins on E-press
6. **ScreenFade** — full-screen fade ColorRect on layer 100; `fade_out`/`fade_in`/`cover` API
7. **TimeSkipSystem** — orchestrates fade + time advance + signal emission for sleep/skip events

### Architecture principles
- **Data-driven where it matters** — items are Custom Resources (chosen over JSON for editor ergonomics; the design doc's hot-reload principle still applies for content authored later: dialogue, schedules, strains)
- **Hot reload during dev** — scripts hot-reload by default; data resources may require restart depending on how they're referenced
- **Singletons (Autoloads):** see list above
- **Signals for cross-system events** — every system that needs to react to time, sleep, room change, etc. listens to a signal rather than polling. Time-skip listeners react to a single `time_skipped` signal; daily things listen to `day_rolled`.
- **Save system** = registry pattern: any node implements `save_state() -> Dictionary` and `load_state(data: Dictionary)`, calls `SaveSystem.register_savable(key, self)` in `_ready()`. Save format is JSON in `user://save.json` with version field.

### Time-skip architecture (the load-bearing pattern)

Sleep is not "the player goes to bed." Sleep is **a special case of time-skip**, alongside:
- Forced sleep at 6 AM
- Knockout / arrest
- Fast travel (post-MVP)
- Cutscene auto-skip ("scene ends, advance to 10 PM")

The pattern:

```
TimeSkipSystem.skip_to(target_minute, context: Dictionary)
  → fade out
  → TimeSystem.advance_to(target_minute)
  → emit time_skipped(from, to, context)
  → fade in
```

The `context` dictionary carries metadata (kind: "sleep"/"arrest"/etc., safe: bool, voluntary: bool, fade_duration: float). Listeners check the keys they care about. Player listens to restore stamina conditionally on context. Plants listen to `day_rolled` only (not `time_skipped`) because growth is discrete-daily. Future systems (heat decay, NPC schedules, robbery rolls) plug in by listening.

The bed's `_on_interacted` calls `TimeSkipSystem.skip_to(...)` with `kind="sleep", safe=true, voluntary=true`. Forced sleep calls with `voluntary=false`. The teleport-to-wake-spot is handled by the bed listening one-shot to `time_skipped` after triggering its own skip.

### Tilemap conventions
- 32×32 tiles, tileset PNG laid out on a 512×512 canvas (room to grow without repositioning existing tiles)
- Walls split across two layers: `WallsBase` (bottom-row, walkable, no physics) and `WallsTop` (upper rows, blocking, Y-sort origin pointing to wall base). Standing-against-wall illusion via Y-sort.
- For mixed-content tiles (one tile with both walkable area and visual depth): split the art into separate fully-transparent halves, paint on appropriate layers. Y-sort origin per-tile, tuned empirically.
- Per-tile collision drawn in Godot's tileset editor; full-tile collision is fine for blocked tiles given the bottom-row-walkable design
- Y-sort enabled on room roots; sprite pivots at *base* of object (character feet, plant container base)
- Character collision: small rectangle (~20×8) at the feet, *not* full sprite size

### Scene structure conventions

**Room scene** (e.g., `apartment_living.tscn`):
```
ApartmentLiving (Node2D, Y-sort enabled)
├── Floor          (TileMapLayer, Y-sort OFF)
├── WallsBase      (TileMapLayer, Y-sort ON)
├── WallsTop       (TileMapLayer, Y-sort ON)
├── Decoration     (TileMapLayer, Y-sort ON)
├── Interactables  (Node2D)        # bed, future fixed interactables
├── SpawnPoints    (Node2D)        # Marker2D children: "default", "from_<other_room>"
├── NPCs           (Node2D)        # populated when NPC system exists
└── Placeables     (Node2D)        # placed objects (pots, furniture); see §21
```

**World scene** (`world.tscn`) is the root that owns RoomManager state and persistent player:
```
World (Node2D)
├── CurrentRoom    (Node2D, slot for active room scene)
├── Player         (instance of player.tscn)
└── HUD            (CanvasLayer)
    ├── DayNightTint    (ColorRect, full-screen, code-driven)
    ├── ClockLabel
    ├── StaminaLabel
    ├── InteractPrompt
    └── Hotbar          (HBoxContainer, 12 slots, programmatically populated)
```

**Player scene** (`player.tscn`):
```
Player (CharacterBody2D, in "player" group)
├── AnimatedSprite2D    (4-direction walk: walk_n/e/s/w, 6 frames each, 8 FPS)
├── CollisionShape2D    (~20×8 rectangle at feet)
├── Camera2D            (zoom 3, Process Callback: Physics, no smoothing — pixel-snap)
└── Inventory           (Node, inventory.gd attached)
```

### Interactable architecture

Interactables use a **priority-based arbitration model** rather than first-come-first-served. This handles the case where multiple interactable zones overlap (e.g., a plant slot and a lamp covering the same tile).

Each Interactable exposes:
- `interact_priority: int` — higher wins (suggested scale: 100 plants, 80 plant slots, 60 containers, 40 NPCs, 30 doorways, 20 lamps, 10 decoration)
- `prompt_text: String` — what the HUD shows when this Interactable is the winner
- `auto_trigger: bool` — bypass arbitration entirely; fire on body_entered (used by bed)
- `can_interact(player) -> bool` — virtual; returns whether this Interactable currently *wants* to handle E. Default: true. Override to gate by player state.
- `state_changed` signal — emitted when eligibility might have changed; InteractionManager re-arbitrates.

InteractionManager tracks all overlapping Interactables, recomputes the winner on register/unregister/state_changed/active-slot-change. Winner appears in the HUD prompt; pressing E fires `interact()` on the winner.

This model handles your "plant slot interactable takes priority over lamp if eligible, otherwise lamp" pattern: the plant slot's `can_interact` returns true only when the player holds the right item or the plant is mature; otherwise it's filtered out and the lamp wins by default.

---

## 18. Open Questions

Decisions to make during prototyping, not now:

1. **Stamina granularity** — currently continuous float (0-100); reconsider if player feedback wants Stardew-style discrete energy
2. **Pickpocket minigame** — timing bar proposal; rhythm or QTE alternatives worth prototyping
3. **Lockpick minigame** — Skyrim-style is legible but tired; explore alternatives
4. **NPC AI for B&E houses** — full schedules or simple state machines?
5. **Witness system** — generic heat or witnesses identifying the player specifically? (Generic for MVP)
6. **Single save slot vs. multiple** — currently single overwrite, design assumes one slot
7. **Wildcard NPC role** — pick after the other five are written
8. **B&E lethality** — leaning no for MVP (pulls combat in with it)
9. **Pager code system specifics** — how complex? How is it taught?
10. **Hangout mechanics** — pure time-skip with affinity reward, or scene-based with dialogue branches?
11. **Strain quality requirements** — when to introduce beyond watering? Probably after first strain is harvestable end-to-end.
12. **Lamp art and tile-coverage shapes** — 1×2 → 2×2 → 2×4 rectangular footprints (lamps occupy a "ceiling" placement layer separate from floor)

---

## 19. MVP Build Order

The recommended order to actually build this. Each stage produces a runnable build that proves the next stage's prerequisites.

### Stage 1: Spatial Foundation ✅ COMPLETE
- Tile-based room (apartment interior)
- Character with 4-direction walking animation
- Collision (foot-only on character, full-tile on blocked tiles)
- Y-sort for depth
- Room-to-room transitions

### Stage 2: Time and State ✅ COMPLETE
- Day/night clock with 10-min display granularity
- Day/night color tint (code-driven from minute_tick)
- Sleep/wake cycle (voluntary via bed; forced at 6 AM)
- Stamina meter (passive + movement + action drain)
- Save/load (JSON, autosave on day_rolled)
- Time-skip system (handles all transitions: sleep, future fast-travel, cutscene auto-skip)
- Interactable architecture with priority arbitration
- Screen fade utility

### Stage 3: First Income Loop (Weed) — IN PROGRESS
- Inventory system ✅ (Custom Resource ItemDefs, ItemStack, 12-slot hotbar with active outline)
- Hotbar input (number keys, mouse wheel, controller LB/RB) ✅
- Placeable items system — IN PROGRESS (see §21)
- Per-room state persistence — UPCOMING
- Plant container system (1-slot pot, multi-slot expansion path)
- Soil/seed/water/harvest cycle
- Storage box (purchasable, see §21)
- Packaging (if art exists for baggies)

### Stage 4: Dialogue & First NPC
- Dialogue system with key-lookup, preconditions, hot-reload
- One NPC with schedule and idle animation in a fixed location
- Basic relationship axes (affinity / trust / knows)

### Stage 5: Economy Closure
- The Fence (sells weed wholesale)
- Money in/out
- Rent

### Stage 6: Pager & Buyers
- Pager system (timing, codes)
- Payphone interactables
- 2-3 buyer archetypes
- Retail dealing pipeline

### Stage 7: Crime & Heat
- Pickpocketing minigame
- Heat system (personal + area)
- Arrest/failure flow

### Stage 8: Adjacent Neighborhood & B&E
- Procedural neighborhood + house assembly
- Casing mechanic
- Lockpick + search minigames
- Loot tables

### Stage 9: Cast Expansion
- Fill out remaining 5 NPCs
- Schedules across locations
- Hangouts mechanic

### Stage 10: Polish & MVP Definition of Done
See §20.

---

## 20. MVP Definition of Done

The MVP is "done" when a new player can:

1. Wake up in the apartment, learn the basic loop in their first in-game day
2. Grow weed from seed to harvest over an in-game week
3. Sell wholesale to the fence
4. Receive a page, return the call, and complete a deal
5. Develop a recurring buyer relationship over multiple successful deals
6. Pickpocket at least one NPC successfully and unsuccessfully
7. Case and B&E at least one procedural house successfully and unsuccessfully
8. Build relationship with at least one of the 6 NPCs to a meaningful threshold
9. Hang out with an NPC, choosing it over a competing income opportunity
10. Get arrested at each severity tier and experience the consequences
11. Survive (or fail to survive) a full in-game month
12. Save and reload without state loss

---

## 21. Build Status & Architecture Decisions

This section captures decisions made during building that weren't in v0.2's design doc.

### Stage 1 + 2 are complete. Specifically working:
- Walk between two apartment rooms via doorways (auto-trigger Area2Ds)
- Clock advances; day/night tint shifts hour-by-hour
- Stamina drains passively + on movement; visible HUD at low values goes amber/red
- Bed sleep: walk onto bed → fade → wake at 2 PM next day at wake-spot, full stamina
- Forced sleep at 6 AM if not slept yet (player wakes wherever they were)
- Save persists time, room, position, stamina, full inventory; loads on game start
- 12-slot hotbar with auto-stacking pickup, active-slot outline, number-key + scroll + LB/RB selection

### Choices made during build (worth knowing):

**Wake hour is 2 PM, not 6 AM.** This is a 90s-criminal-life-sim tonal choice. v0.2 doc had inherited 6 AM from earlier drafts.

**`day_index()` math.** The calendar rolls every `total_minutes / 1440` — i.e., every 24 in-game hours from start. This makes "Mon Day 1" run from 2 PM Mon through 1:59 PM Tue. The wake-hour offset only affects clock-face display, not calendar rollover.

**Single integer `total_minutes` is the source of truth for time.** All other time queries (current_hour, current_minute, day_of_week, day_of_month) are derived. Display granularity (10-min rounding) is purely a format-string concern.

**Pause counter, not bool, on TimeSystem.** Multiple systems can pause concurrently (menu open during dialogue). Time runs only when count is zero.

**Sleep is a special case of time-skip.** The TimeSkipSystem owns the fade + advance + signal pattern. Bed, forced sleep, future cutscene auto-skips, and fast travel all use it. See §17 for details.

**Item architecture: Custom Resources, not JSON.** Author ergonomics (drag-drop, autocomplete, editor inspector) won out over the data-driven principle for items specifically. Other content (dialogue, schedules) will likely still be text files when those systems land.

**Inventory pickup is auto-stack.** Same-item stacks fill first, then overflow to next empty slot. `add()` returns leftover count; caller handles overflow. Inventory-full pickup attempts are refused (item stays in world); no silent loss.

**No held-item visual.** Per design call. The hotbar's active-slot outline is the only feedback. Future contextual prompts (when in an interactable zone) will surface what action will fire, but the visual indicator stays on the HUD, not the player.

**Interactable arbitration uses `interact_priority`, not `priority`.** `priority` is reserved on `Area2D`. Other names that collide and were hit during build: `get_stack` (Node has it), property names ending in standard physics terms.

### Placeable system (in progress, finalized design):

**Placeables are a category of ItemDef** — `ItemDef.category = PLACEABLE` with extra fields:
- `placeable_scene: PackedScene` — what to instantiate on placement
- `placement_surface: enum (FLOOR, CEILING)` — floor for pots/furniture, ceiling for lamps
- `footprint_tiles: Vector2i` — for grid-occupancy validation

**Two parallel placement layers:** floor-grid and ceiling-grid. A pot occupies floor at its tile; a lamp occupies ceiling tile(s) above. Lamps and pots can share a tile-position. Lamps cover 2 tiles (early), 4 (mid), 8 (late) in rectangular footprints.

**Placement mechanic:** drop-at-feet — face direction + interact key + active item is placeable → instantiate at the tile in front of the player, grid-snapped to 32×32. Surface validation rejects if tile occupied for that surface.

**Pickup mechanic:** alt-interact key on a placeable returns it to inventory if state allows. Refuses if container has plants in it ("remove plants first"). Empty pots can be picked up; soil persists with the container until it's picked up (the container "carries" its soil-uses count).

**Persistence model:** per-room state. When the player leaves a room, all Placeables in that room are serialized to a save dictionary keyed by room scene path. When the player re-enters, the room scene loads as a template, then the persisted state is applied as overlay. Integrates with SaveSystem via a new `WorldStateSystem` autoload.

**Plant containers as a special placeable type:** scene structure has a `Slots` (Node2D) child whose `Marker2D` children define slot positions visually. Slot count = child count. Each slot has its own Interactable. Slot state: `empty | soiled | seeded | growing | mature`. Per-slot Interactable's `prompt_text` doesn't morph by held item (per scoping decision; the priority-based arbitration handles "should this slot or the lamp respond to E").

**Interaction priority for plant+lamp overlap:** plant slot priority is high (80). Lamp priority is low (20). Plant slot's `can_interact` returns false when no relevant action is possible — empty slot rejects unless player holds soil, soiled slot rejects unless player holds seed, etc. When plant slot rejects, only lamp is eligible, lamp wins. When plant slot accepts, plant slot wins on priority.

### Quality system foundations (deferred but architected):

Each plant tracks `modifiers: Array[Dictionary]` — events that affect quality. Format: `{ "kind": "water_missed", "day": 3 }`. MVP only adds `water_missed`. Later strains add: wrong light hours, wrong indoor/outdoor, spacing violations, etc. Quality at harvest is a function over this array. The architecture supports adding new modifier kinds without refactoring existing plant data.

---

## 22. Gotchas & Conventions

Things learned during build that are worth knowing for the next dev session:

### Godot quirks

- **Property collisions on built-in nodes are real.** `priority` on Area2D, `get_stack` on Node, etc. are taken. When subclassing built-ins, prefix custom fields: `interact_priority`, `prompt_text`. Generic-sounding names should be assumed taken.
- **Type inference (`:=`) sometimes fails after adding `class_name`.** Reload the project (Project → Reload Current Project) or restart Godot. Workaround: explicit `: Type` annotations.
- **Layout properties hidden inside containers.** Children of `PanelContainer`, `HBoxContainer`, etc. don't expose anchor presets — the container manages layout. To override positioning of a child, wrap it in a `Control` first.
- **`@onready` and child node existence.** `@onready var inventory: Inventory = $Inventory` returns null if no Inventory child exists. Adding the script reference doesn't create the node — the node must exist in the scene file.
- **Editable Children for instanced scenes.** Children of an instanced scene appear faded and can't be added/removed without enabling Editable Children (right-click instance → Editable Children). Prefer to never enable this — design instanced scenes so per-instance config is via exported properties or fully-replaceable child resources.
- **Autoload init order matters.** SaveSystem must initialize before anything that registers with it. ItemRegistry must come before anything that uses items.

### Conventions in this codebase

- **String IDs for save references.** ItemDefs reference each other and save files reference items by `id: StringName`. Renaming a `.tres` file is fine; renaming the `id` breaks saves.
- **Signals over polling.** Every cross-system reaction goes through a signal. HUD updates on time tick, not per-frame poll. Inventory changes emit `slot_changed`; HUD listens.
- **Pause everywhere.** Any UI or transition that should freeze the world calls `TimeSystem.pause()` and `TimeSystem.resume()`. Counter handles concurrent pausers.
- **Y-sort origin tuning is empirical.** Don't try to derive the exact value mathematically; eyeball it with the player walking against the relevant tile/object, and step in 2-pixel increments.
- **Auto-trigger interactables bypass arbitration.** Setting `auto_trigger = true` on an Interactable means it fires on `body_entered` instead of competing for E-press priority. Used by bed and doorway.
- **`super._ready()` in Interactable subclasses.** When overriding `_ready` in a script that extends Interactable, call `super._ready()` first or the body_entered/body_exited signals don't connect.

### Known minor bugs / deferred fixes
- Doorways at identical positions in two rooms cause infinite-flip when stepping through (workaround: don't put doorways at identical positions, give the spawn a one-tile buffer)
- Day/night tint between 2 PM and 9 PM needs more tuning passes (the warm-to-purple transition is the trickiest; needs an intermediate pink stop)
- Some Interactable scenes don't carry CollisionShape2D when instanced (workaround: add manually after instancing)
- HUD's `get_parent().get_node("Player")` is fragile (works because we know World structure; replace with a player-reference singleton when convenient)
