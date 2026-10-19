-- Ensure we have access to the UI global for the floor container
require "ISUI/ISInventoryPage"

BAM = BAM or {}


function BAM.GetNextUninstallablePart(player, vehicle)
    --DebugLog.log("-> Searching for next uninstallable part...")
    -- Collect all installed car parts into a list for sorting
    local validParts = {}
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        table.insert(validParts, part)
    end

    local sortedParts = BAM.SortParts(validParts)

    -- Check each part for uninstall possibility and XP eligibility, return the first one found
    for _, part in ipairs(sortedParts) do
        if BAM.PartCanBeUninstalled(player, vehicle, part) then
            return part
        end
    end
    return nil
end


function BAM.GetNextInstallablePartAndItem(player, vehicle)
    --DebugLog.log("-> Searching for next installable part...")
    -- Collect all uninstalled car parts into a list for sorting
    local validParts = {}
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        table.insert(validParts, part)
    end

    local sortedParts = BAM.SortParts(validParts)

    -- Check each part for install possibility, return the first one found
    for _, part in ipairs(sortedParts) do
        local item = BAM.PartCanBeInstalled(player, vehicle, part)
        if item then
            return part, item
        end
    end
    return nil, nil
end


function BAM.PartCanBeUninstalled(player, vehicle, part)
    --DebugLog.log("Checking if part " .. part:getId() .. " can be uninstalled...")
    -- 1. Check if the physical action is possible (tools, location, etc.)
    if not part:getInventoryItem() then
        --DebugLog.log("Part " .. part:getId() .. " has no item installed, cannot uninstall.")
        return false
    end
    if not part:getVehicle():canUninstallPart(player, part) then
        --DebugLog.log("Part " .. part:getId() .. " cannot be uninstalled due to physical constraints.")
        return false
    end
    if BAM.IsPartInaccessible(part) then
        --DebugLog.log("Part " .. part:getId() .. " is marked as inaccessible, cannot uninstall.")
        return false
    end

    -- 2. Get part success chance
    local successChance = BAM.GetPartSuccessChance(player, part, "uninstall")
    if successChance < BAM.GetOptionMinPartSuccessChance() then
        --DebugLog.log("Part " .. part:getId() .. " has a success chance of " .. tostring(successChance) .. "%, which is below the minimum threshold.")
        return false
    end

    -- 3. Check for smashed cars, their front windows are inaccessible
    if part:getId():find("WindowFront") or part:getId():find("Seat") then
        local scriptName = vehicle:getScript():getName()
        --DebugLog.log("-> Vehicle script name: " .. scriptName)
        if string.find(scriptName, "Burnt") or string.find(scriptName, "Smashed") then
            --DebugLog.log("-> Vehicle is burnt or smashed, cannot uninstall " .. part:getId())
            return false
        end
    end

    -- 4. Check if the player is eligible for XP for this part (Cooldown check)
    -- Key format: PartID + VehicleID + "1" (1 is for Uninstall)
    if not BAM.CanGainXP(player, vehicle, part, 1) then
        --DebugLog.log("Player cannot gain XP for uninstalling part " .. part:getId() .. " due to cooldown.")
        return false
    end

    return true
end


function BAM.PartCanBeInstalled(player, vehicle, part)
    -- 1. Check if the physical action is possible (tools, location, etc.)
    if part:getInventoryItem() ~= nil then
        --DebugLog.log("Part " .. part:getId() .. " already has an item installed, cannot install.")
        return nil
    end
    if not part:getVehicle():canInstallPart(player, part) then
        --DebugLog.log("Part " .. part:getId() .. " cannot be installed due to physical constraints.")
        return nil
    end
    if BAM.IsPartInaccessible(part) then
        --DebugLog.log("Part " .. part:getId() .. " is marked as inaccessible, cannot install.")
        return nil
    end

    -- 2. Get part success chance
    local successChance = BAM.GetPartSuccessChance(player, part, "install")
    if successChance < BAM.GetOptionMinPartSuccessChance() then
        --DebugLog.log("Part " .. part:getId() .. " has a success chance of " .. tostring(successChance) .. "%, which is below the minimum threshold.")
        return nil
    end

    -- 3. Check if the player has the required part in inventory or on ground
    local item = BAM.GetAnyItemOnPlayerThatMatchesThatPart(player, part)
    --local item = BAM.GetBestItemForPart(player, part)
    if not item then
        --DebugLog.log("Player does not have required item for installing part " .. part:getId() .. ".")
        return nil
    end

    return item
end


----------------------------------------
-- TOOL CHECKS
----------------------------------------


--- Returns the two lookup tables the game itself uses to resolve tool requirements.
-- These cover everything the player can reach (inventory, bags and nearby containers/ground),
-- keyed by full item type and by item tag.
-- Building them is not cheap, so pass the results along instead of calling this per part.
-- @param player IsoPlayer
-- @return table typeToItem, table tagToItem
function BAM.GetReachableItems(player)
    local typeToItem, tagToItem = VehicleUtils.getItems(player:getPlayerNum())
    return typeToItem or {}, tagToItem or {}
end


--- Checks whether the player has the tools a single part needs for the given action.
-- This is the tool half of Vehicles.UninstallTest/InstallTest, without the requireInstalled /
-- requireUninstalled checks, so it stays true for parts that are currently only blocked by
-- another part still being in the way.
-- @param player IsoPlayer
-- @param part VehiclePart
-- @param actionType string  "install" or "uninstall"
-- @param typeToItem table|nil  From BAM.GetReachableItems, built on demand when omitted
-- @param tagToItem table|nil   From BAM.GetReachableItems
-- @return boolean
function BAM.PlayerHasToolsForPart(player, part, actionType, typeToItem, tagToItem)
    if ISVehicleMechanics.cheat then return true end

    -- If the game ever drops this function, assume the player has everything rather than
    -- greying out buttons that would actually work
    if not VehicleUtils.testItems then return true end

    local keyvalues = part:getTable(actionType)
    if not keyvalues then return false end
    if not part:getItemType() or part:getItemType():isEmpty() then return false end
    if not keyvalues.items then return true end  -- Part needs no tools at all

    if not typeToItem then
        typeToItem, tagToItem = BAM.GetReachableItems(player)
    end

    -- Let the game answer this, so we always accept exactly the items it would accept
    return VehicleUtils.testItems(player, keyvalues.items, typeToItem, tagToItem) == true
end


--- Checks whether the player has the tools to actually get a part off the vehicle.
-- Some parts can only be uninstalled once other parts are removed first, and those parts can
-- need different tools, so the whole chain has to be covered before the part is reachable.
-- @param player IsoPlayer
-- @param part VehiclePart
-- @param typeToItem table|nil  From BAM.GetReachableItems, built on demand when omitted
-- @param tagToItem table|nil   From BAM.GetReachableItems
-- @return boolean
function BAM.PlayerHasToolsToUninstallPart(player, part, typeToItem, tagToItem)
    if not typeToItem then
        typeToItem, tagToItem = BAM.GetReachableItems(player)
    end

    if not BAM.PlayerHasToolsForPart(player, part, "uninstall", typeToItem, tagToItem) then
        return false
    end

    -- Parts that are already uninstalled are not in the way anymore, so they need no tools
    for _, requiredPart in ipairs(BAM.GetRequiredUninstalledPartsForPart(part)) do
        if requiredPart:getInventoryItem() and
                not BAM.PlayerHasToolsForPart(player, requiredPart, "uninstall", typeToItem, tagToItem) then
            return false
        end
    end

    return true
end


--- Checks whether the player has the tools for at least one part of the vehicle, meaning any
-- automated work is possible at all. Used to grey out the Train Mechanics button.
-- @param player IsoPlayer
-- @param vehicle BaseVehicle
-- @return boolean
function BAM.HasToolsForAnyPart(player, vehicle)
    local typeToItem, tagToItem = BAM.GetReachableItems(player)

    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)

        if part:getInventoryItem() then
            if BAM.PlayerHasToolsToUninstallPart(player, part, typeToItem, tagToItem) then
                return true
            end
        elseif BAM.PlayerHasToolsForPart(player, part, "install", typeToItem, tagToItem) and
                BAM.GetAnyItemOnPlayerThatMatchesThatPart(player, part, typeToItem) then
            return true
        end
    end

    return false
end


----------------------------------------
-- CACHED SORTING DATA
----------------------------------------
local cachedRankLookup = nil
local function buildRankLookup()
    -- Define the train order
    -- Grouped by location on vehicle, and then by required tool to minimize tool switching
    local orderList = {
        -- Front
        "Radio", "Battery", "HeadlightLeft", "HeadlightRight", "Windshield", "EngineDoor",
        -- Front Left
        "BrakeFrontLeft", "SuspensionFrontLeft", "TireFrontLeft",
        -- Doors Left
        "SeatFrontLeft", "DoorFrontLeft", "WindowFrontLeft",
        "SeatMiddleLeft", "DoorMiddleLeft", "WindowMiddleLeft",
        "SeatRearLeft", "DoorRearLeft", "WindowRearLeft",
        -- Rear Left
        "BrakeRearLeft", "SuspensionRearLeft", "TireRearLeft",
        -- Rear
        "GasTank", "WindshieldRear", "HeadlightRearLeft", "HeadlightRearRight", "Muffler", "TrunkDoor", "DoorRear",
        -- Rear Right
        "BrakeRearRight", "SuspensionRearRight", "TireRearRight",
        -- Doors Right
        "SeatRearRight", "DoorRearRight", "WindowRearRight",
        "SeatMiddleRight", "DoorMiddleRight", "WindowMiddleRight",
        "SeatFrontRight", "DoorFrontRight", "WindowFrontRight",
        -- Front Right
        "BrakeFrontRight", "SuspensionFrontRight", "TireFrontRight",
        -- Impossible ones:
        "GloveBox", "Heater", "Engine", "TruckBed", "TruckBedOpen", "PassengerCompartment",
        "TrailerAnimalFood", "TrailerAnimalEggs",
    }

    -- Create a "Rank Map" for fast lookup
    -- This turns the list into: { ["Radio"] = 1, ["Battery"] = 2, ... }
    local lookup = {}
    for index, id in ipairs(orderList) do
        lookup[id] = index
    end
    return lookup
end


function BAM.SortParts(parts)
    -- Build cache only once
    if not cachedRankLookup then
        cachedRankLookup = buildRankLookup()
    end

    -- Sort the actual 'parts' table using the Rank Map
    table.sort(parts, function(a, b)
        local idA = a:getId()
        local idB = b:getId()

        -- Get the rank from our table.
        -- If an ID isn't in your list, we give it rank 999 (puts it at the very bottom)
        local rankA = cachedRankLookup[idA] or 999
        local rankB = cachedRankLookup[idB] or 999

        return rankA < rankB
    end)

    --DebugLog.log("Sorted parts order:")
    --for i, part in ipairs(parts) do
    --    DebugLog.log(i .. " - " .. part:getId())
    --end

    return parts
end


function BAM.GetAnyItemOnPlayerThatMatchesThatPart(player, part, typeToItem)
    if not part:getItemType() or part:getItemType():isEmpty() then return nil end

    local playerItems = typeToItem or VehicleUtils.getItems(player:getPlayerNum())

    -- Get all possible items on and around the player that can be installed
    for i = 0, part:getItemType():size() - 1 do
        local requiredItemType = part:getItemType():get(i)
        local matchingPlayerItems = playerItems[requiredItemType]

        if matchingPlayerItems and #matchingPlayerItems > 0 then
            for _, item in ipairs(matchingPlayerItems) do
                return item  -- Return the first matching item
            end
        end
    end
    return nil
end


function BAM.GetBestItemForPart(player, part)
    if not part:getItemType() or part:getItemType():isEmpty() then return nil end

    local bestItem = nil
    local bestCondition = -1

    -- Helper to check an item
    local function checkItem(item)
        -- Verify type match
        local types = part:getItemType()
        local typeMatch = false
        for i = 0, types:size() - 1 do
            if item:getType() == types:get(i) or item:getFullType() == types:get(i) then
                typeMatch = true
                break
            end
        end

        if typeMatch and not item:isBroken() then
            -- We want the highest condition
            if item:getCondition() > bestCondition then
                bestCondition = item:getCondition()
                bestItem = item
            end
        end
    end

    -- 1. Check Inventory
    local playerItems = player:getInventory():getItems()
    for i = 0, playerItems:size() - 1 do
        checkItem(playerItems:get(i))
    end

    -- 2. Check Ground (Player's current square and adjacent squares)
    local pSq = player:getSquare()
    if pSq then
        local cell = getCell()
        for x = -1, 1 do
            for y = -1, 1 do
                local sq = cell:getGridSquare(pSq:getX() + x, pSq:getY() + y, pSq:getZ())
                if sq then
                    local worldObjects = sq:getWorldObjects()
                    for i = 0, worldObjects:size() - 1 do
                        local obj = worldObjects:get(i)
                        local item = obj:getItem()
                        if item then
                            checkItem(item)
                        end
                    end
                end
            end
        end
    end

    return bestItem
end


function BAM.DropBrokenItems(player)
    local inventory = player:getInventory()
    local items = inventory:getItems()
    local itemsToDrop = {}

    -- 1. Identify items to drop
    for i = 0, items:size() - 1 do
        local item = items:get(i)
        if item:isBroken() and not item:isFavorite() and not item:isEquipped() then
            table.insert(itemsToDrop, item)
        end
    end

    BAM.DropItems(player, itemsToDrop)
end


function BAM.DropItems(player, items)
    if not items or #items == 0 then
        return
    end

    -- Get the "Floor" Container
    -- In Zomboid, the floor is a virtual container managed by ISInventoryPage
    local floorContainer = ISInventoryPage.floorContainer[player:getPlayerNum() + 1]

    if not floorContainer then
        --DebugLog.log("Error: Could not find floor container!")
        return
    end

    -- 3. Queue the Transfer Actions
    for _, item in ipairs(items) do
        DebugLog.log("Dropping item: " .. item:getName())
        local action = ISInventoryTransferAction:new(player, item, item:getContainer(), floorContainer, 10)  -- 10 is Time in ticks (10 is very fast)
        ISTimedActionQueue.add(action)
    end
end


function BAM.PickupItems(player, items)
    if not player or not items or #items == 0 then
        return
    end

    local playerInventory = player:getInventory()
    if not playerInventory then
        return
    end

    local startingSquare = player:getSquare()
    local pickedUpAny = false

    local startX = startingSquare and startingSquare:getX() or player:getX()
    local startY = startingSquare and startingSquare:getY() or player:getY()

    DebugLog.log("Picking back up items...")
    for _, item in ipairs(items) do
        local srcContainer = item:getContainer()
        local worldItem = item:getWorldItem()
        local itemSquare = worldItem and worldItem:getSquare()

        if worldItem == nil then
            DebugLog.log("WorldItem was nil, searching on floor for item: " .. item:getName())
            local foundWorldItem, foundSquare = BAM.FindWorldItem(item, startingSquare, 6)

            if foundWorldItem then
                item = foundWorldItem
                itemSquare = foundSquare
                worldItem = foundWorldItem
                srcContainer = item:getContainer() or srcContainer
            end
        end

        local isOnFloor = (srcContainer and srcContainer:getType() == "floor") or (worldItem ~= nil)

        DebugLog.log("Checking item: " .. item:getName() .. " | isOnFloor: " .. tostring(isOnFloor) .. " | getWorldItem: " .. tostring(worldItem))

        if isOnFloor then
            DebugLog.log("Picking up item from floor: " .. item:getName())
            local dist = 0
            if itemSquare then
                local dx = itemSquare:getX() - startX
                local dy = itemSquare:getY() - startY
                dist = math.sqrt(dx * dx + dy * dy)
            end

            if dist <= 6 then
                pickedUpAny = true
                if itemSquare then
                    ISTimedActionQueue.add(ISWalkToTimedAction:new(player, itemSquare))
                end

                local action = ISInventoryTransferAction:new(
                    player,
                    item,
                    srcContainer,
                    playerInventory,
                    10 -- Time in ticks (10 is very fast)
                )
                DebugLog.log("Picking up item: " .. item:getName())
                ISTimedActionQueue.add(action)
            else
                DebugLog.log("Item too far to pick up: " .. item:getName())
            end
        end
    end

    if pickedUpAny and startingSquare then
        ISTimedActionQueue.add(ISWalkToTimedAction:new(player, startingSquare))
    end
    return pickedUpAny
end



function BAM.FindWorldItem(item, startingSquare, distance)
    local startX = startingSquare:getX()
    local startY = startingSquare:getY()
    local startZ = startingSquare:getZ()

    local worldItem = nil
    local itemSquare = nil

    -- Scan a X*X grid around the player to find where the dropped item ended up
    for x = startX - distance, startX + distance do
        for y = startY - distance, startY + distance do
            local sq = getCell():getGridSquare(x, y, startZ)
            if sq then
                local floorObjects = sq:getWorldObjects()
                for i = 0, floorObjects:size() - 1 do
                    local worldObj = floorObjects:get(i)
                    local floorItem = worldObj:getItem()

                    -- Match the floor item to our item using the unique ID
                    if floorItem and floorItem:getID() == item:getID() then
                        worldItem = floorItem
                        itemSquare = sq
                        break
                    end
                end
            end
            if worldItem ~= nil then break end
        end
        if worldItem ~= nil then break end
    end
    return worldItem, itemSquare
end


function BAM.GetPartSuccessChance(player, part, actionType)
    local successChance = 0
    local keyvalues = part:getTable(actionType)
    if keyvalues then
        local perks = keyvalues.skills
        local perksTable = VehicleUtils.getPerksTableForChr(perks, player)
        successChance, _ = VehicleUtils.calculateInstallationSuccess(perks, player, perksTable)
    end
    return successChance
end


--- Checks if adding an item would exceed the player's hard carry limit.
-- @param player The IsoPlayer object (e.g., getPlayer())
-- @param item The IsoWorldInventoryObject to check
-- @return boolean true if it would exceed the limit, false otherwise
function BAM.WouldExceedWeightLimit(player, item)
    if not player or not item then return false end
    --DebugLog.log("Checking if adding item " .. item:getName() .. " would exceed weight limit...")

    -- 1. Check if the item is currently in the players inventory
    -- If it is already in the main inventory, we return false because it won't add any weight
    local inventory = player:getInventory()
    if inventory:contains(item) then
        --DebugLog.log("Item is already in inventory, so it will fit.")
        return false
    end

    -- 2. Calculate weight after adding the item
    local itemWeight = item:getUnequippedWeight()
    local currentWeight = inventory:getCapacityWeight() -- Current weight in main inventory
    local limitWeight = inventory:getCapacity()
    --DebugLog.log("Current inventory weight:  " .. tostring(currentWeight) .. " / " .. tostring(limitWeight))
    --DebugLog.log("Expected inventory weight: " .. tostring(currentWeight + itemWeight) .. " / " .. tostring(limitWeight))

    return (currentWeight + itemWeight) > limitWeight
end


--- Drops items from the player's inventory until the given item would fit within the capacity limit.
-- @param player The IsoPlayer object (e.g., getPlayer())
-- @param item The IsoWorldInventoryObject to check
-- @return table A list of dropped items, for later pickup
function BAM.DropItemsUntilGivenItemFits(player, item)
    local droppedItems = {}
    if not player or not item then return droppedItems end

    -- If the item is already in the inventory, we don't need to drop anything because it won't add any weight
    local inventory = player:getInventory()
    if inventory:contains(item) then
        return droppedItems
    end

    local itemWeight = item:getUnequippedWeight()
    local currentWeight = inventory:getCapacityWeight()
    local limitWeight = inventory:getCapacity()


    -- If the item would already fit without dropping anything, we can skip the dropping process
    if (currentWeight + itemWeight) <= limitWeight then
        return droppedItems
    end

    DebugLog.log("Item " .. item:getName() .. " would exceed weight limit (" .. tostring(limitWeight) .. ") if picked up. Dropping some items..")

    local items = inventory:getItems()
    local droppableItems = {}

    -- Collect a list of all items in the inventory that are not equipped, not favorite, and not the item we want to pick up
    for i = 0, items:size() - 1 do
        local invItem = items:get(i)
        if not invItem:isEquipped() and not invItem:isFavorite() and invItem ~= item and not string.find(invItem:getFullType(), "KeyRing") then
            table.insert(droppableItems, invItem)
        end
    end

    -- Sort these items by weight
    table.sort(droppableItems, function(a, b)
        return a:getUnequippedWeight() > b:getUnequippedWeight()
    end)

    -- Mark the heaviest items for dropping until we have enough weight freed up to pick up the new item
    for _, invItem in ipairs(droppableItems) do
        DebugLog.log("Dropping item: " .. invItem:getName() .. " (getUnequippedWeight: " .. tostring(invItem:getUnequippedWeight()) .. ", current weight ".. tostring(currentWeight) .. " / " .. tostring(limitWeight) .. ")")
        table.insert(droppedItems, invItem)
        currentWeight = currentWeight - invItem:getUnequippedWeight()

        if (currentWeight + itemWeight) <= limitWeight then
            break
        end
    end

    -- Then drop them
    BAM.DropItems(player, droppedItems)

    return droppedItems
end


function BAM.WorkOnNextPartInXTicks(ticks)
    BAM.WorkDelayTimer = ticks
end


function BAM.CheckGameSpeedInXTicks(ticks)
    BAM.GameSpeedCheckTimer = ticks
end


function BAM.SaveGameSpeed()
    BAM.PrevGameSpeed = getGameSpeed()
    BAM.PrevTimeMultiplier = getGameTime():getTrueMultiplier()
    --DebugLog.log("SAVED GAMESPEED: " .. BAM.PrevGameSpeed .. " - " .. BAM.PrevTimeMultiplier)
end


function BAM.RestoreGameSpeed()
    -- Check if the game speed got randomly reset by the game and restore it in that case
    -- Currently this can interfere with the player manually changing the game speed while training
    if getGameSpeed() < BAM.PrevGameSpeed and getGameSpeed() == 1 then
        setGameSpeed(BAM.PrevGameSpeed)
        getGameTime():setMultiplier(BAM.PrevTimeMultiplier)
        DebugLog.log("Reset gamespeed back to: " .. getGameSpeed() .. " | " .. getGameTime():getMultiplier() .. " | " .. getGameTime():getTrueMultiplier())
    end
end


----------------------------------------
-- CACHED GAME VERSION
----------------------------------------
local cachedMajor, cachedMinor, cachedPatch = nil, nil, nil


function BAM.GetGameVersion()
    if cachedMajor then
        return cachedMajor, cachedMinor, cachedPatch
    end

    -- getCore():getGameVersion()) doesn't return the path, so we extract it from the full version string
    local ver_str = getCore():getVersion()                            -- Returns string like: "42.13.1 1267173a2044ba62aa3d0a0e9899b15e9057de5c 2025-12-18 10:34:47 (ZB)"
    local major, minor, patch = ver_str:match("^(%d+)%.(%d+)%.(%d+)") -- Extract major, minor, patch numbers, here "42", "13", "1"
    cachedMajor = tonumber(major)
    cachedMinor = tonumber(minor)
    cachedPatch = tonumber(patch)
    --DebugLog.log("Detected game version: " .. cachedMajor .. "." .. cachedMinor .. "." .. cachedPatch)

    return cachedMajor, cachedMinor, cachedPatch
end


function BAM.GameVersionNewerThanOrEqual(majorReq, minorReq, patchReq)
    local major, minor, patch = BAM.GetGameVersion()

    if major > majorReq then
        return true
    elseif major == majorReq then
        if minor > minorReq then
            return true
        elseif minor == minorReq then
            return patch >= patchReq
        end
    end

    return false
end


function BAM.GetRequiredInstalledPartsForPart(part)
    local requiredParts = {}
    local vehicle = part:getVehicle()
    local keyvalues = part:getTable("install")
    if keyvalues and keyvalues.requireInstalled then
        local split = keyvalues.requireInstalled:split(";")
        for _, partId in ipairs(split) do
            local requiredPart = vehicle:getPartById(partId)
            if requiredPart then
                table.insert(requiredParts, requiredPart)
            end
        end
    end
    return requiredParts
end


function BAM.GetRequiredUninstalledPartsForPart(part, visited)
    visited = visited or {}
    local id = part:getId()
    if visited[id] then
        return {}
    end
    visited[id] = true

    local requiredParts = {}
    local vehicle = part:getVehicle()
    local keyvalues = part:getTable("uninstall")
    --DebugLog.log("Checking required uninstalled parts for part " .. id)
    if keyvalues and keyvalues.requireUninstalled then
        --DebugLog.log(keyvalues.requireUninstalled)
        local split = keyvalues.requireUninstalled:split(";")
        for _, partId in ipairs(split) do
            local requiredPart = vehicle:getPartById(partId)
            if requiredPart then
                --DebugLog.log("Found part: " .. requiredPart:getId())
                local requiredPartsTmp = BAM.GetRequiredUninstalledPartsForPart(requiredPart, visited)
                for _, requiredPartTmp in ipairs(requiredPartsTmp) do
                    --DebugLog.log("Found required part: " .. requiredPartTmp:getId())
                    table.insert(requiredParts, requiredPartTmp)
                end
                table.insert(requiredParts, requiredPart)
            end
        end
    end
    return requiredParts
end


--- DEBUG ONLY: Recursively prints the contents of a table to the console
-- @param node The table to print
-- @param name (Optional) The name of the table for the log output
-- @param indent (Optional) Used internally for formatting nested tables
function BAM.PrintTable(node, name, indent)
    indent = indent or ""
    name = name or "Table"

    -- If it's not a table, just print the value directly
    if type(node) ~= "table" then
        DebugLog.log(indent .. name .. " = " .. tostring(node))
        return
    end

    DebugLog.log(indent .. name .. " = {")

    for k, v in pairs(node) do
        local keyString = tostring(k)

        -- If the value is another table, call this function again recursively!
        if type(v) == "table" then
            BAM.PrintTable(v, keyString, indent .. "  ")
        else
            -- Otherwise, just print the key and the value
            -- We use tostring(v) so booleans and numbers don't crash the log
            DebugLog.log(indent .. "  " .. keyString .. " = " .. tostring(v))
        end
    end

    DebugLog.log(indent .. "}")
end


function BAM.SetPartInaccessible(part)
    --- Marks a part as inaccessible
    if not part or not part:getId() then return end

    local partAccessibilityLevel = BAM.InaccessibleParts[part:getId()]
    if partAccessibilityLevel == nil then
        BAM.InaccessibleParts[part:getId()] = 1
    else
         BAM.InaccessibleParts[part:getId()] = partAccessibilityLevel + 1
    end
end


function BAM.IsPartInaccessible(part)
    --- Checks if a part is marked as inaccessible. It is marked as inaccessible if working on the part fails 2 times
    if not part or not part:getId() then return false end

    local partAccessibilityLevel = BAM.InaccessibleParts[part:getId()]
    return partAccessibilityLevel ~= nil and partAccessibilityLevel >= 2
end
