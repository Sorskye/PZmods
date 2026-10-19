-- Immersive Snow: ground cleared of the vanilla snow with a shovel (ISnow_Shovel.lua): which squares,
-- and how the snow comes back on them.
--
-- A cleared square is a key "x,y" (ground level only: FBORenderSnow keeps one grid for z 0 and one
-- shared by every upper level, so only z 0 is cleared) with the snowfall that has come down on it
-- since, in game hours of full snowfall. Fresh snow covers it again: at REFILL_HOURS of that the
-- square is snowy again (the vanilla tile comes back whole: it is there or not). With the snow gone
-- from the ground (ISnow.groundCover 0: snow target 0, or out of the erosion winter) every cleared
-- square goes, so the next snow lies everywhere.
--
-- SP: kept in the global ModData KEY, so it lives in the save, and aged on this client.
-- MP: the server keeps and ages it (the same ModData, in the server's save); each client has a copy
-- from the server's commands (ISnow_ShovelServer.lua):
--   client -> server "shovel" { x, y }: a player cleared a square; "clearedQuery": send me all;
--   server -> clients "cleared" { x, y }, "uncleared" { keys = { key, ... } } and "clearedAll" { keys }
--   (the whole set), these two in parts (part = 1.., last = true on the last).
-- A client only draws from its copy (ISnow_Shovel.lua); the copy is never saved.

require "ImmersiveSnow/ISnow_Config"

local Cleared = {}
ISnow.Cleared = Cleared

Cleared.KEY = "ISnowCleared"
Cleared.MODULE = "ISnow"
Cleared.REFILL_HOURS = 3     -- game hours of full snowfall (intensity 1) that cover a cleared square again
Cleared.MAX = 6000           -- cleared squares kept at most; more are refused

-- [key] = game hours of full snowfall on it since it was cleared
Cleared.squares = {}
local count = 0

-- Called on this client when a square was cleared (x, y) or got its snow back (x, y, true);
-- set by ISnow_Shovel.lua.
Cleared.onChange = nil

function Cleared.key(x, y)
    return tostring(math.floor(x)) .. "," .. tostring(math.floor(y))
end

-- x, y of a key, nil for anything else.
function Cleared.parse(key)
    if type(key) ~= "string" then return nil end
    local x, y = string.match(key, "^(%-?%d+),(%-?%d+)$")
    if not x then return nil end
    return tonumber(x), tonumber(y)
end

function Cleared.has(x, y)
    return Cleared.squares[Cleared.key(x, y)] ~= nil
end

function Cleared.count() return count end

-- Whether this game keeps the squares itself (SP, or the MP server), rather than a copy.
function Cleared.authority()
    return not isClient()
end

local function changed(key, back)
    local fn = Cleared.onChange
    if not fn then return end
    local x, y = Cleared.parse(key)
    if x then pcall(fn, x, y, back) end
end

-- Takes the squares from the save's ModData (SP and the server, on OnInitGlobalModData).
function Cleared.load()
    if not Cleared.authority() then return end
    local data = ModData.getOrCreate(Cleared.KEY)
    if type(data.sq) ~= "table" then data.sq = {} end
    Cleared.squares = data.sq
    count = 0
    local bad = nil
    for key, fall in pairs(Cleared.squares) do
        if Cleared.parse(key) and type(fall) == "number" then
            count = count + 1
        else
            bad = bad or {}
            bad[#bad + 1] = key
        end
    end
    if bad then
        for i = 1, #bad do Cleared.squares[bad[i]] = nil end
    end
    for key in pairs(Cleared.squares) do changed(key, false) end
end

-- Marks x, y cleared; true if it was not. Where the squares are kept (SP, server), and on an MP
-- client for the copy.
function Cleared.add(x, y)
    local key = Cleared.key(x, y)
    if Cleared.squares[key] then
        Cleared.squares[key] = 0
        return false
    end
    if count >= Cleared.MAX then return false end
    Cleared.squares[key] = 0
    count = count + 1
    changed(key, false)
    return true
end

-- Gives the squares of keys their snow back.
function Cleared.remove(keys)
    for i = 1, #keys do
        local key = keys[i]
        if Cleared.squares[key] then
            Cleared.squares[key] = nil
            count = count - 1
            changed(key, true)
        end
    end
end

function Cleared.removeAll()
    local keys = {}
    for key in pairs(Cleared.squares) do keys[#keys + 1] = key end
    Cleared.remove(keys)
    return keys
end

-- An MP client's copy becomes keys (the server's whole set).
function Cleared.replace(keys)
    local want = {}
    for i = 1, #keys do
        if Cleared.parse(keys[i]) then want[keys[i]] = true end
    end
    local gone = {}
    for key in pairs(Cleared.squares) do
        if not want[key] then gone[#gone + 1] = key end
    end
    Cleared.remove(gone)
    for key in pairs(want) do
        if not Cleared.squares[key] then
            local x, y = Cleared.parse(key)
            Cleared.add(x, y)
        end
    end
end

function Cleared.keys()
    local keys = {}
    for key in pairs(Cleared.squares) do keys[#keys + 1] = key end
    return keys
end

-- One step of dtHours game hours where the squares are kept: fresh snowfall covers them, no snow
-- on the ground clears the list. The keys that got their snow back, nil for none.
function Cleared.age(dtHours)
    if count == 0 then return nil end
    if ISnow.groundCover() <= 0 then return Cleared.removeAll() end
    local clim = getClimateManager()
    if not clim:isSnowing() then return nil end
    local fall = clim:getSnowIntensity() * dtHours
    if fall <= 0 then return nil end
    local back = nil
    for key, had in pairs(Cleared.squares) do
        local now = had + fall
        Cleared.squares[key] = now
        if now >= Cleared.REFILL_HOURS - 1e-6 then
            back = back or {}
            back[#back + 1] = key
        end
    end
    if back then Cleared.remove(back) end
    return back
end

-- SP: this client keeps the squares (the server does in MP: ISnow_ShovelServer.lua).
if not isClient() and not isServer() then
    Events.OnInitGlobalModData.Add(function()
        local ok, err = pcall(Cleared.load)
        if not ok then print("[ImmersiveSnow] cleared squares: load failed: " .. tostring(err)) end
    end)
    Events.EveryTenMinutes.Add(function()
        local ok, err = pcall(Cleared.age, 1 / 6)
        if not ok then print("[ImmersiveSnow] cleared squares: ageing failed: " .. tostring(err)) end
    end)
end
