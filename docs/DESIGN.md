# Split the Ocean for Eggs: design

## The world

One shore. The beach and five bases sit in a row on the land side, enclosed by 70-stud walls behind and on both sides.
In front of them the ocean runs to the horizon, framed by two rocky headlands and a lighthouse. Three leaderboards stand
against the back wall. A server holds 5 players, one base each.

## Core loop

1. **Walk to the shore.** The light sand strip along the shoreline is the **Split Zone**. Stepping onto it pulls out
   your Sea Staff.
2. **Charge and release.** Hold click (or the HOLD button on touch) to fill the charge bar, then let go. A tap gives 45%
   of the distance; a full bar gives full distance and 4 more seconds before the sea shuts.
3. **The sea parts.** A cutscene plays: a close shot as the staff goes up, then the camera cranes up and back while the
   corridor rips open down its whole length, with letterbox bars, a flash and a title showing the depth and the number
   of eggs revealed. You can't move until it ends (2.6 seconds).
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
   - **Rarity:** deeper eggs can be rarer. Luck and depth both shift the odds toward rare eggs.
   - **Placement:** every egg is placed where a sprint from the shore reaches it before the water does.
   - **Variants:** Gold (×2.5) and Rainbow (×6) chances scale with √Luck.
   - Walk over an egg to pick it up. You can carry 1 egg (2 with the Double Carry pass).
6. **Carry it home.** The egg stays on your head, and an "Eggs 1/1" counter stays on screen, until you walk into your
   own base. Reaching the beach makes it safe, but it is only planted when you step inside your fence. With full hands
   you can't grab another egg or part the sea again.
7. **Hatch.** Planted eggs incubate in a base slot. When the timer reads *Ready!*, use the egg's prompt (or *Hatch All
   Ready* in the Eggs menu). The hatch cutscene plays first; the animal appears in your base, and any "new Index entry"
   news is announced, only after it ends.
8. **Grow.**
   - **Strength:** step onto the pink pad in your base. Reps start on their own: the barbell goes up and down, and each
     finished rep adds Strength. Step off to stop. The staff is put away while you train.
   - **Heavier weights:** buy them on the yellow pad for more Strength per rep.
   - **Luck:** buy it in the **Buy** menu.
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
- It plants carried eggs only when their owner is inside their own base.

## Progression

Depth gates rarity. As a fraction of the 300-stud reach: Kelp eggs start about 56 studs out, Pearl at 111, Treasure at
167, Abyss at 222 and Leviathan at 278.

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

## Feedback while you play

- **Guide:** until a new player has planted an egg, hatched one and trained once, a line of text says what to do next
  and a trail of green arrows on the ground leads there (routing through the base gate). While carrying, it always
  points you home.
- **Sea bar:** while your sea is open, a bar at the top drains from both ends like the walls, with the seconds left. It
  turns red in the last 5 seconds, a tick sounds each second, and the screen edge pulses red as the walls get close.
- **Egg counter:** "Eggs 1/1" stays up from the grab until the egg is planted, red in the sea and green on land.
- **Banners:** large centered messages for the moments that matter (the sea parting, SAFE, SWEPT AWAY, offline cash).
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

## Systems

- **Bases:** 5 per server, assigned on join. You start with 4 slots, and each upgrade adds 2 (up to 20). Animals and eggs
  in slots are rendered by the server so everyone can see your base; animals hop around, animated on each client.
- **Pets menu:** *Place Best* fills the base with your highest earners from the base and storage. Incubating eggs keep
  their slots.
- **Leaderboards:** three boards on the back wall rank Most Cash Earned, Strongest and Most Eggs. They are global
  (OrderedDataStores), merged with live numbers for everyone in the server, and refresh every minute. Without DataStore
  access they rank the current server only. Cash, Strength and Eggs also show in the Roblox player list.
- **Index:** a book of all 21 animals. Undiscovered ones are dark silhouettes, and each new discovery pays a one-time
  reward of 120 seconds of that animal's income.
- **Playtime gifts:** 12 rewards unlock at 1 to 60 minutes of play in a session, and the progress resets when you leave.
  "Skip All" is a developer product.
- **Daily streak:** a 7-day cycle based on UTC days. Missing a day resets the streak.
- **Robux:** passes are x2 Strength, x2 Luck, x2 Cash, Double Carry and Fast Hatch. Products are Starter Pack, two
  cash packs (scaled to your income), Luck Potion (x2 for 15 minutes), Instant Hatch and Skip Playtime. A purchase is
  acknowledged only after it has been saved, so it is never granted twice or lost.

## Art direction

Everything is built from blocks in code. Roblox no longer draws the old stud texture, so the toy-box look comes from
checkered tiles on the ground, seabed and base floors.

- **Models:** pixel eggs stacked layer by layer on twig nests; blocky animals from a few templates (crab, bird, fish,
  quadruped, seal, octopus, turtle, frog, serpent); voxel palms, umbrellas, barbells and a lighthouse. Gold and Rainbow
  variants recolor the model.
- **Ocean:** foam crests drifting in from the horizon; rolling wave-topped walls that grow taller as they close, foam
  churning at their feet, and wet sand along the corridor floor.
- **UI:** chunky gradient buttons with thick black outlines and Fredoka One, model icons, and labels over eggs and
  animals sized in studs so they shrink with distance.
