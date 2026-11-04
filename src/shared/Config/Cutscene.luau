--!strict
-- THE THROW CUTSCENE: every timing and tunable in ONE table (docs/DESIGN.md §20). Times are seconds,
-- distances studs, angles degrees, unless a comment says otherwise. Change numbers here, not in code.
-- Read by src/shared/Cutscene/* (pure maths, Lune-tested) and src/client/Cutscene/* (camera, rig, FX, UI).
-- The cutscene only DISPLAYS the server's ThrowResult; nothing in this file can change an outcome.
local Cutscene = {}

----------------------------------------------------------------------------------------------------
-- Per-rarity beat lengths. One row per beat, one column per rarity. The timeline depends on the outcome:
--   CAUGHT: WindUp.ReleaseAt -> Flight (by distance) -> Settle -> DogArrive -> Grab -> Victory -> Counter
--           -> CounterHold -> HopAway -> end card (ui:ShowReveal; waits for the player) -> Return
--   MISSED: WindUp.ReleaseAt -> Flight -> Settle -> DogArrive -> Counter -> CounterHold -> Sniff -> Bolt
--           -> end card -> Return   (the counter shows the rarity BEFORE the loss: docs/DESIGN.md §8)
-- Total (release -> end card) is checked against Budget (caught) / Budget.Missed by tools/tests/cutscene.luau.
----------------------------------------------------------------------------------------------------
Cutscene.Beats = {
	-- after touchdown, before the dog starts hopping in (the ball keeps bouncing underneath)
	Settle = { Common = 0.2, Uncommon = 0.25, Rare = 0.3, Epic = 0.35, Legendary = 0.4, Mythic = 0.5 },
	-- the dog hops in from off camera and stops beside the ball (camera holds wide, then pushes in)
	DogArrive = { Common = 0.6, Uncommon = 0.8, Rare = 1.0, Epic = 1.2, Legendary = 1.4, Mythic = 1.5 },
	-- the "1 out of N" counter, from "1 out of 1" to the dog's odds
	Counter = { Common = 1.5, Uncommon = 2.0, Rare = 2.5, Epic = 3.0, Legendary = 3.5, Mythic = 4.0 },
	-- the counter stays on its final number with the dog's name / rarity / variant badge under it
	CounterHold = { Common = 0.25, Uncommon = 0.35, Rare = 0.45, Epic = 0.6, Legendary = 0.75, Mythic = 1.05 },
	-- (was Outcome = 0.5 / 0.65 / 0.8 / 1.4 / 2.0 / 2.5: one shared caught / missed beat after the counter)
	-- caught: the dog dips its head and grabs the ball (it snaps to the mouth at Outcome.PickUpAt)
	Grab = { Common = 0.5, Uncommon = 0.5, Rare = 0.5, Epic = 0.5, Legendary = 0.5, Mythic = 0.5 },
	-- caught: the victory beat BEFORE the counter: two bouncy jumps with the ball, fast wag, bark, confetti (Victory)
	Victory = { Common = 2.0, Uncommon = 2.0, Rare = 2.0, Epic = 2.1, Legendary = 2.2, Mythic = 2.4 },
	-- caught, after the counter: turn to the hub (Outcome.TurnTime) + hop away; >= TurnTime + HopAwayMinSeconds
	HopAway = { Common = 1.3, Uncommon = 1.4, Rare = 1.5, Epic = 1.7, Legendary = 1.9, Mythic = 2.1 },
	-- missed, after the counter: sniff, sniff, look at the camera, ears drop, tail still, whimper (Sniff)
	Sniff = { Common = 1.5, Uncommon = 1.5, Rare = 1.5, Epic = 1.5, Legendary = 1.5, Mythic = 1.5 },
	-- missed: the dog bolts off the side (it keeps running behind the end card: Outcome.HopAwayMinSeconds)
	Bolt = { Common = 0.6, Uncommon = 0.7, Rare = 0.8, Epic = 1.0, Legendary = 1.2, Mythic = 1.4 },
}

-- Target total per rarity (release -> end card) at Budget.ReferenceFlight. The test asserts every rarity's
-- beats sum to its budget within Tolerance. A longer throw adds (flight - ReferenceFlight) on top.
-- Budget[rarity] is the CAUGHT total (the longest timeline; Config/Timers.Cutscene builds the server timeout
-- from it); Budget.Missed[rarity] is the missed total (always shorter).
Cutscene.Budget = {
	-- The catch celebration (Grab + Victory before the counter, HopAway after) replaced the 0.5..2.5 s Outcome.
	-- Old values (one timeline for both outcomes): 5.75 / 6.75 / 7.75 / 9.25 / 10.75 / 12.25.
	Common = 9.05, -- s: 1.2 release + 1.5 flight + 0.2 settle + 0.6 dog + 0.5 grab + 2.0 victory + 1.5 + 0.25 + 1.3
	Uncommon = 10.0, -- s
	Rare = 10.95, -- s
	Epic = 12.15, -- s
	Legendary = 13.35, -- s
	Mythic = 14.75, -- s
	Missed = { Common = 7.35, Uncommon = 8.3, Rare = 9.25, Epic = 10.35, Legendary = 11.45, Mythic = 12.65 }, -- s
	Tolerance = 0.05, -- s, allowed difference between the summed beats and the budget
	ReferenceFlight = 1.5, -- s, flight length the budgets assume (= Flight.Min, a short throw)
}

----------------------------------------------------------------------------------------------------
-- Beat 1: WIND-UP (starts when the player releases the meter; the rarity is not known yet)
----------------------------------------------------------------------------------------------------
Cutscene.AnimationIds = {
	WindUp = 0, -- rbxassetid of an uploaded wind-up Animation; 0 (or Throw = 0) = the built-in throw (Cutscene/Rig:
	-- a KeyframeSequence built from Pose at runtime, else Motor6D C0 / AnimationConstraint.Transform keyframes)
	Throw = 0, -- rbxassetid of the throw Animation, started at WindUp.ReleaseAt - Throw.Lead
	-- Dog animations: 0 = procedural (Dog/DogAnimator writes the rig's Motor6Ds: "victory" jumps + 6 Hz wag +
	-- lagging ears, "sniff", "sadlook"). The dog rig has no Animator, so ids are reserved for a future upload.
	DogJump = 0, -- victory jumps
	DogWag = 0, -- tail wag
	DogSniff = 0, -- missed sniff
}

Cutscene.WindUp = {
	Duration = 1.5, -- whole wind-up + throw + follow-through (the follow-through overlaps the flight). Was 1.2:
	-- the 1.2 s throw was over before the camera sweep settled, so the wind-up never read on screen.
	ReleaseAt = 1.2, -- the release frame: the ball leaves the hand and the flight starts (was 0.95; = Pose[5].At x Duration)
	ThrowLead = 0.15, -- uploaded Throw animation starts this long before ReleaseAt
	Recover = 0.35, -- after Duration, the procedural pose eases back to the rest pose over this
	SweepTime = 0.75, -- camera half circle from the default view to the front shot (was 0.9: it now settles before
	-- the cocked pose at 0.55 x Duration = 0.83 s and holds still on the body for the throw itself)
	SweepDirection = 1, -- 1 = round the player's right (throwing-arm) side, -1 = round the left side
	MaxSweepDegrees = 225, -- if the preferred side is longer than this, sweep the other way round
	-- Front shot: framed on the WHOLE body (raised throwing hand ~+4.5 to the feet ~-3 studs around the
	-- HumanoidRootPart), so the arm wind-back and the raised knee are in frame, not just the face.
	FrontDistance = 10, -- front shot: studs in front of the player (was 7: head and shoulders only)
	FrontSide = 2, -- front shot: studs toward the player's left so the ball does not fly into the lens (was 1.5)
	FrontHeight = 0.4, -- front shot: camera height above the HumanoidRootPart (a low angle; was 0.6)
	LookHeight = 0.9, -- front shot: looks at this height above the HumanoidRootPart (mid body; was 1.9 = the face)
	Fov = 60, -- field of view during the wind-up (vertical: 11.5 studs of body room at FrontDistance)
	BallGrip = 0.9, -- R6 only: ball sits this far down the Right Arm (R15 uses the RightHand centre)
}

-- The built-in throw (used when AnimationIds are 0). Keyframes: At = fraction of WindUp.Duration, angles in
-- degrees about the parent part's axes (X = pitch: + swings a limb forward/up, Y = yaw: + turns left,
-- Z = roll). The last key must equal the rest pose (0 or a multiple of 360) so every joint restores cleanly.
-- Consecutive keys of one joint differ by < 180 degrees per axis (the KeyframeSequence path slerps the shortest
-- way between keys). Joints: Waist (R15 Waist / R6 RootJoint), RightShoulder, RightElbow (R15 only),
-- LeftShoulder, LeftHip, LeftKnee (R15 only), RightHip, RightKnee (R15 only).
-- Widened for readability: torso coil -45 -> -60, throwing arm -150 -> -165 (cocked) and -170 -> -185 (step),
-- knee lift 70 -> 85, a bigger follow-through. Key 5 (release) sits at ReleaseAt / Duration = 0.80.
Cutscene.Pose = {
	{ At = 0.00, Waist = { 0, 0, 0 }, RightShoulder = { 0, 0, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 0, 0, 0 },
		LeftHip = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 }, RightHip = { 0, 0, 0 }, RightKnee = { 0, 0, 0 } }, -- rest
	{ At = 0.20, Waist = { 0, -20, 0 }, RightShoulder = { -60, 0, -15 }, RightElbow = { 25, 0, 0 }, LeftShoulder = { 35, 0, 0 },
		LeftHip = { 20, 0, 0 }, LeftKnee = { -20, 0, 0 }, RightHip = { 0, 0, 0 }, RightKnee = { -8, 0, 0 } }, -- anticipation
	{ At = 0.55, Waist = { 12, -60, 0 }, RightShoulder = { -165, 0, -35 }, RightElbow = { 110, 0, 0 }, LeftShoulder = { 90, 0, 15 },
		LeftHip = { 85, 0, 0 }, LeftKnee = { -90, 0, 0 }, RightHip = { -5, 0, 0 }, RightKnee = { -15, 0, 0 } }, -- cocked, knee up
	{ At = 0.68, Waist = { 10, -45, 0 }, RightShoulder = { -185, 0, -35 }, RightElbow = { 120, 0, 0 }, LeftShoulder = { 70, 0, 15 },
		LeftHip = { 40, 0, 0 }, LeftKnee = { -35, 0, 0 }, RightHip = { -10, 0, 0 }, RightKnee = { -18, 0, 0 } }, -- step + start
	{ At = 0.80, Waist = { -20, 35, 0 }, RightShoulder = { -270, 0, -10 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -20, 0, 5 },
		LeftHip = { 15, 0, 0 }, LeftKnee = { -10, 0, 0 }, RightHip = { -20, 0, 0 }, RightKnee = { -25, 0, 0 } }, -- release
	{ At = 0.90, Waist = { -30, 50, 0 }, RightShoulder = { -325, 0, 25 }, RightElbow = { 15, 0, 0 }, LeftShoulder = { -30, 0, 0 },
		LeftHip = { 5, 0, 0 }, LeftKnee = { -5, 0, 0 }, RightHip = { -30, 0, 0 }, RightKnee = { -40, 0, 0 } }, -- follow-through
	{ At = 1.00, Waist = { -15, 30, 0 }, RightShoulder = { -335, 0, 15 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -15, 0, 0 },
		LeftHip = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 }, RightHip = { -15, 0, 0 }, RightKnee = { -20, 0, 0 } }, -- settle
	{ At = 1.2333, Waist = { 0, 0, 0 }, RightShoulder = { -360, 0, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 0, 0, 0 },
		LeftHip = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 }, RightHip = { 0, 0, 0 }, RightKnee = { 0, 0, 0 } }, -- rest (= (Duration + Recover) / Duration)
}


----------------------------------------------------------------------------------------------------
-- Beat 2: LAUNCH AND BALL POV
----------------------------------------------------------------------------------------------------
Cutscene.Flight = {
	ServerMin = 1.0, -- result.FlightTime of the shortest throw (Util/BallFlight.ForThrow off the 40-stud plateau: ~0.99 s)
	ServerMax = 2.3, -- result.FlightTime of the longest throw (3200 studs: ~2.28 s)
	Min = 1.5, -- on-screen flight for the shortest throw; result.FlightTime is remapped into Min..Max
	Max = 4.0, -- on-screen flight for the longest throw (the arc is time-scaled, it still lands on LandPos)
	HandBlend = 0.3, -- the ball starts in the hand and blends into the server arc over this long
	RetargetBlend = 0.4, -- a ThrowResult arriving mid-flight blends the estimated arc into the real one
	WhipTime = 0.2, -- camera whip from the front shot to the ball POV at the release frame
	PovBack = 7, -- POV camera: studs behind the ball
	PovUp = 3.5, -- POV camera: studs above the ball (keeps zone arches / fences in the shot)
	PovPitchFollow = 0.45, -- POV camera: share of the ball's climb / dive angle the camera follows
	PovPitchMin = -50, -- POV camera: lowest look pitch (looking down)
	PovPitchMax = 12, -- POV camera: highest look pitch (looking up)
	PovFov = 78, -- field of view while riding the ball (wider = faster feel)
	-- (the launch shake moved to Cutscene.Impact: was 0.3 s / 0.3 studs / 0.8 degrees)
	TrailLifetime = 0.45, -- ball trail length in seconds
	BallSize = 1.2, -- ball diameter
	WindMinVolume = 0.05, -- wind sound volume at rest
	WindMaxVolume = 0.7, -- wind sound volume at WindSpeedForMax
	WindMinPitch = 0.7, -- wind sound PlaybackSpeed at rest
	WindMaxPitch = 1.6, -- wind sound PlaybackSpeed at WindSpeedForMax
	WindSpeedForMax = 900, -- ball speed (studs/s, on-screen) that maps to full wind volume / pitch
	-- constant ball-POV shake that scales with the ball's speed (on top of the launch Impact shake)
	PovShakeStuds = 0.06, -- position amplitude at PovShakeSpeedForMax
	PovShakeDegrees = 0.25, -- roll amplitude at PovShakeSpeedForMax
	PovShakeHz = 9, -- base wobble frequency
	PovShakeSpeedForMax = 900, -- on-screen ball speed (studs/s) that gives the full POV shake
	-- faint motion blur while riding the ball (BlurEffect in Lighting, client only, always removed)
	BlurSize = 4, -- BlurEffect.Size at BlurSpeedForMax
	BlurSpeedForMax = 600, -- on-screen ball speed (studs/s) that gives the full blur; it clears as the ball slows
}

-- The release frame: impact (Beat 2 starts with it). Quality = result.Quality (0.35 flub .. 1 Perfect), or the
-- client's release meter position via Util/Meter when no ThrowResult has arrived yet.
Cutscene.Impact = {
	ShakeTime = 0.4, -- s, the release shake starts hard and decays to zero over this
	ShakeStuds = 0.55, -- position amplitude at the start (Perfect)
	ShakeDegrees = 1.6, -- roll amplitude at the start (Perfect)
	ShakeDecay = 3, -- amplitude x (1 - t / ShakeTime) ^ ShakeDecay (higher = dies off faster)
	ShakeHz = 11, -- wobble frequency
	QualityMin = 0.35, -- quality that gets ShakeMinScale (Game.Meter.FlubQuality)
	ShakeMinScale = 0.45, -- shake multiplier at QualityMin; 1 at quality 1 (Perfect feels heavier)
	FlashTransparency = 0.2, -- one-frame white flash
	FlashFrames = 1, -- frames the flash stays up
	FovFrom = 70, -- FOV punch: 70 -> 82 -> 70 over FovTime, applied as + (FovPeak - FovFrom) on top of the whip
	FovPeak = 82, -- FOV at the top of the punch
	FovTime = 0.3, -- s
	FovPeakAt = 0.3, -- share of FovTime at the peak (fast out, slower back)
	WhooshVolume = 0.7, -- release whoosh
	SpeedLines = 26, -- speed-line particles burst from the hand along the throw
	SpeedLineSpeed = { 45, 80 }, -- studs/s
	SpeedLineLifetime = 0.22, -- s
	SpeedLineSize = 0.18, -- studs (stretched along the velocity)
	SpeedLineSpread = 18, -- degrees around the throw direction
}

----------------------------------------------------------------------------------------------------
-- Beat 3: LANDING (the last LandingShare of the flight + the bounces)
----------------------------------------------------------------------------------------------------
Cutscene.Landing = {
	Share = 0.25, -- last share of the flight in which the camera eases out to the wide shot
	WideBack = 30, -- wide shot: studs back from the landing spot (toward the thrower)
	WideUp = 24, -- wide shot: studs above the landing spot
	WideSide = 6, -- wide shot: studs to the side (a slight three-quarter view)
	WideFov = 60, -- field of view of the wide shot
	Bounces = 3, -- decaying bounces after touchdown (2-3 reads as "bouncing to a stop")
	BounceHeight = 2.6, -- first bounce height
	BounceTime = 0.34, -- first bounce air time; each later bounce is BounceTime x sqrt(BounceDecay)^n
	BounceDecay = 0.4, -- height multiplier per bounce
	BounceRoll = 2.5, -- forward roll during the first bounce; later bounces roll x BounceDecay
	ImpactShakeStuds = 0.15, -- small camera bump on touchdown
	GroundProbe = 30, -- raycast this far above / below LandPos to find the real ground top
}

local DUST = "rbxasset://textures/particles/smoke_main.dds" -- soft puff texture (grass / sand / snow / grit)
local SPARK = "rbxasset://textures/particles/sparkles_main.dds" -- glitter texture (metal / crystal)
-- Dust / splash / sparks on touchdown, per zone. Colors: particle colour range; Texture: particle texture;
-- Count: particles emitted; Speed: min/max particle speed; Size: start size; Lifetime: seconds;
-- Gravity: particle Acceleration Y; Sound: SoundIds key; Pitch: PlaybackSpeed; Sparks: extra Neon sparks.
Cutscene.ImpactFX = {
	Backyard = { Colors = { Color3.fromRGB(110, 175, 70), Color3.fromRGB(80, 140, 50) }, Texture = DUST, Count = 22,
		Speed = { 6, 14 }, Size = 0.5, Lifetime = 0.7, Gravity = -30, Sound = "ImpactGrass", Pitch = 1.0, Sparks = false }, -- grass bits
	Park = { Colors = { Color3.fromRGB(95, 165, 80), Color3.fromRGB(140, 110, 70) }, Texture = DUST, Count = 22,
		Speed = { 6, 14 }, Size = 0.5, Lifetime = 0.7, Gravity = -30, Sound = "ImpactGrass", Pitch = 0.95, Sparks = false }, -- grass + dirt
	Beach = { Colors = { Color3.fromRGB(240, 220, 165), Color3.fromRGB(215, 190, 130) }, Texture = DUST, Count = 34,
		Speed = { 5, 12 }, Size = 0.8, Lifetime = 0.9, Gravity = -20, Sound = "ImpactSand", Pitch = 1.0, Sparks = false }, -- sand puff
	Farm = { Colors = { Color3.fromRGB(150, 115, 70), Color3.fromRGB(215, 190, 90) }, Texture = DUST, Count = 28,
		Speed = { 5, 12 }, Size = 0.7, Lifetime = 0.8, Gravity = -25, Sound = "ImpactSand", Pitch = 0.85, Sparks = false }, -- dirt + hay
	Forest = { Colors = { Color3.fromRGB(60, 110, 50), Color3.fromRGB(120, 80, 40) }, Texture = DUST, Count = 24,
		Speed = { 5, 12 }, Size = 0.6, Lifetime = 1.0, Gravity = -12, Sound = "ImpactGrass", Pitch = 0.8, Sparks = false }, -- leaf litter
	SnowyPeaks = { Colors = { Color3.fromRGB(250, 252, 255), Color3.fromRGB(205, 225, 245) }, Texture = DUST, Count = 40,
		Speed = { 6, 14 }, Size = 0.9, Lifetime = 1.1, Gravity = -10, Sound = "ImpactSnow", Pitch = 1.1, Sparks = false }, -- snow burst
	CityRooftops = { Colors = { Color3.fromRGB(160, 160, 165), Color3.fromRGB(110, 110, 120) }, Texture = DUST, Count = 20,
		Speed = { 6, 12 }, Size = 0.6, Lifetime = 0.6, Gravity = -30, Sound = "ImpactConcrete", Pitch = 1.0, Sparks = false }, -- grit
	SpaceStation = { Colors = { Color3.fromRGB(255, 220, 120), Color3.fromRGB(120, 220, 255) }, Texture = SPARK, Count = 26,
		Speed = { 10, 22 }, Size = 0.35, Lifetime = 0.45, Gravity = -40, Sound = "ImpactMetal", Pitch = 1.3, Sparks = true }, -- clank + sparks
	MythicMeadow = { Colors = { Color3.fromRGB(255, 190, 240), Color3.fromRGB(170, 220, 255) }, Texture = SPARK, Count = 30,
		Speed = { 4, 10 }, Size = 0.6, Lifetime = 1.2, Gravity = 4, Sound = "ImpactCrystal", Pitch = 1.2, Sparks = true }, -- crystal glitter
}

----------------------------------------------------------------------------------------------------
-- Beat 4: THE DOG ARRIVES (length per rarity in Beats.DogArrive)
----------------------------------------------------------------------------------------------------
Cutscene.Dog = {
	StartMin = 18, -- the dog starts at least this far from the ball (studs), further if still in frame
	StartMax = 60, -- ... and never further than this (or outside the field edge)
	EdgeMargin = 8, -- the dog's path stays this far inside the field's X edges
	StopOffset = 3, -- the dog stops this far beside the ball
	HopRate = 2.4, -- hops per second while arriving
	HoldShare = 0.35, -- share of DogArrive the camera holds the wide shot before pushing in
	PushIn = 0.45, -- the camera ends this share of the way from the wide shot toward the dog
	PushFov = 50, -- field of view at the end of the push-in
	CounterDrift = 0.08, -- extra slow push toward the dog during the counter (share of the remaining distance)
}

----------------------------------------------------------------------------------------------------
-- Beat 5: THE ODDS COUNTER (length per rarity in Beats.Counter)
----------------------------------------------------------------------------------------------------
Cutscene.Counter = {
	LinearUpTo = 30, -- every number 1..LinearUpTo is shown; above that the count skips in growing steps
	MaxTicks = 90, -- most numbers shown in one count (keeps a 1-in-6,667 inside its budget)
	EasePower = 1.6, -- tick timing ease-in: > 1 = ticks get closer together as the count runs
	IncludeCatch = false, -- false: target = 1 / (tier odds / dogs in tier) (appear); true: x catch chance too
	TextSize = 60, -- canvas px of "1 out of N"
	PopScale = 1.25, -- scale punch when the colour climbs a rarity
	PopTime = 0.16, -- length of the scale punch
	FlashTransparency = 0.55, -- one-frame screen flash in the new rarity colour (1 = off)
	ClickMinPitch = 0.8, -- click PlaybackSpeed on the first tick
	ClickMaxPitch = 2.2, -- click PlaybackSpeed on the last tick
	ClickMinGap = 0.03, -- at most one click per this many seconds (fast counts stay listenable)
	ClickVolume = 0.35, -- click volume
	StopPopScale = 1.35, -- scale punch when the count lands on the target
	NameFadeTime = 0.2, -- name / rarity / badge fade-in under the stopped counter
}

----------------------------------------------------------------------------------------------------
-- Beat 4b (CAUGHT, before the counter): GRAB + VICTORY (lengths in Beats.Grab / Beats.Victory)
----------------------------------------------------------------------------------------------------
Cutscene.Victory = {
	Jumps = 2, -- bouncy jumps in place with the ball in the mouth
	JumpTime = 0.7, -- s per jump (crouch 20% + air 65% + landing squash 15%)
	JumpGap = 0.15, -- s standing between the jumps
	Height = 1.6, -- jump height, studs at dog scale 1
	WagHz = 6, -- tail wag frequency the whole beat (a sine on the TailJoint Motor6Ds)
	WagDegrees = 40, -- tail wag amplitude
	EarLag = 0.1, -- s the ears lag the body (they flap on the jumps)
	EarFlapDegrees = 45, -- ear swing at full body speed
	BarkAt = 0.1, -- s into the beat: happy bark
	BarkVolume = 0.6, -- bark volume
	BarkPitch = 1.5, -- bark PlaybackSpeed (placeholder sound, pitched up)
	-- confetti / sparkles in the rarity colour, one burst per jump take-off (more for higher rarity)
	Confetti = { Common = 14, Uncommon = 20, Rare = 28, Epic = 38, Legendary = 50, Mythic = 66 },
	VariantConfetti = 0.6, -- the variant's colours burst on top, x this many of the rarity count
	ConfettiSpeed = { 8, 16 }, -- studs/s
	ConfettiLifetime = 1.4, -- s
	ConfettiSize = 0.35, -- studs
	PushIn = 0.3, -- the camera pushes this share of the remaining way toward the dog over the beat
	PushFov = 44, -- field of view at the end of the beat (from Dog.PushFov)
}

----------------------------------------------------------------------------------------------------
-- Beat 6: OUTCOME (caught: Beats.HopAway after the counter; missed: Beats.Sniff + Beats.Bolt after the counter)
----------------------------------------------------------------------------------------------------
Cutscene.Outcome = {
	PickUpAt = 0.5, -- caught: share of Beats.Grab at which the ball snaps into the dog's mouth
	TurnTime = 0.25, -- caught: s of Beats.HopAway turning toward the hub; the rest = hop away, camera follows
	HopSpeed = 26, -- caught: studs/s hopping toward the hub
	FollowBack = 12, -- caught: follow camera studs behind the dog
	FollowUp = 6, -- caught: follow camera studs above the dog
	FollowLag = 0.55, -- caught: camera moves at this share of the dog's speed, so the dog pulls away
	-- The leaving dog (hop away / bolt) keeps moving behind the end card and is removed by a TIME + DISTANCE
	-- check, never a frustum check: not before HopAwayMinSeconds after it starts leaving, then once it is
	-- RemoveDistance from where it started, or at HopAwayMaxSeconds at the latest.
	HopAwayMinSeconds = 1.0, -- s
	RemoveDistance = 40, -- studs
	HopAwayMaxSeconds = 4.0, -- s
	BoltSpeed = 45, -- missed: studs/s bolting off to the side
	StingVolume = 0.5, -- missed: sad sting volume
	FlourishLucky = "Saved by your Lucky Streak!", -- text under the counter on a Lucky Streak catch
	FlourishTreat = "Saved by a Treat Pocket!", -- text under the counter on a Treat Pocket catch
	FlourishTime = 0.3, -- the flourish line pops in this long into the outcome
}

-- Missed: the sniff beat (Beats.Sniff), after the counter so the rarity is seen before the loss.
Cutscene.Sniff = {
	Sniffs = 2, -- nose-down sniffs
	SniffShare = 0.5, -- share of Beats.Sniff for the sniffs; the rest = look at the camera, ears drop, tail still
	EarDownDegrees = 55, -- ears drop back this far
	WhimperAt = 0.15, -- s into the look: whimper (not a bark)
	WhimperVolume = 0.5, -- whimper volume
	WhimperPitch = 1.6, -- whimper PlaybackSpeed (placeholder sound, pitched up)
}

----------------------------------------------------------------------------------------------------
-- END CARD (ui:ShowReveal, starts at the timeline Total): waits for OK / Keep / Whistle, but always closes
-- itself after AutoClose. Read by UI/Screens/Reveal.luau and by Config/Timers (the server timeout).
----------------------------------------------------------------------------------------------------
Cutscene.EndCard = {
	-- s, the thrower's Reveal card closes itself after this (the player can close it sooner)
	AutoClose = { Common = 5, Uncommon = 6, Rare = 7, Epic = 8, Legendary = 9, Mythic = 10 },
	SpectatorAutoClose = 3, -- s, the compact card other players see for a Rare+ throw
	-- Prize-screen entry (Reveal.luau). Reduced motion: no pop, no ray spin, no count-up (short fades only).
	PopFrom = 0.6, -- card scale at the start of the entry pop ...
	PopTime = 0.38, -- ... s to reach 1 (Back out, overshoots a little)
	FlashFrom = 0.3, -- transparency the rarity-coloured full-screen flash starts at (0 = solid) ...
	FlashTime = 0.5, -- ... s to fade out
	ScrimTransparency = 0.3, -- the darkened background behind the card (1 = none) ...
	ScrimTime = 0.25, -- ... s to fade in
	RaysFrom = "Epic", -- light rays spin behind the card for this rarity and up
	RaysPeriod = 16, -- s per full turn of the light rays
	RaysCount = 8, -- beams (each one crosses the card centre, so 2x this many rays)
	CountUpDelay = 0.3, -- s after the card appears before the $/s number starts counting ...
	CountUpTime = 1.0, -- ... s to count from 0 to the dog's $/s
	-- Live dog viewport (Components/DogViewport.luau)
	StageShare = 0.6, -- the viewport is this share of the card width
	TurnPeriod = 6, -- s per full turn of the dog on its pedestal (caught)
	StartYaw = -35, -- degrees, the caught dog's first-frame yaw (3/4 front view; the reduced-motion pose)
	MissedYaw = 120, -- degrees, a missed dog stands turned away (side-rear) and looks back over its shoulder (no turning)
	HopEvery = 3, -- s between little hops (DogAnimator.Idle; caught only)
	HopHeight = 0.5, -- studs at dog scale 1
	WagHz = 6, -- tail wags per second (DogAnimator.Idle)
	CameraFov = 30, -- degrees, vertical FOV of the viewport camera (narrow = little perspective distortion)
	CameraPitch = 7, -- degrees the camera sits below the subject's centre, looking up (slight low angle)
	FrameFill = 0.94, -- share of the viewport the turning dog fills (camera fitted to its turning bounding cylinder)
	PedestalMargin = 1.05, -- pedestal radius = the dog's turning radius x this
	MoteCount = 10, -- Mythic: floating particles (small Neon parts; ViewportFrames don't render ParticleEmitters)
	MoteRiseTime = 2.6, -- s for one mote to rise through the aura and loop
	GlowPulse = 1.6, -- s per pulse of the Legendary / Mythic pedestal glow
}

----------------------------------------------------------------------------------------------------
-- Beat 7: RETURN
----------------------------------------------------------------------------------------------------
Cutscene.Return = {
	Time = 0.5, -- camera tween back to the normal view after the end card closes
	BackDistance = 12, -- the tween aims at a point this far behind the player ...
	UpDistance = 4, -- ... and this far up, then hands the camera back to Roblox (Custom)
}

----------------------------------------------------------------------------------------------------
-- Rules
----------------------------------------------------------------------------------------------------
Cutscene.Skip = {
	FromBeat = "Counter", -- the Skip button appears when this beat starts
	Never = { Legendary = true, Mythic = true }, -- these rarities can never be skipped
}

-- Settings.HideCommonReveals: a Common plays wind-up + flight + landing, then goes straight to the end card.
Cutscene.ShortCommon = {
	AfterTouchdown = 0.6, -- s on the landing shot before the end card (the bounces finish)
}

-- ThrowResult never arrived (or arrived late).
Cutscene.Fallback = {
	HoldMax = 3, -- hold on the landing shot this long waiting for the result after the estimated flight
	ShowFor = 1.6, -- show the fallback text this long, then return and unlock
	Text = "The ball rolled away...", -- fallback text (no CutsceneFinished is sent for that throw)
	RollTime = 0.45, -- a result that arrives during the hold: the ball rolls from the guess to LandPos
	EstimateLaneX = 0.5, -- estimated landing X = this share of the thrower's X (the server's lateral rule)
}

-- Reduced motion (State.Settings.ReducedMotion): no sweeps / whips / push-ins / shakes, hard cuts instead.
Cutscene.ReducedMotion = {
	PovFov = 70, -- calmer FOV on the ball shot
	NoShake = true, -- no camera shakes (release impact / ball POV / touchdown)
	NoFovPunch = true, -- no release FOV punch
	NoBlur = true, -- no ball-POV motion blur
	FlashTransparency = 0.6, -- the release flash stays, but subtler (Impact.FlashTransparency otherwise)
	NoPop = true, -- the counter colour climbs without the scale punch (the colour still snaps)
}

-- Spectators: the thrower's avatar winds up and the ball flies (on every client); no camera work.
Cutscene.Spectator = {
	BallRest = 6, -- the spectator ball rests on the field this long before it is removed
	MaxDistance = 1200, -- skip the avatar animation when the thrower is further than this from our camera
}

-- Debug test place (Config/Game.CutsceneTestMode = true). Fake results never reach the server.
Cutscene.Test = {
	LoopGap = 1.0, -- seconds between looped random cutscenes
	LoopEndCard = 2.5, -- the end card auto-closes after this in loop mode
	VariantChance = 0.4, -- "random" fakes: chance a non-Common gets a variant
	CaughtChance = 0.6, -- "random" fakes: chance of a catch
}

-- Sound ids. Built-in placeholders (rbxasset://sounds/...) so it works before any upload; replace with
-- rbxassetid://<id> once real sounds are uploaded. Volume multiplies Settings.Sfx (off = silent).
Cutscene.SoundIds = {
	Whoosh = "rbxasset://sounds/swoosh.wav", -- release frame
	Wind = "rbxasset://sounds/action_falling.mp3", -- looped wind while the ball flies
	Click = "rbxasset://sounds/clickfast.wav", -- counter tick
	Punch = "rbxasset://sounds/electronicpingshort.wav", -- counter colour climbs a rarity
	Stop = "rbxasset://sounds/electronicpingshort.wav", -- counter lands on the target
	ImpactGrass = "rbxasset://sounds/action_jump_land.mp3", -- touchdown on grass / leaves
	ImpactSand = "rbxasset://sounds/action_jump_land.mp3", -- touchdown on sand / dirt
	ImpactSnow = "rbxasset://sounds/action_jump_land.mp3", -- touchdown on snow
	ImpactConcrete = "rbxasset://sounds/hit.wav", -- touchdown on a roof deck
	ImpactMetal = "rbxasset://sounds/hit.wav", -- touchdown on the Space Station deck (pitched up = clank)
	ImpactCrystal = "rbxasset://sounds/electronicpingshort.wav", -- touchdown in the Mythic Meadow
	Bounce = "rbxasset://sounds/action_jump_land.mp3", -- each later bounce (quieter)
	Sting = "rbxasset://sounds/uuhhh.mp3", -- missed: sad sting
	Happy = "rbxasset://sounds/electronicpingshort.wav", -- caught: little ding
	Bark = "rbxasset://sounds/action_jump.mp3", -- caught: happy bark on the victory beat (placeholder, pitched up)
	Whimper = "rbxasset://sounds/uuhhh.mp3", -- missed: whimper as the ears drop (placeholder, pitched up)
}

return Cutscene
