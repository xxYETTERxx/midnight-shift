# [WORKING TITLE] — MVP Design Document

**Status:** Living document. MVP scope only. Story content deferred.
**Last updated:** v0.1

---

## 1. High Concept

A 90s-set, urban, pixel-art life sim about scraping by — and building yourself up — through a mix of hustles, relationships, and risk management. Imagine **Stardew Valley's** loop and craft systems welded onto **Schedule I's** subject matter and **Disco Elysium's** willingness to sit with adult themes.

The player starts in a shitty apartment in a rough neighborhood. They earn money through a mix of legal and illegal means: growing weed in their apartment, pickpocketing, breaking into homes in adjacent neighborhoods. The shine isn't in the mechanics — those are deliberately simple. The shine is in the characters, the dialogue, the relationships, and the texture of the world.

**MVP goal:** A vertical slice that proves the loop is fun. One handcrafted neighborhood, the player's apartment, ~6 characters with full dialogue/relationship support, three income sources, a working day/calendar, and a basic heat system. No story arcs yet. No moving up. No combat depth.

**Tone references:**
- Schedule I (criminal life sim, irreverence)
- Stardew Valley (loop, dialogue system, relationships)
- Disco Elysium (adult themes treated seriously)
- Kentucky Route Zero (melancholy of place)
- Grand Theft Auto: Vice City / San Andreas (90s urban texture)

---

## 2. Setting & Aesthetic

**Setting:** A fictional city, somewhere in the US, mid-1990s. Player's home neighborhood is run-down — boarded windows, weed-cracked sidewalks, neon signs missing letters. Other neighborhoods (procedural, see §12) range from working-class to affluent.

**Why the 90s:**
- Removes smartphones — schedules, paper maps, payphones, beepers all feel natural and create gameplay friction
- Weed is unambiguously illegal everywhere, raises stakes
- Aesthetic is well-trodden and pixel-art-friendly (CRT TVs, boomboxes, baggy clothes, muscle cars)
- Lets the writing engage with the era's specific anxieties (crack epidemic aftermath, AIDS, recession)

**Visual direction:**
- Stardew Valley as the structural reference (top-down, similar tile size, similar character proportions)
- Palette pivots hard from Stardew's saturated greens/yellows to **greys, browns, sodium-vapor oranges, dirty teals**
- Aim for a fixed master palette of ~32-40 colors — this is the single biggest lever for cohesion when mixing AI-generated and hand-edited assets
- Strong use of warm interior light vs. cold exterior light for mood
- Rain and night are visual events, not just lighting toggles

**Asset pipeline:**
1. Generate base assets in Pixel Lab
2. Aseprite for cleanup, palette enforcement (indexed mode), animation, tilemap edits
3. Export spritesheets + JSON to Godot
4. Lock master palette early — retrofitting later is miserable

---

## 3. Core Loop

### Minute-to-minute (typical day)

1. **Wake at 6am** in the apartment
2. **Tend the grow** — water plants, harvest mature ones, start new ones
3. **Step outside** into the neighborhood
4. **Run errands or hustles**: pick a pocket, case a house, meet a contact, sell product to a fence
5. **Socialize** — find characters at their scheduled locations, talk, give gifts, build relationships
6. **Spend or save** — buy food/supplies, pay rent (weekly), upgrade gear
7. **Return home before 2am** or pass out wherever you are
8. **Sleep, day advances**

### Day / Week / Month

- **Day:** 6am–2am playable. Pass out at 2am wherever you are (penalty if outside or in the wrong place).
- **Week:** Mon–Sun. Rent due Sundays. Some characters have weekly schedules tied to weekday.
- **Month:** Roughly 28 days. Drives long-arc events (post-MVP).

### Failure states (Mix — escalating severity)

- **Petty (first offenses, low-value theft):** lose cash on hand, lose stash if caught with it, wake up next day with a small relationship hit to anyone who saw
- **Medium (caught with quantity, repeat offenses):** overnight in lockup, lose 1–3 days, lose all carried stash, larger relationship hits, "known to police" flag raised (heat system)
- **Severe (post-MVP):** real jail time, certain characters cut you off, save-significant consequences

---

## 4. Time & Calendar

- **Real-time clock** during gameplay, ~1 in-game minute = ~0.7 real seconds (tunable). A full day is roughly 14 real minutes of activity.
- **Pause** in menus, dialogue, and minigames.
- **Stamina** drains with effort actions (B&E, running, fighting, prolonged labor) and resets on sleep. Out of stamina = slower movement, can't do skill checks. *Including in MVP because it's hard to bolt on later — it gates how much you can do per day, which is core to the loop.*
- **Sleep at home** = full restore. **Pass out elsewhere** = wake up with reduced stamina, possibly robbed.

---

## 5. Economy

### Income sources (MVP)

| Source | Risk | Setup Cost | Skill Ceiling | Time Cost |
|---|---|---|---|---|
| Weed growing | Low (at home) | Medium (gear) | Medium (strain quality) | Slow (days per cycle) |
| Pickpocketing | Medium | None | High (timing) | Fast (seconds per attempt) |
| B&E | High | Low (tools) | High (planning) | Medium (minutes per house) |

These are intentionally varied across **risk × time × skill** axes so they don't redundantly fill the same niche. The player should genuinely choose between them based on situation, stamina, heat level, and time of day.

### Expenses (MVP)

- **Rent:** weekly, eviction if missed twice
- **Food:** stamina maintenance — skip too long and tomorrow's stamina cap drops
- **Supplies:** soil, seeds, lockpicks, etc.
- **Gifts:** social currency
- **Bribes / fines:** when caught

### Selling product

Single MVP fence. Pays per gram by quality tier. Post-MVP: multiple buyers with relationships, prices, preferences, and risks.

### Money laundering — *deferred post-MVP.* Worth flagging now: when introduced, it creates a meaningful split between "dirty cash" (can't spend at the bank, rent, certain shops) and "clean cash" (can). Build the wallet system with this split anticipated, even if both pools start as one.

---

## 6. Income System: Weed Growing

The player's apartment has space for a few growing pots. The full chain is:

```
empty pot → [+ soil] → soiled pot → [+ seed] → seeded pot
→ [+ water, daily, N days] → mature plant → [harvest] → buds + new seed (chance)
```

**Stages (visual + gameplay):**
1. Seedling (2 days)
2. Vegetative (4 days)
3. Flowering (4 days)
4. Mature — harvest window (3 days, declining quality if missed)

**Quality factors (MVP — keep simple):**
- Watering consistency (missed days reduce yield)
- Light source (basic lamp = baseline, grow lamp = +quality, requires electricity upgrade)
- Strain (post-MVP — start with one strain)

**Selling:**
- Raw buds sell to fence at base price
- Post-MVP: curing process, edibles, packaging into baggies for street sale at higher margin/risk

**Mechanic style:** Stardew-direct. Held item + interactable container = action. No menus. Click soil bag on empty pot, click seed on soiled pot, click watering can on seeded pot, click mature plant to harvest. The mechanic itself is muscle memory; the *interest* comes from balancing water cycles against your day.

---

## 7. Income System: Pickpocketing

**Target selection:** NPCs in public spaces have a "pocket value" (cash, sometimes items) and an "awareness" stat. Crowded areas reduce witness risk.

**Minigame (proposal — to refine):**
- Approach target undetected (positioning + their facing direction)
- Press interact → minigame opens (paused world)
- Timing-based: a moving indicator must be stopped in a green zone. Green zone shrinks with target awareness, grows with player skill.
- Three outcomes:
  - **Clean:** take wallet, nobody notices
  - **Detected, fled:** target shouts, witnesses gain awareness of player, no arrest unless cop nearby
  - **Caught:** if cop in line of sight, immediate arrest sequence

**Risk variables:**
- Target awareness (drunk = low, alert = high)
- Witness count nearby
- Cop proximity
- Player's "Sleight" skill (improves with practice)

**Why timing-based:** fast, repeatable, low-friction, and scales naturally to skill. Doesn't require complex AI from NPCs.

---

## 8. Income System: Breaking & Entering

Higher-stakes, longer-form. Targets **houses in adjacent neighborhoods** (procedurally generated — see §12). Player's home neighborhood is *not* a B&E target — it's the social hub.

**Loop:**
1. **Cash a target:** travel to a procedural neighborhood, observe houses (lights on = occupied, schedules visible through windows). Costs in-game time.
2. **Plan the entry:** pick door, window, or back. Each has different lockpick difficulty / noise / visibility.
3. **Enter and search:** stamina-costed search of containers. The longer you stay, the more loot, but rising heat meter triggers neighbors / silent alarms / police dispatch.
4. **Exit:** with loot, before heat caps.

**Minigame elements:**
- **Lockpicking:** tension/pin minigame (Skyrim-style is the worn but legible reference). Skill-gated.
- **Search:** click containers, time cost per container, RNG loot tables.
- **Stealth:** footstep noise, sleeping occupants, dogs.

**Risk / reward:**
- Bigger / nicer houses = better loot, more security, occupants more likely to call cops fast
- Heat persists — hitting the same neighborhood repeatedly raises baseline difficulty there for in-game weeks

**Failure cases:** caught inside (run / fight), tripped alarm (timer to escape), woken occupant (run / fight / rare lethal option — flag for design discussion).

---

## 9. Relationships & Dialogue

This is the heart of the game. Mechanics elsewhere are simple precisely so the writing and relationships can carry weight.

### Relationship model — *not* hearts

Stardew's single-axis hearts is too thin for adult, morally complex characters. MVP proposal:

- **Affinity** (-100 to +100): how much they like the player
- **Trust** (0 to 100): how much they'd bet on the player's word/competence
- **Knows** (flag set): aware of player's criminal activity (specific or general)

Examples:
- A romance interest could be high affinity, low trust, doesn't know — "I like you but you're shady"
- A criminal mentor could be medium affinity, high trust, knows everything — "You're an asshole but you're my asshole"
- A straight-world neighbor could be high affinity, high trust, doesn't know — and the *fear of them finding out* is the dramatic engine

Both axes move from interactions, gifts, completed favors, witnessed events. Thresholds gate dialogue lines and (post-MVP) events.

### Dialogue system

Building on the Stardew-style key-lookup approach we discussed:

- Each NPC has a dialogue dictionary (JSON or Godot Resource files for hot-reload during writing)
- Keys encode conditions through naming convention: `Apartment_Mon_rainy`, `summer_Wed`, `Wed`
- Lookup walks priority list, picks first match
- Per-line **preconditions** (mini-DSL) handle anything keys can't: `affinity Mira 60/trust Mira 40/!knows Mira/time 1800 2400`
- In-string formatting for portraits, branches, and substitutions: `$h` (happy portrait), `$b` (page break), `$q`/`$r` (question/response branching), `%name`/`%nbhd` (substitutions)
- **Hot-reload from disk** during development — non-negotiable for writer iteration speed

### Events (post-MVP, but architect for it now)

Stardew-style cutscenes triggered by location + time + precondition. They can `pushDialogue()` follow-up lines onto an NPC's stack so the next conversation references what just happened. **Don't build events yet, but the dialogue system should support the push-stack pattern from day one.**

### Gifts

Gifting is ambient relationship-building in addition to dialogue choices. Stardew uses universal Loves/Likes/Neutral/Dislikes/Hates with per-NPC overrides — solid pattern, keep it. Gifts can include cash, drugs, favors, contraband — different from Stardew's wholesome eggs and amethysts, which expands the design space (giving a recovering addict drugs is a relationship-destroyer; giving an undercover cop a baggie is a disaster).

---

## 10. Cast (MVP — 6 Characters)

Roles, not specific characters. Each role is chosen to stress-test a different facet of the relationship/dialogue/economy systems with minimum cast size.

| # | Role | System purpose |
|---|---|---|
| 1 | **The Fence** | Economy node — buys product. Tests trust system, gates progression. |
| 2 | **The Mentor / Old Hand** | Tutorial-ish but human. Tests "knows everything" relationship, criminal advice. |
| 3 | **The Romance** | Romantic arc. Tests affinity scaling, gift system, branching dialogue under pressure. |
| 4 | **The Straight-World Anchor** | Neighbor / shopkeep / regular person. Tests "doesn't know" tension, secret-keeping. |
| 5 | **The Rival / Antagonist** | Competing dealer or hostile peer. Tests negative affinity, conflict dialogue. |
| 6 | **The Wildcard** | An addict, a sex worker, a beat cop, a runaway — pick what serves the world's texture. Tests morally complex helping/hurting. |

Each gets:
- Daily / weekly schedule with named locations
- Birthday
- Gift preferences
- Dialogue dictionary covering: time-of-day, weather, weekday, location, affinity tiers, trust tiers, knows-flag variants
- A few placeholder lines for now — full writing comes later

---

## 11. Locations (MVP)

**Handcrafted (the world the player lives in):**
1. **Player's Apartment** — bed, kitchen, growing area, storage. Upgradable post-MVP.
2. **The Neighborhood (street + adjacent buildings)** — connective tissue, public space for encounters
3. **The Bar / Diner** — hangout, late-night socializing, schedule destination for several NPCs
4. **The Bodega / Corner Store** — supplies, food, the Straight-World Anchor's workplace
5. **The Fence's Spot** — back room of a pawn shop, autobody, etc. Selling product happens here.

**Procedural (B&E targets):**
6. **Adjacent Neighborhood(s)** — see §12

That's six handcrafted areas, which is a lot for MVP — be prepared to cut to four if scope balloons. Bar and bodega are the most cuttable (functions can fold into other spaces).

---

## 12. Procedural Generation for B&E

**Ambition level for MVP: low.** Don't build a full PCG system. Build a "handcrafted rooms, procedurally assembled and dressed" system — close to how Spelunky's level chunks work.

**Approach:**
- Author ~10–20 **room templates** (living room, kitchen, bedroom, bathroom, hallway) at multiple sizes
- Author ~3 **house layouts** as connection graphs (1-bedroom apt, 2-bedroom house, 3-bedroom house)
- At runtime, pick a layout, fill its slots with random matching room templates
- Dress with random furniture / loot containers / decor from theme-tagged pools
- Occupants generated with simple schedules (sleeping, watching TV, out)

**Variety comes from:**
- Wealth tier (changes loot pool and decor pool)
- Occupancy state (empty / sleeping / awake)
- Security tier (locks, alarms, dogs)

**What this gives you:** infinite-feeling targets without infinite handcrafting. Every room individually is handcrafted-quality; only the *combination* is procedural. This is the right tradeoff at MVP scope.

---

## 13. Heat / Police System (MVP-light)

A heat system is included in MVP because it's deeply coupled to the income loop — bolting it on later requires re-tuning every risk/reward decision.

**Two heat pools:**

- **Personal heat** (0-100): how interested the cops are in *you specifically*. Rises from witnessed crimes, decays slowly over days. High personal heat = more patrols on routes you frequent, higher arrest severity.
- **Area heat** (per neighborhood, 0-100): how alert a neighborhood is. Rises from B&Es and visible crimes there. Decays over a week or two. High area heat = more witnesses calling in, faster police response, residents alarmed.

**What it affects (MVP):**
- Patrol density on streets
- Police response time during crimes
- Arrest severity tier (see §3)

**What it doesn't do yet (post-MVP):**
- Detective investigations, named cop NPCs hunting you, news stories, witnesses identifying you specifically

---

## 14. Systems Deferred Post-MVP

Listed here so they're not forgotten and so MVP architecture can leave hooks for them:

- **Combat** — for now, "caught" = arrest sequence. No fistfights, no weapons. Architect inventory/items so weapons are addable.
- **Money laundering / dirty vs. clean cash** — wallet should support multiple currency pools even if MVP uses one
- **Hunger and detailed needs** — stamina is the only need; food just maintains stamina cap
- **Inventory weight / limits** — soft slot limits only
- **Moving up (better neighborhood)** — apartment is fixed in MVP
- **Story arcs and named events** — dialogue system supports them; just no content authored yet
- **Multiple fences / dealer relationships** — single fence for MVP
- **Romance progression to physical content** — relationship system supports the curve, content not authored
- **More characters, more income sources, more locations** — obvious expansions
- **Detective AI, news system, reputation, gangs, territory** — long-term

---

## 15. Technical Architecture (Godot)

**Engine:** Godot 4.x (latest stable). 2D pixel-art project.

**Project structure (proposal):**
```
res://
├── scenes/
│   ├── player/
│   ├── npcs/
│   ├── rooms/             # handcrafted scenes
│   ├── procedural/        # B&E room templates
│   ├── ui/
│   └── minigames/
├── scripts/
│   ├── systems/           # time, economy, heat, relationships, save
│   ├── dialogue/          # parser, runtime, hot-reload
│   └── components/        # reusable behaviors (interactable, schedule, etc.)
├── data/                  # editable text data — hot-reloadable
│   ├── dialogue/          # per-NPC dialogue files
│   ├── items.json
│   ├── npcs.json
│   ├── schedules/
│   ├── loot_tables/
│   └── room_templates/
└── art/
    ├── tilesets/
    ├── sprites/
    └── ui/
```

**Architecture principles:**
- **Data-driven everything.** Items, dialogue, schedules, loot tables, NPC definitions live in editable text files (JSON or Godot `.tres` Resources). The engine is a runtime, not a content store.
- **Hot reload during dev.** `F5` reloads dialogue/items/schedules without restarting. Critical for writer iteration.
- **Singletons (Autoloads)** for: `TimeSystem`, `EconomySystem`, `RelationshipSystem`, `HeatSystem`, `SaveSystem`, `DialogueSystem`. They're long-lived and accessed everywhere; this is what autoloads are for.
- **Signals for cross-system events.** Crime committed → emits signal → heat system, relationship system, dialogue system all react independently. Keeps systems decoupled.
- **Save system** = serialize all singleton state + per-scene state (NPC positions, plant states, container contents) to a single save file. Decide save format early (JSON readable for debugging, binary for ship). Build it from day one — retrofitting saves is famously painful.

---

## 16. Open Questions (deliberately unresolved)

These are decisions to make during prototyping, not now:

1. **Stamina granularity** — points (Stardew's energy) or continuous bar? Points are more readable; bars feel modern.
2. **Pickpocket minigame mechanic** — timing bar is the proposal; rhythm-based or QTE alternatives worth prototyping.
3. **Lockpick minigame** — Skyrim-style is legible but tired. Better idioms exist; worth one round of exploration.
4. **NPC AI for B&E houses** — full schedules or simple state machines (sleeping/idle/alerted)? Probably the latter for MVP.
5. **Witness system** — do witnesses identify you specifically, or do crimes just generate generic heat? Generic for MVP, identification later.
6. **Single save slot vs. multiple** — affects how punishing failure can be.
7. **Tone calibration on the wildcard NPC** — pick what role only after the other five are written so you can fill the gap the cast is missing.
8. **Whether B&E lethality (occupant violence) is in MVP** — leaning no, since it pulls combat in with it. Worth revisiting.

---

## 17. MVP Definition of Done

The MVP is "done" when a new player can:

1. Wake up in the apartment, learn the basic loop in their first in-game day
2. Grow weed from seed to harvest over an in-game week
3. Sell product to the fence
4. Pickpocket at least one NPC successfully and unsuccessfully
5. B&E at least one procedural house successfully and unsuccessfully
6. Build relationship with at least one NPC to a meaningful threshold (gated dialogue + a noticeable behavior change)
7. Get arrested at each severity tier and experience the consequences
8. Survive (or fail to survive) a full in-game month
9. Save and reload without state loss

If all nine are achievable in a vertical slice, the MVP is done and the question "is this loop fun?" can be answered with real playtest data.
