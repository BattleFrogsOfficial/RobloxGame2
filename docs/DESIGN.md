# Split the Ocean for Eggs: design

## The world

One shore. The beach and five bases sit in a row on the land side, enclosed by 70-stud walls behind and on both sides.
Sheer rock walls continue straight out from those side walls at the same height, so the ocean is one long channel that
runs to the horizon with nothing visible past its sides. A lighthouse stands on the east cliff, and three leaderboards
stand against the back wall. A server holds 5 players, one base each.

## Core loop

1. **Walk to the shore.** The light sand strip along the shoreline is where you can part the sea. Stepping onto it pulls
   out your Sea Staff.
2. **Charge and release.** Hold click (or the HOLD button on touch) to fill the charge bar, then let go. A tap gives 45%
   of the distance; a full bar gives full distance and 4 more seconds before the sea shuts.
3. **The sea parts.** A 4-second cutscene plays, and you can't move until it ends:
   - **Coil, leap, slam.** Your character drops into a deep crouch and twists away with the staff wound far back,
     launches off the ground swinging it overhead, then comes down into a lunge and drives it forward and down. The
     camera arcs around in front of them the whole time.
   - **The slam** (about a third of the way in) is when the sea starts to tear: a shockwave ring and debris burst from
     the character's feet, the screen flashes and the camera jolts.
   - **Parting.** The character rises off the ground with both arms pushed out in front, then slowly spreads them
     wide apart, straining, as the camera swings behind and rises to watch the sea peel open from the shore outward.
     Each stretch of water surges well above its resting height as it tears, a fountain of spray rides the tear, and
     chunks of water are flung up and out to both sides.
   - Letterbox bars and a title show the depth and the number of eggs revealed.
   - The camera then glides back to exactly where your own camera was, so control returns without a cut.
   - **Three casts.** Each split rolls which one you get. The rarer two multiply your Luck for the eggs in that split:

     | Cast | Chance | Luck | Cutscene | Walls |
     |---|---|---|---|---|
     | Split | 85% | x1 | 4s | 26 studs |
     | Super Split | 12% | x5 | 5.2s | 44 studs |
     | Poseidon's Wrath | 3% | x10 | 8s | 78 studs |

     A **Super Split** shows its name huge and tilted across the screen while lightning strikes around you; you spin
     as you leap about twice as high, hit the ground harder, and "5x LUCK!" fills the screen. **Poseidon's Wrath** flies
     you far into the sky, where you hang with both arms raised in a lightning storm, then dive and land hard: a ring
     of bolts, rolling shockwaves, nine times the flung water, the tallest walls, and "10x LUCK!". The bonus stays on
     the sea bar for the whole split. In Studio, `player:SetAttribute("ForceCast", "Super")` (or `"Poseidon"`) forces
     one for previewing.
   - **Depth** grows with Strength: `length = (30 + 13.2 · log2(1 + Strength/5)) × chargeFactor`, up to 300 studs, which
     takes about 7M Strength.
   - **Width** starts at 26 studs and grows to 44 with Strength.
4. **The walls close.** From the moment the cutscene ends, both side walls move inward at a steady rate and meet after
   `6 + 0.15 × length + 4 × charge` seconds. A sprint to the far end and back takes `0.125 × length` seconds, so there
   is always time for one deep trip, but not much to spare.
   - An egg is gone the moment the water covers it, so eggs near the edges vanish first.
   - If the walls meet while you're between them, you're caught.
5. **Grab an egg.** Your eggs sit on the seabed and only you can see them.
   - **Count:** `2 + length/34 + log2(Luck)`, up to 16.
   - **Rarity:** the sea is divided into six luck zones by depth (see Progression). Each zone unlocks one more egg
     tier than the last and multiplies your Luck for eggs found there.
   - **Placement:** every egg is placed where a sprint from the shore reaches it before the water does.
   - **Variants:** an egg can be Gold (×2.5 income, 5% base chance), Platinum (×4, 1.8%) or Rainbow (×6, 0.6%). The
     chances scale with √Luck, and the animal that hatches keeps the egg's variant.
   - Walk up to an egg and hold **E** for a third of a second to pick it up (a tap-and-hold prompt on touch, the
     prompt button on gamepad). Walking over it does nothing. You can carry 1 egg (2 with the Double Carry pass).
6. **Get out.** The egg stays on your head, and an "Eggs 1/1" counter stays on screen, while you are in the sea.
   Stepping back onto land flashes the screen green with a small shake and puts the egg in your inventory: it appears
   on your hotbar as a tool, next to the Sea Staff (and in the **Eggs** window). With full hands you can't grab another
   egg.
7. **Place it.** Pick the egg on your hotbar while you are in or right by your plot. A see-through copy of it follows
   your mouse over the plot (on touch it sits in front of you until you tap a spot). Click or tap to put it down
   anywhere inside the fence, at least 5 studs from the next egg. The preview ring is green where it fits and red
   where it doesn't. *Put away* (Q) returns the egg to the hotbar. *Place* in the **Eggs** window does the same as
   picking the egg on the hotbar, and takes you to your plot if you aren't there. Incubation starts when the egg is
   put down. The number of eggs and animals a base holds is still set by its size (4, +2 per upgrade, up to 20).
8. **Hatch.** When an egg's timer reads *Ready!*, use the egg's prompt (or *Hatch All
   Ready* in the Eggs menu). The hatch cutscene plays first; the animal appears in your base, and any "new Index entry"
   news is announced, only after it ends.
9. **Grow.**
   - **Strength:** step onto the pink pad outside your base, left of the gate. Reps start on their own, 1.4 seconds each: a clean-and-press.
     Your character drops into a deep squat with the bar at the shoulders, drives up with a small hop as the bar
     punches overhead, holds the lockout with shaking arms, and lowers it. Each lockout sends a shockwave ring and
     debris out from the feet, kicks your camera, and adds Strength. Step off to stop. The staff is put away while you
     train.
   - **Heavier weights:** the weights stall next to the pad opens a menu of all eight barbells; buy the next one for
     more Strength per rep. The barbell rests on the pad when you aren't training and is in your hands when you are.
   - **Luck and Speed:** sold at the shop stall on the beach (the **Buy** button takes you there). Speed raises your
     walk speed from 16 by 1 per level, up to 30, so you can get deeper and back before the sea closes.
   - **Base size:** upgrade it at the sign by the gate.

### Getting caught

You're caught if the walls meet on you, if you go past the end of the corridor, or if you walk into the sea without
parting it. Your character goes limp and is thrown high into the air and back onto the beach, a large banner fills the
middle of the screen ("SWEPT AWAY!" with what you lost, or "THE SEA THROWS YOU BACK!"), and the run ends. Any eggs you
were carrying are lost.

## Visibility model

| | Splitter | Everyone else |
|---|---|---|
| Ocean water | cutscene, parted corridor, closing walls | closed sea |
| Eggs in the corridor | visible, with name and rarity labels | not visible |
| The splitter | walks down the sandy ramp on the seabed | walks into the water |
| Carried egg | above their head | above their head |
| Being thrown back | visible | visible |

This works because **the water is not on the server at all**. `client/Ocean.luau` builds the sea locally: static slabs
out to the horizon, plus a near section it reshapes every frame while your own split is active (left, right and far
water, rows of wall segments whose tops roll like waves, foam, wet sand). The seabed, ramp and coral are real server
Parts, so the splitter stands on solid ground that everyone shares.

The server is authoritative for everything that matters:

- It decides the corridor (center, width, depth, duration, start time on `workspace:GetServerTimeNow()`) and rolls the
  eggs.
- `Formulas.halfWidth` gives server and client the same wall positions at any moment, so the walls you see are the
  walls the server checks against (with 2 studs of grace for network delay).
- At 10 Hz it checks every character seaward of the shoreline, at any height. Anyone outside an open corridor is thrown
  back.
- It accepts a grab only if the egg exists, hasn't been taken, hasn't been covered, and the player is within reach.
- It moves carried eggs into the inventory once their owner is back on land.
- It places an egg only at a spot inside its owner's own fence, clear of the other eggs, and only while the base has
  room.

## Progression

The sea is divided into six **luck zones** by depth. Each zone multiplies your Luck for eggs found in it and unlocks
one more egg tier than the zone before:

| Zone | Starts at | Luck | Rarest egg |
|---|---|---|---|
| Shallows | shore | x1 | Coral |
| Reef | 56 studs | x2 | Kelp |
| Kelp Forest | 111 studs | x3.5 | Pearl |
| Twilight | 167 studs | x5.5 | Treasure |
| Trench | 222 studs | x8 | Abyss |
| Abyss | 278 studs | x11 | Leviathan |

An egg's rarity odds are its tier's base weight times `(Luck x zone luck)^(0.35 x (tier - 1))`. Each zone's start is
marked by a glowing line across the seabed with a sign, and the bar at the top of the screen shows all six zones, which
ones your corridor reaches, and where you are.

| Egg | Rarity | Hatch | Animals (income $/s) | Size |
|---|---|---|---|---|
| Shell | Common | 15s | Crab 4, Seagull 6, Turtle 10 | ×1 |
| Coral | Uncommon | 40s | Pufferfish 18, Seal 26, Flamingo 38 | ×1.5 |
| Kelp | Rare | 1:30 | Frog 70, Otter 100, Pelican 145 | ×2.2 |
| Pearl | Epic | 3:00 | Penguin 280, Octopus 400, Dolphin 560 | ×3.2 |
| Treasure | Legendary | 6:00 | Parrot 1.2K, Shark 1.7K, Walrus 2.4K | ×4.8 |
| Abyss | Mythic | 12:00 | Anglerfish 5.5K, Kraken 7.8K, Narwhal 11K | ×7 |
| Leviathan | Secret | 20:00 | Sea Dragon 28K, Ghost Whale 42K, Golden Kraken 65K | ×10 |

Rare animals are deliberately enormous: a Secret pet is ten times the size of a Common one and towers over its base, so
a strong player is obvious at a glance.

Inside an egg the first animal is the most common (60/30/10), and Luck nudges the odds toward the rarer two.

`tests/pacing.sim.luau` plays the economy with a simple bot (one egg per run, 25 seconds of training between runs, buy
what it can afford). Across several seeds it finds its first Kelp egg in 2 to 12 minutes, Pearl in 6 to 19, Treasure in
20 to 40, Abyss in 70 to 90 minutes, and Leviathan after 4 to 6 hours. Re-run it after changing costs or curves.

Income keeps flowing while you're away: 50% of your $/s for up to 4 hours. Eggs keep incubating offline too, because
their timers use `os.time()`. If you leave while carrying an egg you had already brought to land, it goes into storage.

## Character animation

The staff cast and the barbell reps are animated in code, with no uploaded animation assets. The server publishes only
timing, as player attributes (`CastStart`, `Training`, `RepStart`, `WeightTier`). `client/Poses.luau` turns that into
full-body poses every frame on every client: each move is a set of keyframe tracks for the shoulders, elbows, hips,
knees, waist and the root joint (which moves and tilts the whole body, for the crouches, the leap and the hop). It
changes each joint's resting offset from the value it had when the move began and restores it when the move ends. The
engine's Animator never writes that offset, so nothing overrides the pose, and whatever default animation is playing
layers on top.

- **Joint types:** characters come with either classic `Motor6D` joints (offset = `C0`) or, on rigs with Roblox's avatar
  joint upgrade, `AnimationConstraint` joints (offset = the `CFrame` of its `Attachment0`). Both are handled, here and
  in the ragdoll.
- **Rigs:** R15 uses every joint. R6 has no elbows, knees or waist, so it gets the shoulders, hips and whole-body
  movement.
- **Barbell:** placed at the midpoint of the two hands each frame, so it is always in the character's grip.
- **Staying put:** while your own character is casting or training and you aren't steering, it is pinned where it
  stands, so the moving body can't nudge it off the pad.
- **Diagnostics:** each move prints one `[Poses]` line (avatar type, number and type of joints found) to the Output
  window.

The build number (`Config.Build`) is shown in small print at the top of the screen and is part of the place file's
name, so it is always clear which build is running.

## Inside the sea

Everything inside a parted sea is drawn only for the player who parted it (`client/Depths.luau`):

- **Zone lines:** a glowing strip across the seabed where each luck zone starts, with a sign giving its name and luck.
- **Kelp** sways along both sides and is swallowed as the walls close in.
- **Bubble vents** send streams of bubbles up from the floor.
- **Mist** rolls along the corridor floor.
- **Fish** swim inside the water walls, and every second or two one leaps across the gap over your head.
- **Falling water:** chunks break off the tops of the walls and drop into the corridor.
- **Light:** the view turns bluer and dimmer the deeper you go.

## Feedback while you play

- **Guide:** until a new player has placed an egg, hatched one and trained once, a line of text says what to do next
  and a trail of green arrows on the ground leads there (routing through the base gate). With an egg in the inventory it points you to your plot.
- **Zone bar:** while your sea is open it replaces Buy/Base/Sell at the top: one colored segment per luck zone with its
  multiplier, the rarest egg that zone can hold underneath, zones beyond your corridor greyed out, and your face
  marking how deep you are.
- **Sea bar:** under the zone bar, a bar drains from both ends like the walls, with the seconds left. It turns red in
  the last 5 seconds, a tick sounds each second, and the screen edge pulses red as the walls get close.
- **Egg counter:** "0/1" floats over your head while a sea is open, and a panel reading "Eggs 1/1" stays up from the
  grab until you are back on land.
- **Banners:** large centered messages for the moments that matter (the sea parting, a special cast's luck, SWEPT
  AWAY, offline cash). Reaching land safely is a green flash and a shake, with no banner.
- **Egg odds:** the Buy menu shows the chance of each rarity at the deepest point you can currently reach.
- **Touch:** phones and tablets get a large HOLD button for charging, so it doesn't fight the camera.

## HUD

Every HUD element's position is data in `client/ui/Layout.luau`. `tests/layout.spec.luau` checks, on ten desktop, tablet
and phone screen sizes, that no element overlaps another, leaves the screen, or covers the areas Roblox's own UI uses
(top bar buttons, player list, hotbar, mobile thumbstick and jump button). Elements that can never be shown together
(for example the charge meter and the egg counter) are listed there and may share space.

Icons are small 3D models built by `Voxel.icon` (cash stack, barbell, clover, egg, book, chest, gift, calendar, potion,
clock) and shown in viewports. There are no emoji in the interface; the playthrough test scans every label to keep it
that way.

- **Left:** Pets and Eggs tiles, then Cash, Strength and Luck with large icons, then a feed of income ticks.
- **Right:** a round Starter Pack badge with the prize bursting out of it, a rainbow pass banner under it (desktop
  only), then four tiles (Index, Shop, Gifts, Daily). Tile icons are larger than their frames and spill out of the
  top; tiles can carry a tag ribbon and a round count badge.
- **Player list:** Roblox's default player list is switched off, because it would sit on top of the right column and
  the world has its own leaderboards.

## Systems

- **Bases:** 5 per server, assigned on join. A base holds 4 eggs and animals to start, and each upgrade adds 2 (up to
  20). Eggs stand wherever their owner put them, and animals hop around the whole plot; the server renders both so
  everyone can see your base, and each client animates the hops. The whole fenced plot is free: the training pad and
  weights stall stand just outside the front fence left of the gate, and the *Upgrade Base* sign to its right.
- **Pets menu:** *Place Best* fills the base with your highest earners from the base and storage. Incubating eggs stay
  where they are.
- **Leaderboards:** three boards on the back wall rank Most Cash Earned, Strongest and Most Eggs. They are global
  (OrderedDataStores), merged with live numbers for everyone in the server, and refresh every minute. Without DataStore
  access they rank the current server only. Cash, Strength and Eggs also show in the Roblox player list.
- **Index:** a book with a tab for each variant (Normal, Gold, Platinum, Rainbow). Each row is an egg, an arrow, and the three
  animals it hatches, on backgrounds in the egg's rarity color; animals you haven't hatched in that variant are dark
  silhouettes. Every egg you complete (all three animals in one variant) adds +10% to all your income, permanently,
  up to +280%.
- **Playtime gifts:** 12 rewards unlock at 1 to 60 minutes of play in a session, and the progress resets when you leave.
  "Skip All" is a developer product.
- **Daily streak:** a 7-day cycle based on UTC days. Missing a day resets the streak.
- **Robux:** passes are x2 Strength, x2 Luck, x2 Cash, Double Carry and Fast Hatch. Products are Starter Pack, two
  cash packs (scaled to your income), Luck Potion (x2 for 15 minutes), Instant Hatch and Skip Playtime. A purchase is
  acknowledged only after it has been saved, so it is never granted twice or lost.

## Art direction

Everything is built from blocks in code. Roblox no longer draws the old stud texture, so the toy-box look comes from
checkered tiles on the ground, seabed and base floors.

- **Models:** pixel eggs stacked layer by layer on twig nests; animals from a few templates (crab, bird, fish,
  quadruped, seal, octopus, turtle, frog, serpent); voxel palms, umbrellas, barbells and a lighthouse. Gold, Platinum
  and Rainbow variants recolor the model (Platinum is a pale, highly reflective silver-blue).
- **Resolution:** a Common animal's pixel is 0.16 studs and an egg's is 0.21. Bodies, heads and shells are rounded
  lumps stacked from one-pixel layers with clipped corners; details are single pixels (eyes with highlights, toes,
  feather tips, fins, teeth, shell plates, speckles). Animals are 32 to 73 parts each and eggs 70 with their nest.
- **Ocean:** foam crests drifting in from the horizon. The corridor walls are stepped (a wide base, a narrower upper
  tier set back from it, a foam crest) with rolling tops; they grow taller as they close, with foam churning at their
  feet and wet sand along the corridor floor.
- **UI:** chunky gradient buttons with thick black outlines and Fredoka One, model icons, and labels over eggs and
  animals sized in studs so they shrink with distance.
