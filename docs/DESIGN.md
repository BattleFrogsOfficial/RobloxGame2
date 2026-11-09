# Split the Ocean for Eggs: design

## Core loop

1. **Walk to the shore.** Two beaches face a long ocean in the middle of the map. The light sand strip along each
   shoreline is the **Split Zone**. Stepping onto it pulls out your Sea Staff.
2. **Charge and release.** Hold click (or tap and hold) to fill the charge bar, then let go. A tap still works but gives
   only 45% of the distance. A full bar gives full distance plus up to +4s of open time.
3. **The sea parts.** A corridor opens straight out from where you stand. Walls of water rise on both sides and at the
   far end.
   - **Depth** grows with Strength (`length = (34 + 18 · log2(1 + Strength/5)) × chargeFactor`, up to 214 studs, which is
     nearly the opposite shore).
   - **Open time** is `5 + 1.4 · log2(1 + Strength/5) + 4 · charge` seconds.
4. **Grab eggs.** Your eggs sit on the seabed, and only you can see them.
   - **Count:** `2 + depth/34 + log2(Luck)`, up to 16.
   - **Rarity:** deeper eggs can be rarer. Near the shore only Common and Uncommon can appear, and the Secret tier only
     shows up near the far side. Luck and depth both shift the odds toward rare eggs.
   - **Variants:** Gold (×2.5) and Rainbow (×6) chances scale with √Luck.
   - Walk over an egg to pick it up. You can carry 1 egg (2 with the Double Carry pass), and it floats above your head
     where everyone can see it.
5. **Run.** When the open time ends, the far wall rolls back toward the shore at 8 studs/s, half your walking speed. If it
   reaches you, you're swept back to the beach and lose what you carried. While the corridor is open you can come back
   for more eggs.
6. **Bank it.** Reach dry land and the egg goes into a free slot in your pen to incubate. If the pen is full it goes to
   storage, and if storage is full it's sold.
7. **Hatch.** When the timer reads *Ready!*, use the egg's prompt (or *Hatch All Ready* in the Eggs menu) to play the
   hatch cutscene. The animal joins your pen, wanders around and earns $/s.
8. **Grow.**
   - **Strength:** train on the pink pad in your pen. It lifts automatically, and clicking lifts faster.
   - **Heavier weights:** buy them on the yellow pad.
   - **Luck:** buy it in the **Buy** menu.
   - **Base size:** upgrade it at the sign by the gate.

If you walk into the ocean without parting it, the sea pushes you back. Inside your corridor the side walls are solid
for you, so you can't slip out sideways by accident. The far wall is the danger.

## Feedback while you play

- **Guide:** until a new player has banked an egg, hatched one and trained once, a line of text says what to do next
  and a trail of green arrows on the ground leads there (routing through the pen gate). During a run it points at the
  nearest egg, then turns red and points home once you're carrying.
- **Egg beams:** every egg in the corridor has a light beam in its rarity color, so rare eggs are visible from the shore.
- **Countdown:** the last three seconds of open time tick. When the sea starts closing, the HUD shows how many studs the
  wave is behind you and the screen edge pulses red, stronger as it gets closer.
- **Egg odds:** the Buy menu shows the chance of each rarity at the deepest point you can currently reach, so the
  effect of Strength and Luck is visible before spending.
- **Touch:** phones and tablets get a large hold button for charging, so it doesn't fight the camera.

## Visibility model

| | Splitter | Everyone else |
|---|---|---|
| Ocean water | parted corridor, walls of water | closed sea |
| Eggs in the corridor | visible, with name and rarity labels | not visible |
| The splitter | walks down the sandy ramp on the seabed | walks into the water |
| Carried egg | above their head | above their head |
| Sweep-back splash | visible | visible |

This works because **the water is not on the server at all**. `client/Ocean.luau` builds the sea locally out of a few
large Parts. When your own split is active it resizes them into left, right and far sections, plus walls and foam caps,
every frame (the side walls are rows of segments whose tops roll like waves). The seabed, ramps and coral are real
server Parts, so the splitter's character stands on solid ground that
everyone shares.

The server is authoritative for everything that matters:

- It decides the corridor (center, width, depth, open time, close speed, start time on `workspace:GetServerTimeNow()`)
  and rolls the eggs.
- `Formulas.currentLength` gives server and client the same open depth at any moment, so the walls you see are the
  walls the server checks against.
- At 10 Hz it checks every character in the ocean. Anyone outside their corridor, or past the closing wall (with 1.5
  studs of grace), is swept back.
- It accepts a grab only if the egg exists, hasn't been taken, is still inside the open corridor, and the player is
  within reach.

## Progression

| Egg | Rarity | Hatch | Animals (income $/s) |
|---|---|---|---|
| Shell | Common | 15s | Crab 4, Seagull 6, Turtle 10 |
| Coral | Uncommon | 40s | Pufferfish 18, Seal 26, Flamingo 38 |
| Kelp | Rare | 1:30 | Frog 70, Otter 100, Pelican 145 |
| Pearl | Epic | 3:00 | Penguin 280, Octopus 400, Dolphin 560 |
| Treasure | Legendary | 6:00 | Parrot 1.2K, Shark 1.7K, Walrus 2.4K |
| Abyss | Mythic | 12:00 | Anglerfish 5.5K, Kraken 7.8K, Narwhal 11K |
| Leviathan | Secret | 20:00 | Sea Dragon 28K, Ghost Whale 42K, Golden Kraken 65K |

Inside an egg the first animal is the most common (60/30/10), and Luck nudges the odds toward the rarer two.

Income keeps flowing while you're away: 50% of your $/s for up to 4 hours. Eggs keep incubating offline too, because
their timers use `os.time()`.

## Systems

- **Pens:** 8 per server, 4 on each side, assigned on join. You start with 4 slots, and each upgrade adds 2 (up to 20).
  Animals and eggs in slots are rendered by the server so everyone can see your base.
- **Pets menu:** *Place Best* fills the base with your highest earners from the base and storage. Incubating eggs keep
  their slots.
- **Leaderboard:** Cash, Strength and Eggs show in the Roblox player list.
- **Index:** a book of all 21 animals. Undiscovered ones are dark silhouettes, and each new discovery pays a one-time
  reward of 120 seconds of that animal's income.
- **Playtime gifts:** 12 rewards unlock at 1 to 60 minutes of play in a session, and the progress resets when you leave.
  "Skip All" is a developer product.
- **Daily streak:** a 7-day cycle based on UTC days. Missing a day resets the streak.
- **Robux:** passes are x2 Strength, x2 Luck, x2 Cash, Double Carry and Fast Hatch. Products are Starter Pack, two
  cash packs (scaled to your income), Luck Potion (x2 for 15 minutes), Instant Hatch and Skip Playtime. Receipts are
  checked against the save so a purchase is never granted twice.

## Art direction

Everything is built from blocks in code. Roblox no longer draws the old stud texture, so the toy-box look comes from
checkered tiles on the ground, seabed and pen floors.

- **Models:** pixel eggs stacked layer by layer on twig nests; blocky animals from a few templates (crab, bird, fish,
  quadruped, seal, octopus, turtle, frog, serpent); voxel palms, umbrellas, barbells and a lighthouse. Gold and Rainbow
  variants recolor the model. Animals hop as they move around the pen.
- **Ocean:** drifting foam crests on the closed sea; rolling wave-topped walls, a breaking curl on the closing wall and
  wet sand along the floor of a parted corridor.
- **UI:** the chunky toy-box style of the reference, with gradient buttons, thick black outlines, Fredoka One, a
  green-header window for gifts, and a blue/brown/orange Buy/Base/Sell bar. Labels over eggs and animals are sized in
  studs, so they shrink with distance.
