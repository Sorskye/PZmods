-- Immersive Snow, MP server: passes on the snow on vehicles their drivers report, and tells the
-- clients the vehicle scripts' parts signature (ISnow_VehicleSnow.lua, "Multiplayer").
--
-- "vehSnow" (id = vehicle id, s = script full name, l = snow level, i = icing level, f = frost on
-- the glass, missing from a client without it; g = the glass wiped, a boolean, missing from a client
-- without it; h = how much less snow the hood has, melted by the engine, missing from a client
-- without it): kept per vehicle id with the time it came, and sent
-- to every client with from = the sender's online id.
-- "vehFrost" (id): a player scraped the frost off a vehicle: the kept report gets none (and wiped
-- glass), the time is
-- kept, and every client is told (from as above). A query for a vehicle scraped after its last
-- report (or never reported: parked, nobody drove it) gets "vehFrost" with age too, so a player
-- meeting it later does not see it frosted over again.
-- "vehSnowQuery" (id): the kept report back to the client that asks, with age = game hours since.
-- Nothing is saved: vehicle ids are only the same while the server runs. Reports older than
-- KEEP_HOURS are dropped every game hour. Only the look: a client could only paint snow on
-- vehicles, so the values are only kept in range and each sender is held to one report per
-- MIN_GAP_MS.
-- "shellsQuery": the parts signature (ISnow_VehicleShells.lua); "shellsDetailQuery": the part
-- count of every vehicle script, for a client whose signature differs.

if not isServer() then return end

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_VehicleShells"

local MODULE = "ISnow"
local KEEP_HOURS = 72     -- as MP_KEEP_HOURS in ISnow_VehicleSnow.lua
local MIN_GAP_MS = 200      -- clients keep REPORT_GAP_MS (500) between their reports
local MAX_NAME = 200

local reports = {}        -- [vehicle id] = { s, l, i, f, g, h, at = world hours }
local lastFrom = {}       -- [online id] = getTimestampMs() of the last report taken
local scrapes = {}        -- [vehicle id] = world hours of the last scrape
local lastScrape = {}     -- [online id] = getTimestampMs() of the last scrape taken (apart from reports)

local function clamp01(v)
    v = tonumber(v)
    if not v or v ~= v then return nil end
    return math.max(0, math.min(1, v))
end

local function now() return getGameTime():getWorldAgeHours() end

local function onVehSnow(player, args)
    local id = tonumber(args.id)
    local l, i, f, h = clamp01(args.l), clamp01(args.i), clamp01(args.f), clamp01(args.h)
    local g = nil
    if type(args.g) == "boolean" then g = args.g end
    if not id or id < 0 or not l or not i or type(args.s) ~= "string" or #args.s > MAX_NAME then return end
    local from = player:getOnlineID()
    local t = getTimestampMs()
    if lastFrom[from] and t - lastFrom[from] < MIN_GAP_MS and t >= lastFrom[from] then return end
    lastFrom[from] = t
    reports[math.floor(id)] = { s = args.s, l = l, i = i, f = f, g = g, h = h, at = now() }
    sendServerCommand(MODULE, "vehSnow", { id = math.floor(id), s = args.s, l = l, i = i, f = f, g = g, h = h, from = from })
end

local function onVehFrost(player, args)
    local id = tonumber(args.id)
    if not id or id < 0 then return end
    id = math.floor(id)
    local from = player:getOnlineID()
    local t = getTimestampMs()
    if lastScrape[from] and t - lastScrape[from] < MIN_GAP_MS and t >= lastScrape[from] then return end
    lastScrape[from] = t
    if reports[id] then reports[id].f, reports[id].g = 0, true end
    scrapes[id] = now()
    sendServerCommand(MODULE, "vehFrost", { id = id, from = from })
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE or not player or type(args) ~= "table" then return end
    if command == "vehSnow" then
        onVehSnow(player, args)
    elseif command == "vehFrost" then
        onVehFrost(player, args)
    elseif command == "vehSnowQuery" then
        local id = tonumber(args.id)
        local r = id and reports[id]
        if r then
            sendServerCommand(player, MODULE, "vehSnow",
                { id = id, s = r.s, l = r.l, i = r.i, f = r.f, g = r.g, h = r.h, age = math.max(0, now() - r.at) })
        end
        local sc = id and scrapes[id]
        if sc and (not r or sc >= r.at) then
            sendServerCommand(player, MODULE, "vehFrost", { id = id, age = math.max(0, now() - sc) })
        end
    elseif command == "shellsQuery" then
        local sig, n = ISnow.VehicleShells.signature()
        sendServerCommand(player, MODULE, "shells", { sig = sig, n = n })
    elseif command == "shellsDetailQuery" then
        sendServerCommand(player, MODULE, "shellsDetail", { counts = ISnow.VehicleShells.partCounts() })
    end
end
Events.OnClientCommand.Add(function(module, command, player, args)
    local ok, err = pcall(onClientCommand, module, command, player, args)
    if not ok then print("[ImmersiveSnow] vehicle snow command failed: " .. tostring(err)) end
end)

local function dropOld()
    local t = now()
    local old = {}
    for id, r in pairs(reports) do
        if t - r.at > KEEP_HOURS or t < r.at then table.insert(old, id) end
    end
    for _, id in ipairs(old) do reports[id] = nil end
    old = {}
    for id, at in pairs(scrapes) do
        if t - at > KEEP_HOURS or t < at then table.insert(old, id) end
    end
    for _, id in ipairs(old) do scrapes[id] = nil end
    lastFrom, lastScrape = {}, {}
end
Events.EveryHours.Add(function() pcall(dropOld) end)
