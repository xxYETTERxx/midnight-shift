Transparent bottom wall tiles
Consistent character animations
polish pixel gitter

A few smaller things that I'd genuinely defer:

%player and %nbhd substitutions — %name works, the others are wired into the parser but unimplemented. Defer until you actually have a player name and a neighborhood concept (probably Stage 5 or later).
has_item precondition — parsed but stubbed false. Wire up when Inventory grows a has_item_id() method.
NPC idle animation — your TestMale has an AnimatedSprite2D. If it's currently a single-frame static sprite that's fine for now; idle animations are a Stage 9 NPC-expansion concern.
