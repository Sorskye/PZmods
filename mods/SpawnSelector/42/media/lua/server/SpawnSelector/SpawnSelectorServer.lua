require "SpawnSelector/SpawnSelectorRegions"

local MODULE = "SpawnSelector"
local COMMAND = "SelectSpawn"
local pendingSpawns = {}
local selectingPlayers = {}
local arrivalSafety = {}
local safetyTick = 0
local deathTrackedAlive = {}

local function isFiniteNumber(value)
    return type(value) == "number" and value == value and value > -1000000 and value < 1000000
end

local function isBlockedSafehouseSpawn(player, x, y)
    local safehouses = SafeHouse.getSafehouseList()

    for index = 0, safehouses:size() - 1 do
        local safehouse = safehouses:get(index)
        if safehouse:containsLocation(x, y) and not safehouse:playerAllowed(player) then
            return true
        end
    end

    return false
end

local function rollRandomSpawn(player, bounds)
    for attempt = 1, 100 do
        local x, y = SpawnSelector.rollRandomPosition(bounds, player)
        if not x then
            return nil, nil
        end
        x = x + 0.5
        y = y + 0.5
        if not isBlockedSafehouseSpawn(player, x, y) then
            return x, y
        end
    end

    return nil, nil
end

local function rollRandomBuildingSpawn(player, bounds)
    for attempt = 1, 20 do
        local x, y = SpawnSelector.rollRandomBuildingTile(bounds, player)
        if not x then
            return nil, nil
        end
        x = x + 0.5
        y = y + 0.5
        if not isBlockedSafehouseSpawn(player, x, y) then
            return x, y
        end
    end

    return nil, nil
end

local function updateDeathZoneTracking()
    if not SpawnSelector.isDeathZoneFeatureEnabled() then
        return
    end

    local players = getOnlinePlayers()
    for index = 0, players:size() - 1 do
        local player = players:get(index)
        local identity = SpawnSelector.getPlayerIdentity(player)
        if identity then
            local dead = player:isDead()
            if deathTrackedAlive[identity] == nil then
                deathTrackedAlive[identity] = not dead
            elseif deathTrackedAlive[identity] and dead then
                SpawnSelector.recordDeathZone(player)
                deathTrackedAlive[identity] = false
            elseif not dead then
                deathTrackedAlive[identity] = true
            end
        end
    end
end

local function movePlayer(player, x, y, z)
    player:setX(x)
    player:setY(y)
    player:setZ(z)
    player:setLastX(x)
    player:setLastY(y)
    player:setLastZ(z)
end

local function clearNearbyZombies(x, y, z, radius, room)
    local zombies = getCell():getZombieList()
    local clearRadius = radius or SpawnSelector.SAFE_RADIUS
    local radiusSquared = clearRadius * clearRadius

    for index = zombies:size() - 1, 0, -1 do
        local zombie = zombies:get(index)
        local deltaX = zombie:getX() - x
        local deltaY = zombie:getY() - y
        local zombieSquare = zombie:getSquare()
        local sameFloor = zombieSquare and zombieSquare:getZ() == math.floor(z)
        local inRoom = room and zombieSquare and zombieSquare:getRoom() == room
        if sameFloor and (inRoom or deltaX * deltaX + deltaY * deltaY <= radiusSquared) then
            zombie:removeFromWorld()
            zombie:removeFromSquare()
        end
    end
end

local function turnOnRoomLights(square)
    local room = square:getRoom()
    if not room then
        return
    end

    local switches = room:getLightSwitches()
    for index = 0, switches:size() - 1 do
        switches:get(index):setActive(true)
    end
end

local function disableBuildingAlarm(square)
    local building = square and square:getBuilding()
    local definition = building and building:getDef()
    if definition and definition:isAlarmed() then
        definition:setAlarmed(false)
    end
end

local function disableBuildingAlarmAt(x, y, z)
    local world = getWorld()
    local metaGrid = world and world:getMetaGrid()
    local definition = metaGrid and metaGrid:getBuildingAt(math.floor(x), math.floor(y), z or 0)
    if definition and definition:isAlarmed() then
        definition:setAlarmed(false)
    end
end

local function rejectRandomSearch(player, spawn)
    movePlayer(
        player,
        SpawnSelector.STAGING_X + 0.5,
        SpawnSelector.STAGING_Y + 0.5,
        SpawnSelector.STAGING_Z
    )
    local data = player:getModData()
    data.SpawnSelectorComplete = false
    player:transmitModData()
    sendServerCommand(player, MODULE, "SpawnRejected", {
        reason = spawn.randomBuilding and "RandomBuildingUnavailable" or "RandomUnavailable",
        x = SpawnSelector.STAGING_X + 0.5,
        y = SpawnSelector.STAGING_Y + 0.5,
        z = SpawnSelector.STAGING_Z,
    })
    return true
end

local function rerollRandomSearch(player, spawn)
    if spawn.randomAttempts >= SpawnSelector.RANDOM_BUILDING_MAX_ATTEMPTS then
        return rejectRandomSearch(player, spawn)
    end

    if spawn.randomBuilding then
        spawn.x, spawn.y = rollRandomBuildingSpawn(player, spawn.randomBounds)
    else
        spawn.x, spawn.y = rollRandomSpawn(player, spawn.randomBounds)
    end
    if not spawn.x then
        return rejectRandomSearch(player, spawn)
    end

    spawn.randomAttempts = spawn.randomAttempts + 1
    spawn.validationStartedAt = getTimestampMs()
    disableBuildingAlarmAt(spawn.x, spawn.y, spawn.z)
    movePlayer(player, spawn.x, spawn.y, spawn.z)
    sendServerCommand(player, MODULE, "RandomRelocated", {
        x = spawn.x,
        y = spawn.y,
        z = spawn.z,
    })
    return false
end

local function finishPendingSpawn(player, spawn)
    -- BuildingDef is available from the meta-grid before its squares are streamed in.
    -- Clear the alarm before the validation teleport can count as entering it.
    disableBuildingAlarmAt(spawn.x, spawn.y, spawn.z)
    movePlayer(player, spawn.x, spawn.y, spawn.validationZ)
    local validationSquare = getCell():getGridSquare(
        math.floor(spawn.x),
        math.floor(spawn.y),
        spawn.validationZ
    )
    local square = getCell():getGridSquare(math.floor(spawn.x), math.floor(spawn.y), spawn.z)
    if not square then
        if spawn.randomBounds
            and getTimestampMs() - spawn.validationStartedAt >= SpawnSelector.LAYER_VALIDATION_MS then
            return rerollRandomSearch(player, spawn)
        end
        if spawn.validateLayer
            and (validationSquare
                or getTimestampMs() - spawn.validationStartedAt >= SpawnSelector.LAYER_VALIDATION_MS) then
            movePlayer(
                player,
                SpawnSelector.STAGING_X + 0.5,
                SpawnSelector.STAGING_Y + 0.5,
                SpawnSelector.STAGING_Z
            )
            sendServerCommand(player, MODULE, "SpawnRejected", {
                reason = "LayerUnavailable",
                x = SpawnSelector.STAGING_X + 0.5,
                y = SpawnSelector.STAGING_Y + 0.5,
                z = SpawnSelector.STAGING_Z,
            })
            return true
        end
        return false
    end

    if not square:getFloor() then
        if spawn.randomBounds then
            return rerollRandomSearch(player, spawn)
        end
        movePlayer(
            player,
            SpawnSelector.STAGING_X + 0.5,
            SpawnSelector.STAGING_Y + 0.5,
            SpawnSelector.STAGING_Z
        )
        sendServerCommand(player, MODULE, "SpawnRejected", {
            reason = "LayerUnavailable",
            x = SpawnSelector.STAGING_X + 0.5,
            y = SpawnSelector.STAGING_Y + 0.5,
            z = SpawnSelector.STAGING_Z,
        })
        return true
    end

    if square:isWaterSquare() and not spawn.randomBounds then
        movePlayer(
            player,
            SpawnSelector.STAGING_X + 0.5,
            SpawnSelector.STAGING_Y + 0.5,
            SpawnSelector.STAGING_Z
        )
        sendServerCommand(player, MODULE, "SpawnRejected", {
            reason = "Water",
            x = SpawnSelector.STAGING_X + 0.5,
            y = SpawnSelector.STAGING_Y + 0.5,
            z = SpawnSelector.STAGING_Z,
        })
        return true
    end

    if spawn.randomBounds and square:isWaterSquare() then
        return rerollRandomSearch(player, spawn)
    end

    if spawn.randomBuilding and not square:getBuilding() then
        return rerollRandomSearch(player, spawn)
    end

    if not SpawnSelector.isSquareRoomTypeAllowed(square) then
        if spawn.randomBounds then
            return rerollRandomSearch(player, spawn)
        end
        movePlayer(
            player,
            SpawnSelector.STAGING_X + 0.5,
            SpawnSelector.STAGING_Y + 0.5,
            SpawnSelector.STAGING_Z
        )
        sendServerCommand(player, MODULE, "SpawnRejected", {
            reason = "BlockedRoomType",
            x = SpawnSelector.STAGING_X + 0.5,
            y = SpawnSelector.STAGING_Y + 0.5,
            z = SpawnSelector.STAGING_Z,
        })
        return true
    end

    disableBuildingAlarm(square)
    local newKey = SpawnSelector.giveBuildingKey(player, square)
    if newKey then
        sendAddItemToContainer(player:getInventory(), newKey)
    end
    movePlayer(player, spawn.x, spawn.y, spawn.z)
    clearNearbyZombies(spawn.x, spawn.y, spawn.z, SpawnSelector.ARRIVAL_SAFE_RADIUS, square:getRoom())
    turnOnRoomLights(square)
    selectingPlayers[player] = nil
    arrivalSafety[player] = {
        x = spawn.x,
        y = spawn.y,
        z = spawn.z,
        expiresAt = getTimestampMs() + SpawnSelector.ARRIVAL_GRACE_MS,
    }
    if spawn.randomBounds then
        sendServerCommand(player, MODULE, "RandomSpawnReady", {
            clearMapKnowledge = spawn.randomBuilding,
        })
    elseif spawn.validateLayer then
        local data = player:getModData()
        data.SpawnSelectorComplete = true
        player:transmitModData()
        sendServerCommand(player, MODULE, "SpawnConfirmed", {
            x = spawn.x,
            y = spawn.y,
            z = spawn.z,
            random = false,
        })
    end
    return true
end

local function onClientCommand(module, command, player, args)
    if module ~= MODULE then
        return
    end

    if command == "SelectionStarted" then
        if not player:getModData().SpawnSelectorComplete then
            selectingPlayers[player] = true
            clearNearbyZombies(player:getX(), player:getY(), player:getZ())
        end
        sendServerCommand(player, MODULE, "DeathZones", {
            zones = SpawnSelector.getActiveDeathZones(player),
        })
        return
    end

    if command ~= COMMAND then
        return
    end

    if not args
        or not isFiniteNumber(args.x)
        or not isFiniteNumber(args.y)
        or not isFiniteNumber(args.z) then
        return
    end

    local data = player:getModData()
    if data.SpawnSelectorComplete then
        return
    end

    local x = math.floor(args.x) + 0.5
    local y = math.floor(args.y) + 0.5
    local z = math.floor(args.z)
    local randomBounds = nil

    if args.random
        and isFiniteNumber(args.minX)
        and isFiniteNumber(args.minY)
        and isFiniteNumber(args.maxX)
        and isFiniteNumber(args.maxY)
        and args.minX <= args.maxX
        and args.minY <= args.maxY then
        randomBounds = {
            minX = math.floor(args.minX),
            minY = math.floor(args.minY),
            maxX = math.floor(args.maxX),
            maxY = math.floor(args.maxY),
        }
    end

    if randomBounds then
        z = 0
    elseif z < SpawnSelector.MIN_Z or z > SpawnSelector.MAX_Z then
        sendServerCommand(player, MODULE, "SpawnRejected", {
            reason = "InvalidLayer",
        })
        return
    end

    if randomBounds and args.randomBuilding then
        x, y = rollRandomBuildingSpawn(player, randomBounds)
        if not x then
            sendServerCommand(player, MODULE, "SpawnRejected", {
                reason = "RandomBuildingUnavailable",
            })
            return
        end
    elseif randomBounds and (isBlockedSafehouseSpawn(player, x, y) or SpawnSelector.isDeathZoneBlocked(player, x, y)) then
        x, y = rollRandomSpawn(player, randomBounds)
        if not x then
            sendServerCommand(player, MODULE, "SpawnRejected", {
                reason = "RandomUnavailable",
            })
            return
        end
    elseif isBlockedSafehouseSpawn(player, x, y) then
        sendServerCommand(player, MODULE, "SpawnRejected", {
            reason = "Safehouse",
        })
        return
    elseif SpawnSelector.isDeathZoneBlocked(player, x, y) then
        sendServerCommand(player, MODULE, "SpawnRejected", {
            reason = "DeathZone",
        })
        return
    end

    selectingPlayers[player] = true
    disableBuildingAlarmAt(x, y, z)
    movePlayer(player, x, y, 0)
    local validateLayer = not randomBounds
    local spawn = {
        x = x,
        y = y,
        z = z,
        validationZ = 0,
        randomBounds = randomBounds,
        random = randomBounds ~= nil,
        randomBuilding = randomBounds ~= nil and args.randomBuilding == true,
        randomAttempts = 1,
        validateLayer = validateLayer,
        validationStartedAt = getTimestampMs(),
    }
    pendingSpawns[player] = spawn
    if validateLayer then
        sendServerCommand(player, MODULE, "SpawnCandidate", {
            x = spawn.x,
            y = spawn.y,
            z = spawn.validationZ,
        })
    else
        data.SpawnSelectorComplete = true
        player:transmitModData()
        sendServerCommand(player, MODULE, "SpawnConfirmed", {
            x = spawn.x,
            y = spawn.y,
            z = spawn.z,
            random = spawn.random,
        })
    end
end

local function onTick()
    updateDeathZoneTracking()

    safetyTick = safetyTick + 1
    if safetyTick >= 15 then
        safetyTick = 0
        for player in pairs(selectingPlayers) do
            clearNearbyZombies(
                SpawnSelector.STAGING_X + 0.5,
                SpawnSelector.STAGING_Y + 0.5,
                SpawnSelector.STAGING_Z
            )
        end
        for player, safety in pairs(arrivalSafety) do
            if getTimestampMs() >= safety.expiresAt then
                arrivalSafety[player] = nil
            else
                local square = getCell():getGridSquare(
                    math.floor(safety.x),
                    math.floor(safety.y),
                    safety.z
                )
                if square then
                    turnOnRoomLights(square)
                end
                clearNearbyZombies(
                    safety.x,
                    safety.y,
                    safety.z,
                    SpawnSelector.ARRIVAL_SAFE_RADIUS,
                    square and square:getRoom() or nil
                )
            end
        end
    end

    for player, spawn in pairs(pendingSpawns) do
        if finishPendingSpawn(player, spawn) then
            pendingSpawns[player] = nil
        end
    end
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnTick.Add(onTick)
