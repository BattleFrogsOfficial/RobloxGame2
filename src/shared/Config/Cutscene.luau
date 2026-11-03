--!strict
-- THE THROW CUTSCENE: every timing and tunable in ONE table (docs/DESIGN.md §20). Times are seconds,
-- distances studs, angles degrees, unless a comment says otherwise. Change numbers here, not in code.
-- Read by src/shared/Cutscene/* (pure maths, Lune-tested) and src/client/Cutscene/* (camera, rig, FX, UI).
-- The cutscene only DISPLAYS the server's ThrowResult; nothing in this file can change an outcome.
local Cutscene = {}

----------------------------------------------------------------------------------------------------
-- Per-rarity beat lengths. One row per beat, one column per rarity. The timeline is, in order:
--   WindUp.ReleaseAt -> Flight (by distance) -> Settle -> DogArrive -> Counter -> CounterHold -> Outcome
--   -> end card (ui:ShowReveal; waits for the player) -> Return
-- Total (release -> end card) is checked against Budget by tools/tests/cutscene.luau.
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
	-- caught: pick up + turn + hop toward the hub; missed: sniff + look at camera + bolt (same length)
	Outcome = { Common = 0.5, Uncommon = 0.65, Rare = 0.8, Epic = 1.4, Legendary = 2.0, Mythic = 2.5 },
}

-- Target total per rarity (release -> end card) at Budget.ReferenceFlight. The test asserts every rarity's
-- beats sum to its budget within Tolerance. A longer throw adds (flight - ReferenceFlight) on top.
Cutscene.Budget = {
	Common = 5.5, -- "about 5 s": 0.95 release + 1.5 flight + 1.5 counter alone are already 3.95 s
	Uncommon = 6.5, -- s
	Rare = 7.5, -- s
	Epic = 9.0, -- s
	Legendary = 10.5, -- s
	Mythic = 12.0, -- s
	Tolerance = 0.05, -- s, allowed difference between the summed beats and the budget
	ReferenceFlight = 1.5, -- s, flight length the budgets assume (= Flight.Min, a short throw)
}

----------------------------------------------------------------------------------------------------
-- Beat 1: WIND-UP (starts when the player releases the meter; the rarity is not known yet)
----------------------------------------------------------------------------------------------------
Cutscene.AnimationIds = {
	WindUp = 0, -- rbxassetid of an uploaded wind-up Animation; 0 (or Throw = 0) = procedural Motor6D throw
	Throw = 0, -- rbxassetid of the throw Animation, started at WindUp.ReleaseAt - Throw.Lead
}

Cutscene.WindUp = {
	Duration = 1.2, -- whole wind-up + throw + follow-through (the follow-through overlaps the flight)
	ReleaseAt = 0.95, -- the release frame: the ball leaves the hand and the flight starts
	ThrowLead = 0.15, -- uploaded Throw animation starts this long before ReleaseAt
	Recover = 0.35, -- after Duration, the procedural pose eases back to the rest pose over this
	SweepTime = 0.9, -- camera half circle from the default view to the front shot
	SweepDirection = 1, -- 1 = round the player's right (throwing-arm) side, -1 = round the left side
	MaxSweepDegrees = 225, -- if the preferred side is longer than this, sweep the other way round
	FrontDistance = 7, -- front shot: studs in front of the player
	FrontSide = 1.5, -- front shot: studs toward the player's left so the ball does not fly into the lens
	FrontHeight = 0.6, -- front shot: camera height above the HumanoidRootPart (chest is ~1; lower = bigger)
	LookHeight = 1.9, -- front shot: looks at this height above the HumanoidRootPart (the face)
	Fov = 60, -- field of view during the wind-up
	BallGrip = 0.9, -- R6 only: ball sits this far down the Right Arm (R15 uses the RightHand centre)
}

-- Procedural throw (used when AnimationIds are 0). Keyframes: At = fraction of WindUp.Duration, angles in
-- degrees about the parent part's axes (X = pitch: + swings a limb forward/up, Y = yaw: + turns left,
-- Z = roll). The last key must equal the rest pose (0 or a multiple of 360) so every C0 restores cleanly.
-- Joints: Waist (R15 Waist / R6 RootJoint), RightShoulder, RightElbow (R15 only), LeftShoulder,
-- LeftHip, LeftKnee (R15 only), RightHip, RightKnee (R15 only).
Cutscene.Pose = {
	{ At = 0.00, Waist = { 0, 0, 0 }, RightShoulder = { 0, 0, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 0, 0, 0 },
		LeftHip = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 }, RightHip = { 0, 0, 0 }, RightKnee = { 0, 0, 0 } }, -- rest
	{ At = 0.20, Waist = { 0, -12, 0 }, RightShoulder = { -45, 0, -10 }, RightElbow = { 20, 0, 0 }, LeftShoulder = { 25, 0, 0 },
		LeftHip = { 15, 0, 0 }, LeftKnee = { -15, 0, 0 }, RightHip = { 0, 0, 0 }, RightKnee = { -5, 0, 0 } }, -- anticipation
	{ At = 0.55, Waist = { 10, -45, 0 }, RightShoulder = { -150, 0, -25 }, RightElbow = { 95, 0, 0 }, LeftShoulder = { 80, 0, 10 },
		LeftHip = { 70, 0, 0 }, LeftKnee = { -75, 0, 0 }, RightHip = { -5, 0, 0 }, RightKnee = { -12, 0, 0 } }, -- cocked, knee up
	{ At = 0.68, Waist = { 8, -32, 0 }, RightShoulder = { -170, 0, -25 }, RightElbow = { 105, 0, 0 }, LeftShoulder = { 60, 0, 10 },
		LeftHip = { 35, 0, 0 }, LeftKnee = { -30, 0, 0 }, RightHip = { -8, 0, 0 }, RightKnee = { -15, 0, 0 } }, -- step + start
	{ At = 0.79, Waist = { -15, 25, 0 }, RightShoulder = { -265, 0, -10 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -10, 0, 5 },
		LeftHip = { 10, 0, 0 }, LeftKnee = { -10, 0, 0 }, RightHip = { -15, 0, 0 }, RightKnee = { -20, 0, 0 } }, -- release
	{ At = 0.90, Waist = { -25, 40, 0 }, RightShoulder = { -320, 0, 25 }, RightElbow = { 15, 0, 0 }, LeftShoulder = { -25, 0, 0 },
		LeftHip = { 5, 0, 0 }, LeftKnee = { -5, 0, 0 }, RightHip = { -25, 0, 0 }, RightKnee = { -35, 0, 0 } }, -- follow-through
	{ At = 1.00, Waist = { -15, 30, 0 }, RightShoulder = { -330, 0, 15 }, RightElbow = { 10, 0, 0 }, LeftShoulder = { -15, 0, 0 },
		LeftHip = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 }, RightHip = { -15, 0, 0 }, RightKnee = { -20, 0, 0 } }, -- settle
	{ At = 1.29, Waist = { 0, 0, 0 }, RightShoulder = { -360, 0, 0 }, RightElbow = { 0, 0, 0 }, LeftShoulder = { 0, 0, 0 },
		LeftHip = { 0, 0, 0 }, LeftKnee = { 0, 0, 0 }, RightHip = { 0, 0, 0 }, RightKnee = { 0, 0, 0 } }, -- rest (= Duration + Recover)
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
	ShakeTime = 0.3, -- launch camera shake length
	ShakeStuds = 0.3, -- launch camera shake position amplitude
	ShakeDegrees = 0.8, -- launch camera shake rotation amplitude
	TrailLifetime = 0.45, -- ball trail length in seconds
	BallSize = 1.2, -- ball diameter
	WindMinVolume = 0.05, -- wind sound volume at rest
	WindMaxVolume = 0.7, -- wind sound volume at WindSpeedForMax
	WindMinPitch = 0.7, -- wind sound PlaybackSpeed at rest
	WindMaxPitch = 1.6, -- wind sound PlaybackSpeed at WindSpeedForMax
	WindSpeedForMax = 900, -- ball speed (studs/s, on-screen) that maps to full wind volume / pitch
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

-- Dust / splash / sparks on touchdown, per zone. Colors: particle colour range; Texture: particle texture;
-- Count: particles emitted; Speed: min/max particle speed; Size: start size; Lifetime: seconds;
-- Gravity: particle Acceleration Y; Sound: SoundIds key; Pitch: PlaybackSpeed; Sparks: extra Neon sparks.
local DUST = "rbxasset://textures/particles/smoke_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
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
-- Beat 6: OUTCOME (length per rarity in Beats.Outcome; shares below split it)
----------------------------------------------------------------------------------------------------
Cutscene.Outcome = {
	PickUpShare = 0.25, -- caught: dog lowers its head and picks up the ball
	TurnShare = 0.15, -- caught: dog turns toward the hub; the rest of Outcome = hop away, camera follows
	HopSpeed = 26, -- caught: studs/s hopping toward the hub
	FollowBack = 12, -- caught: follow camera studs behind the dog
	FollowUp = 6, -- caught: follow camera studs above the dog
	FollowLag = 0.55, -- caught: camera moves at this share of the dog's speed, so the dog pulls away
	SniffShare = 0.3, -- missed: dog sniffs the ball
	LookShare = 0.3, -- missed: dog looks at the camera; the rest of Outcome = bolt out of frame
	BoltSpeed = 45, -- missed: studs/s bolting off to the side
	StingVolume = 0.5, -- missed: sad sting volume
	FlourishLucky = "Saved by your Lucky Streak!", -- text under the counter on a Lucky Streak catch
	FlourishTreat = "Saved by a Treat Pocket!", -- text under the counter on a Treat Pocket catch
	FlourishTime = 0.3, -- the flourish line pops in this long into the outcome
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
	NoShake = true, -- no camera shakes (launch / impact)
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
}

return Cutscene
