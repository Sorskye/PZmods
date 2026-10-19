-- Immersive Snow, MP server: the squares cleared of snow with a shovel (ISnow_Cleared.lua: what is
-- kept and the commands). A "shovel" report is taken from a player standing within REACH of the
-- square, one per MIN_GAP_MS, on ground level; the server ages the list every ten game minutes and
-- tells every client what got its snow back. Only the look and the footprints depend on it.

if not isServer() then return end

require "ImmersiveSnow/ISnow_Cleared"

local Cleared = ISnow.Cleared
local REACH = 4              -- tiles from the player's square the cleared square may be
local MIN_GAP_MS = 300       -- a shovelled square takes a few seconds; this only stops a flood
local PART = 400             -- keys per command: a long list goes in parts

local lastFrom = {}          -- [online id] = getTimestampMs() of the last report taken

local function onShovel(player, args)
    local x, y = tonumber(args.x), tonumber(args.y)
    if not x or not y or x ~= x or y ~= y then return end
    x, y = math.floor(x), math.floor(y)
    if math.abs(x - player:getX()) > REACH or math.abs(y - player:getY()) > REACH then return end
    local from = player:getOnlineID()
    local t = getTimestampMs()
    if lastFrom[from] and t - lastFrom[from] < MIN_GAP_MS and t >= lastFrom[from] then return end
    lastFrom[from] = t
    if Cleared.add(x, y) or Cleared.has(x, y) then
        sendServerCommand(Cleared.MODULE, "cleared", { x = x, y = y })
    end
end

-- Sends command with keys in parts of PART (part = 1.., last = true on the last), to player or to
-- every client.
local function sendKeys(player, command, keys)
    local n = #keys
    local part = 1
    local i = 1
    repeat
        local list = {}
        for j = i, math.min(n, i + PART - 1) do list[#list + 1] = keys[j] end
        i = i + PART
        local args = { keys = list, part = part, last = i > n }
        if player then
            sendServerCommand(player, Cleared.MODULE, command, args)
        else
            sendServerCommand(Cleared.MODULE, command, args)
        end
        part = part + 1
    until i > n
end

local function onClientCommand(module, command, player, args)
    if module ~= Cleared.MODULE or not player then return end
    if command == "shovel" and type(args) == "table" then
        onShovel(player, args)
    elseif command == "clearedQuery" then
        sendKeys(player, "clearedAll", Cleared.keys())
    end
end
Events.OnClientCommand.Add(function(module, command, player, args)
    local ok, err = pcall(onClientCommand, module, command, player, args)
    if not ok then print("[ImmersiveSnow] shovel command failed: " .. tostring(err)) end
end)

Events.OnInitGlobalModData.Add(function()
    local ok, err = pcall(Cleared.load)
    if not ok then print("[ImmersiveSnow] cleared squares: load failed: " .. tostring(err)) end
end)

Events.EveryTenMinutes.Add(function()
    local ok, back = pcall(Cleared.age, 1 / 6)
    if not ok then
        print("[ImmersiveSnow] cleared squares: ageing failed: " .. tostring(back))
    elseif back then
        sendKeys(nil, "uncleared", back)
    end
end)

Events.EveryHours.Add(function() lastFrom = {} end)
