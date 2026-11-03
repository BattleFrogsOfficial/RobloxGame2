--!strict
-- The 14 body types of the ONE shared quadruped rig (see DogFactory). Every dog in the roster picks one
-- of these; the roster's Scale field then sets overall size (1.0 = a medium dog), so these proportions
-- describe SHAPE, not size. Units are studs at scale 1. Forward is -Z (the model's LookVector).
--
--   Torso      : Vector3 (width X, height Y, length Z)
--   LegLength  : hip -> ground
--   LegThick   : leg cross-section
--   Head       : Vector3 head block
--   Snout      : Vector3 snout block (Z = length forward of the head)
--   Ear        : "floppy" | "pointy" | "round" | "folded" ; EarSize = length of the ear
--   Tail       : "straight" | "curled" | "plume" | "stub" | "whip" | "pom" ; TailLength ; TailAngle (deg, 0 = up, 90 = straight back, 120 = drooping)
--   NeckRaise  : extra head height above the shoulders
--   Fluffy     : adds ruff/cheek fluff parts and a Fabric coat material
--   Poodle     : adds pom-pom puffs (ankles, tail tip, head top, chest)
export type BodyType = {
	Id: string,
	Torso: Vector3,
	LegLength: number,
	LegThick: number,
	Head: Vector3,
	Snout: Vector3,
	Ear: string,
	EarSize: number,
	Tail: string,
	TailLength: number,
	TailAngle: number,
	NeckRaise: number,
	Fluffy: boolean,
	Poodle: boolean,
}

local function body(id: string, t: { [string]: any }): BodyType
	return {
		Id = id,
		Torso = t.Torso,
		LegLength = t.LegLength,
		LegThick = t.LegThick,
		Head = t.Head,
		Snout = t.Snout,
		Ear = t.Ear,
		EarSize = t.EarSize,
		Tail = t.Tail,
		TailLength = t.TailLength,
		TailAngle = t.TailAngle,
		NeckRaise = t.NeckRaise or 0,
		Fluffy = t.Fluffy == true,
		Poodle = t.Poodle == true,
	}
end

local BodyTypes = {}

BodyTypes.Order = {
	"toy", "small_terrier", "long_low", "small_fluffy", "corgi_type", "medium_lean", "medium_stocky",
	"medium_fluffy", "large_lean", "large_athletic", "large_fluffy", "giant", "giant_fluffy", "poodle_type",
}

BodyTypes.ById = {
	-- tiny round body, big head and eyes, pointy ears, curled tail
	toy = body("toy", { Torso = Vector3.new(1.3, 1.2, 1.9), LegLength = 1.0, LegThick = 0.32,
		Head = Vector3.new(1.35, 1.25, 1.2), Snout = Vector3.new(0.55, 0.4, 0.35), Ear = "pointy", EarSize = 0.85,
		Tail = "curled", TailLength = 0.7, TailAngle = 20, NeckRaise = 0.25 }),
	-- boxy, beardy snout, folded ears, upright carrot tail
	small_terrier = body("small_terrier", { Torso = Vector3.new(1.35, 1.35, 2.3), LegLength = 1.15, LegThick = 0.38,
		Head = Vector3.new(1.1, 1.15, 1.1), Snout = Vector3.new(0.7, 0.65, 0.75), Ear = "folded", EarSize = 0.5,
		Tail = "straight", TailLength = 0.75, TailAngle = 10, NeckRaise = 0.2 }),
	-- sausage dog: very long torso, very short legs, long floppy ears
	long_low = body("long_low", { Torso = Vector3.new(1.25, 1.15, 3.9), LegLength = 0.6, LegThick = 0.38,
		Head = Vector3.new(1.0, 1.0, 1.15), Snout = Vector3.new(0.55, 0.5, 0.95), Ear = "floppy", EarSize = 1.0,
		Tail = "whip", TailLength = 1.3, TailAngle = 70, NeckRaise = 0.15 }),
	-- small fluffball: round fluffy body, plume tail over the back
	small_fluffy = body("small_fluffy", { Torso = Vector3.new(1.6, 1.5, 2.1), LegLength = 0.85, LegThick = 0.42,
		Head = Vector3.new(1.35, 1.3, 1.25), Snout = Vector3.new(0.5, 0.4, 0.35), Ear = "pointy", EarSize = 0.55,
		Tail = "plume", TailLength = 1.1, TailAngle = 5, NeckRaise = 0.2, Fluffy = true }),
	-- herding loaf: long-ish low torso, huge upright ears, stub tail
	corgi_type = body("corgi_type", { Torso = Vector3.new(1.55, 1.3, 3.0), LegLength = 0.7, LegThick = 0.45,
		Head = Vector3.new(1.2, 1.1, 1.2), Snout = Vector3.new(0.6, 0.5, 0.7), Ear = "pointy", EarSize = 1.0,
		Tail = "stub", TailLength = 0.35, TailAngle = 40, NeckRaise = 0.25 }),
	-- the reference dog: balanced hound/retriever-lite
	medium_lean = body("medium_lean", { Torso = Vector3.new(1.3, 1.3, 2.8), LegLength = 1.4, LegThick = 0.36,
		Head = Vector3.new(1.0, 1.0, 1.1), Snout = Vector3.new(0.55, 0.5, 0.8), Ear = "floppy", EarSize = 0.85,
		Tail = "straight", TailLength = 1.2, TailAngle = 50, NeckRaise = 0.3 }),
	-- bully build: wide chest, broad head, short muzzle
	medium_stocky = body("medium_stocky", { Torso = Vector3.new(1.85, 1.6, 2.5), LegLength = 1.1, LegThick = 0.52,
		Head = Vector3.new(1.45, 1.3, 1.2), Snout = Vector3.new(0.9, 0.6, 0.45), Ear = "round", EarSize = 0.45,
		Tail = "straight", TailLength = 0.7, TailAngle = 65, NeckRaise = 0.1 }),
	-- spitz/collie: medium fluffy body, pointy ears, plume tail
	medium_fluffy = body("medium_fluffy", { Torso = Vector3.new(1.6, 1.5, 2.8), LegLength = 1.25, LegThick = 0.46,
		Head = Vector3.new(1.2, 1.15, 1.15), Snout = Vector3.new(0.55, 0.5, 0.75), Ear = "pointy", EarSize = 0.65,
		Tail = "plume", TailLength = 1.3, TailAngle = 25, NeckRaise = 0.3, Fluffy = true }),
	-- sighthound: deep narrow chest, very long legs, long snout, drooping whip tail
	large_lean = body("large_lean", { Torso = Vector3.new(1.2, 1.45, 3.3), LegLength = 2.1, LegThick = 0.32,
		Head = Vector3.new(0.85, 0.9, 1.25), Snout = Vector3.new(0.45, 0.45, 1.2), Ear = "folded", EarSize = 0.55,
		Tail = "whip", TailLength = 1.9, TailAngle = 125, NeckRaise = 0.6 }),
	-- retriever/shepherd/boxer: big, muscular, balanced
	large_athletic = body("large_athletic", { Torso = Vector3.new(1.7, 1.7, 3.3), LegLength = 1.75, LegThick = 0.5,
		Head = Vector3.new(1.25, 1.2, 1.3), Snout = Vector3.new(0.7, 0.6, 0.85), Ear = "floppy", EarSize = 0.8,
		Tail = "straight", TailLength = 1.45, TailAngle = 70, NeckRaise = 0.4 }),
	-- big fluffy: husky/malamute/golden-floof, curled plume tail
	large_fluffy = body("large_fluffy", { Torso = Vector3.new(1.95, 1.85, 3.3), LegLength = 1.65, LegThick = 0.6,
		Head = Vector3.new(1.45, 1.4, 1.4), Snout = Vector3.new(0.7, 0.6, 0.8), Ear = "pointy", EarSize = 0.7,
		Tail = "plume", TailLength = 1.6, TailAngle = 30, NeckRaise = 0.4, Fluffy = true }),
	-- mastiff/great dane: massive frame, heavy head, thick legs
	giant = body("giant", { Torso = Vector3.new(2.1, 2.0, 3.6), LegLength = 2.0, LegThick = 0.72,
		Head = Vector3.new(1.7, 1.6, 1.55), Snout = Vector3.new(1.0, 0.85, 0.8), Ear = "floppy", EarSize = 0.95,
		Tail = "straight", TailLength = 1.6, TailAngle = 95, NeckRaise = 0.35 }),
	-- newfie/bernese/pyrenees: massive and fluffy, droopy ears
	giant_fluffy = body("giant_fluffy", { Torso = Vector3.new(2.3, 2.15, 3.6), LegLength = 1.85, LegThick = 0.8,
		Head = Vector3.new(1.85, 1.75, 1.65), Snout = Vector3.new(0.9, 0.8, 0.8), Ear = "floppy", EarSize = 1.0,
		Tail = "plume", TailLength = 1.8, TailAngle = 55, NeckRaise = 0.35, Fluffy = true }),
	-- poodle: slim body on long legs, pom-poms, long floppy puffy ears, pom tail
	poodle_type = body("poodle_type", { Torso = Vector3.new(1.3, 1.4, 2.4), LegLength = 1.8, LegThick = 0.3,
		Head = Vector3.new(1.0, 1.1, 1.1), Snout = Vector3.new(0.45, 0.45, 0.95), Ear = "floppy", EarSize = 1.05,
		Tail = "pom", TailLength = 0.9, TailAngle = 10, NeckRaise = 0.55, Poodle = true }),
} :: { [string]: BodyType }

BodyTypes.Default = "medium_lean"

function BodyTypes.Get(id: string?): BodyType
	return BodyTypes.ById[id or ""] or BodyTypes.ById[BodyTypes.Default]
end

-- Puppy proportions: big head, shorter legs and snout (applied before the overall puppy scale).
BodyTypes.Puppy = {
	OverallScale = 0.6,
	HeadMult = 1.3,
	LegMult = 0.8,
	SnoutMult = 0.6,
	EarMult = 1.15,
}

return BodyTypes
