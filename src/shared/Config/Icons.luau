--!strict
-- Uploaded image asset ids for the pixel icons (assets/icons/<name>.png). 0 = not uploaded yet: the client
-- then draws the icon from PixelIcons as a grid of Frames, so the game runs with no uploads at all.
-- After uploading via Studio's Asset Manager (Bulk Import), paste each id here. Never upload an icon
-- that is not in tools/icons.py.
local Icons = {}

Icons.AssetIds = {} :: { [string]: number }

-- Example once uploaded:
-- Icons.AssetIds.cash = 123456789

function Icons.Get(name: string): number
	return Icons.AssetIds[name] or 0
end

return Icons
