--!nocheck
-- Platform queue order (src/server/Services/ThrowQueue.luau).   lune run tools/tests/throwqueue.luau
local process = require("@lune/process")
local Loader = require("./loader")
local check = Loader.Check

local Server = Loader.Mount("src/server")
local ThrowQueue = Loader.Require(Server.Services.ThrowQueue)

local q = ThrowQueue.new()
check(q:Head() == nil and q:Count() == 0, "starts empty")
check(q:Join("A") == 1 and q:Join("B") == 2 and q:Join("C") == 3, "arrivals join the back")
check(q:Join("B") == 2, "joining twice keeps the place")
check(q:Position("A") == 1 and q:Position("C") == 3 and q:Position("Z") == 0, "positions (0 = not queued)")
check(q:ToBack("A") and q:Head() == "B" and q:Position("A") == 3, "turn over: thrower to the back, line advances")
check(q:Remove("C") and q:Position("A") == 2 and not q:Remove("C"), "leaving removes and closes the gap")
check(q:Remove("B") and q:Head() == "A", "head leaves: next in line takes the turn")
check(not q:ToBack("A") and q:Head() == "A", "alone: ToBack is a no-op")
for _, k in { "B", "C", "D", "E", "F" } do
	q:Join(k)
end
local snap = q:Snapshot()
check(#snap == 6 and snap[1] == "A" and snap[6] == "F", "six players: one throwing, five waiting")
if Loader.Done("throwqueue") > 0 then
	process.exit(1)
end
