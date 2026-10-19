BAM = BAM or {}

-- ########################
--    Uninstall Buttons
-- ########################


-- Each category maps to an explicit list of part IDs.
-- "Everything" uses nil to match all parts.
-- Translation keys map to vanilla game translation strings where possible
BAM.UninstallCategories = {
    {
        key = "everything",
        label = "UI_BAM_Uninstall_Everything",
        ids = nil,  -- nil means match all parts
    },
    {
        key = "tires",
        label = "IGUI_VehiclePartCattire",
        ids = { "TireFrontLeft", "TireFrontRight", "TireRearLeft", "TireRearRight" },
    },
    {
        key = "doors",
        label = "IGUI_VehiclePartCatdoor",
        ids = { "DoorFrontLeft", "DoorFrontRight", "DoorMiddleLeft", "DoorMiddleRight", "DoorRearLeft", "DoorRearRight", "DoorRear" },
    },
    --{
    --    key = "windows",
    --    label = "IGUI_VehiclePartWindow",
    --    ids = { "WindowFrontLeft", "WindowFrontRight", "WindowMiddleLeft", "WindowMiddleRight", "WindowRearLeft", "WindowRearRight", "Windshield", "WindshieldRear" },
    --},
    {
        key = "seats",
        label = "IGUI_VehiclePartCatseat",
        ids = { "SeatFrontLeft", "SeatFrontRight", "SeatMiddleLeft", "SeatMiddleRight", "SeatRearLeft", "SeatRearRight" },
    },
    {
        key = "lights",
        label = "IGUI_VehiclePartCatlights",
        ids = { "HeadlightLeft", "HeadlightRight", "HeadlightRearLeft", "HeadlightRearRight" },
    },
    {
        key = "brakes",
        label = "IGUI_VehiclePartCatbrakes",
        ids = { "BrakeFrontLeft", "BrakeFrontRight", "BrakeRearLeft", "BrakeRearRight" },
    },
    {
        key = "suspension",
        label = "IGUI_VehiclePartCatsuspension",
        ids = { "SuspensionFrontLeft", "SuspensionFrontRight", "SuspensionRearLeft", "SuspensionRearRight" },
    },
}

function BAM.CreateUninstallAllMenu(self, context, player, vehicle)
    if not context then return end

    -- Build a parent option: "Uninstall ..."
    local parentOption = context:addOption(getText("UI_BAM_Uninstall_Title"), nil)
    parentOption.iconTexture = getTexture("Item_Wrench")

    -- Create the submenu
    local subMenu = context:getNew(context)
    context:addSubMenu(parentOption, subMenu)

    local anyEnabled = false

    -- Built once and shared by every category, since collecting the reachable items is expensive
    local typeToItem, tagToItem = BAM.GetReachableItems(player)

    for _, category in ipairs(BAM.UninstallCategories) do
        --DebugLog.log("Creating uninstall option for category: " .. category.key)
        -- Build a set-like table from the category ids list (or nil for "everything")
        local categoryIds
        if category.ids then
            categoryIds = {}
            for _, id in ipairs(category.ids) do
                categoryIds[id] = true
            end
        end

        -- Check how many parts can actually be uninstalled in this category.
        -- Parts the player has no tools for don't count, otherwise the button would promise
        -- work that the batch uninstall can't do.
        local parts = BAM.GetUninstallablePartsByCategory(player, vehicle, categoryIds)
        local count = 0
        local counted = {}
        for _, part in ipairs(parts) do
            -- The list also contains parts that are only in the way, and can hold duplicates
            local partId = part:getId()
            if not counted[partId] and (categoryIds == nil or categoryIds[partId]) and
                    BAM.PlayerHasToolsToUninstallPart(player, part, typeToItem, tagToItem) then
                counted[partId] = true
                count = count + 1
            end
        end

        -- Build the label: "All Tires (3)" or "Everything (12)"
        local label = getText(category.label or category.key)
        if category.key ~= "everything" then
            label = getText("UI_BAM_Uninstall_All", label)
            label = label .. " (" .. tostring(count) .. ")"
        end

        local option = subMenu:addOption(label, self, BAM.UninstallCategory, player, vehicle, categoryIds)

        option.notAvailable = count == 0
        if not option.notAvailable then
            anyEnabled = true
        end

        -- The tooltip is still shown while greyed out, so it can explain what is missing
        local optionTooltip = ISToolTip:new()
        optionTooltip:initialise()
        optionTooltip:setVisible(true)
        optionTooltip.description = BAM.GenerateUninstallDescription(player, vehicle, parts, category.key, count > 0)
        option.toolTip = optionTooltip
    end

    -- If no category has any uninstallable parts, grey out the parent option too
    if not anyEnabled then
        parentOption.notAvailable = true
    end
end


-- ### Button Design ###
-- @param hasTools boolean|nil  False when the player can't uninstall any part of this category
function BAM.GenerateUninstallDescription(player, vehicle, parts, categoryKey, hasTools)
    local newline = " <LINE>"
    local msg = ""

    -- Explain the greyed out button right at the top
    if hasTools == false then
        msg = "<RED>" .. getText("UI_BAM_button_desc.no_tools") .. newline .. newline .. "<RGB:1,1,1>"
    end

    msg = msg .. getText("UI_BAM_button_desc.needs") .. ":"

    local requiredTools = BAM.GetRequiredToolsForParts(parts, "uninstall")

    -- 1. Figure out which tool categories are actually required
    local needsScrewdriver = false
    local needsWrench = false
    local needsLugWrench = false
    local needsJack = false

    -- We loop through the required tools dictionary and check the ID/Tag
    for toolID, _ in pairs(requiredTools) do
        local lowerID = string.lower(toolID)

        -- string.find makes this bulletproof against both B41 Items and B42 Tags
        if string.find(lowerID, "screwdriver") then
            needsScrewdriver = true
        elseif string.find(lowerID, "lug") then
            needsLugWrench = true
        elseif string.find(lowerID, "wrench") then
            needsWrench = true
        elseif string.find(lowerID, "jack") then
            needsJack = true
        end
    end

    -- 2. Inventory Check (Optimized to only search for what we need!)
    local hasScrewdriver = false
    local hasWrench = false
    local hasLugWrench = false
    local hasJack = false

    if BAM.GameVersionNewerThanOrEqual(42, 13, 0) then
        if needsScrewdriver then hasScrewdriver = player:getInventory():getFirstTagRecurse(ItemTag.SCREWDRIVER) end
        if needsWrench then hasWrench = player:getInventory():getFirstTagRecurse(ItemTag.WRENCH) end
        if needsLugWrench then hasLugWrench = player:getInventory():getFirstTagRecurse(ItemTag.LUG_WRENCH) end
    else
        if needsScrewdriver then hasScrewdriver = player:getInventory():getFirstTagRecurse("Screwdriver") end
        if needsWrench then hasWrench = player:getInventory():getFirstTagRecurse("Wrench") end
        if needsLugWrench then hasLugWrench = player:getInventory():getFirstTagRecurse("LugWrench") end
    end
    if needsJack then hasJack = player:getInventory():getFirstTypeRecurse("Jack") end

    -- 3. Build the Tooltip Strings Dynamically
    local nameScrewdriver = getScriptManager():getItem("Base.Screwdriver"):getDisplayName()
    local nameMultitool = getScriptManager():getItem("Base.Multitool"):getDisplayName()
    local nameHandiknife = getScriptManager():getItem("Base.Handiknife"):getDisplayName()
    local nameWrench = getScriptManager():getItem("Base.Wrench"):getDisplayName()
    local nameRatchetWrench = getScriptManager():getItem("Base.Ratchet"):getDisplayName()
    local nameLugWrench = getScriptManager():getItem("Base.LugWrench"):getDisplayName()
    local nameTireIron = getScriptManager():getItem("Base.TireIron"):getDisplayName()
    local nameJack = getScriptManager():getItem("Base.Jack"):getDisplayName()

    local color
    if needsScrewdriver then
        color = hasScrewdriver and "<GREEN>" or "<RED>"
        msg = msg .. newline .. color .. " - " .. nameScrewdriver .. " / " .. nameMultitool .. " / " .. nameHandiknife
    end
    if needsWrench then
        color = hasWrench and "<GREEN>" or "<RED>"
        msg = msg .. newline .. color .. " - " .. nameWrench .. " / " .. nameRatchetWrench
    end
    if needsLugWrench then
        color = hasLugWrench and "<GREEN>" or "<RED>"
        msg = msg .. newline .. color .. " - " .. nameLugWrench .. " / " .. nameTireIron
    end
    if needsJack then
        color = hasJack and "<GREEN>" or "<RED>"
        msg = msg .. newline .. color .. " - " .. nameJack
    end

    -- 4. Recipe check
    local requiredRecipes = BAM.GetRequiredRecipes(vehicle, parts)

    -- Only add the "Recipes Required:" header if there are actually recipes needed
    local hasRecipes = false
    for _ in pairs(requiredRecipes) do hasRecipes = true; break end

    if hasRecipes then
        msg = msg .. newline
        msg = msg .. newline .. "<RGB:1,1,1>" .. getText("UI_BAM_button_desc.recipes_required") .. ":"
        for recipe, _ in pairs(requiredRecipes) do
            local recipeDisplayName = getText("Tooltip_vehicle_requireRecipe", getRecipeDisplayName(recipe))
            local knowsRecipe = player:isRecipeKnown(recipe, true)
            color = knowsRecipe and "<GREEN>" or "<RED>"
            msg = msg .. newline .. color .. " - " .. recipeDisplayName
        end
    end

    -- Car Key check
    if not BAM.PlayerHasCarAccess(player, vehicle) then
        msg = msg .. newline
        msg = msg .. newline .. "<RGB:1,1,1>" .. getText("UI_BAM_button_desc.no_car_access")
        msg = msg .. newline .. "<ORANGE> - " .. getText("UI_BAM_button_desc.parts_inaccessible")
    end

    -- Notes
    if categoryKey == "everything" or categoryKey == "seats" then
        msg = msg .. newline
        msg = msg .. newline .. "<RGB:1,1,1>" .. getText("UI_BAM_button_desc.empty_seats")
    end

    return msg
end


-- ########################
--      Uninstall Logic
-- ########################


--- Start batch-uninstalling all parts in a given category, one at a time.
-- Stops any active training first, then works through each matching part sequentially.
-- @param playerOrSelf  When called from the mechanics UI context menu, this is the ISVehicleMechanics 'self'.
-- @param player IsoPlayer
-- @param vehicle BaseVehicle
-- @param categoryIds table|nil  Set of part ID strings, or nil for "Everything"
function BAM.UninstallCategory(playerOrSelf, player, vehicle, categoryIds)
    -- Stop any active training session first
    ISTimedActionQueue.clear(player)
    BAM.StopMechanicsWork(nil)

    local parts = BAM.GetUninstallablePartsByCategory(player, vehicle, categoryIds)
    if #parts == 0 then return end

    DebugLog.log("=================================")
    DebugLog.log("BAM: Starting batch uninstall of " .. #parts .. " parts...")
    BAM.IsCurrentlyBatchUninstalling = true
    BAM.BatchUninstallCategoryIds = categoryIds
    BAM.Vehicle = vehicle
    BAM.workOnNextUninstallPart(player, vehicle)
end


--- Pick and uninstall the next part in the current batch category, one at a time.
-- Skips parts marked as inaccessible. Stops when no more parts remain.
function BAM.workOnNextUninstallPart(player, vehicle)
    -- Safety check
    if not player or not vehicle then
        BAM.StopMechanicsWork(nil)
        return
    end

    -- Distance check
    local distanceToCar = player:DistToSquared(vehicle)
    if distanceToCar > 10 and BAM.LastWorkedPart then
        DebugLog.log("BAM: Player is too far from vehicle (" .. tostring(distanceToCar) .. " tiles). Stopping batch uninstall.")
        BAM.StopMechanicsWork(nil)
        return
    end

    -- Get the next part to uninstall in this category
    DebugLog.log("Deciding on next batch uninstall part...")
    local parts = BAM.GetUninstallablePartsByCategory(player, vehicle, BAM.BatchUninstallCategoryIds)

    -- Use the first part that is valid for uninstall
    for _, part in ipairs(parts) do
        if BAM.PartCanBeBatchUninstalled(player, vehicle, part) then
            DebugLog.log("BAM: Next part to batch uninstall: " .. part:getId())
            BAM.UninstallPart(player, part)
            return
        end
    end

     DebugLog.log("BAM: No more accessible parts to batch uninstall.")
     BAM.StopMechanicsWork(nil)
end


-- ########################
--     Uninstall Utils
-- ########################


--- Returns a list of parts on the vehicle that the player can uninstall, filtered by category.
-- Respects BAM.InaccessibleParts to skip parts that have previously failed during batch uninstall.
-- @param player IsoPlayer
-- @param vehicle BaseVehicle
-- @param categoryIds table|nil  A set-like table { ["TireFrontLeft"]=true, ... } or nil for all parts
-- @return table  List of VehiclePart objects
function BAM.GetUninstallablePartsByCategory(player, vehicle, categoryIds)
    -- Collect all installed car parts into a list for sorting
    local validParts = {}
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        if categoryIds == nil or categoryIds[part:getId()] then
            table.insert(validParts, part)
        end
    end

    local sortedParts = BAM.SortParts(validParts)
    local uninstallableParts = {}

    -- Check each part for uninstall possibility and required uninstalls
    for _, part in ipairs(sortedParts) do
        --DebugLog.log("Checking part" .. part:getId())
        if part:getInventoryItem() then
            local requiredParts = BAM.GetRequiredUninstalledPartsForPart(part)
            for _, p in ipairs(requiredParts) do
                if p:getInventoryItem() then
                    table.insert(uninstallableParts, p)
                end
            end
            table.insert(uninstallableParts, part)
        end
    end
    return uninstallableParts
end


function BAM.PartCanBeBatchUninstalled(player, vehicle, part)
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
    if successChance < 1 then
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

    return true
end


function BAM.GetRequiredToolsForParts(partsList, actionType)
    local requiredTools = {}

    for _, part in ipairs(partsList) do
        local keyvalues = part:getTable(actionType)

        if keyvalues and keyvalues.items then
            local itemsTable = {}
            if type(keyvalues.items) == "string" then
                itemsTable = keyvalues.items:split(";")
            elseif type(keyvalues.items) == "table" then
                itemsTable = keyvalues.items
            end

            for _, toolDef in pairs(itemsTable) do
                -- 1. If it's a rich table, check for TYPE or TAGS
                if type(toolDef) == "table" then

                    --BAM.PrintTable(toolDef, part:getId())

                    if toolDef.type then
                        local toolID = string.gsub(toolDef.type, "%s+", "")
                        if not string.find(toolID, "%.") then toolID = "Base." .. toolID end
                        -- Store it and mark that it is NOT a tag
                        requiredTools[toolID] = { isTag = false }

                    elseif toolDef.tags then
                        local tagID = string.gsub(toolDef.tags, "%s+", "")
                        -- Store it and mark that it IS a tag
                        requiredTools[tagID] = { isTag = true }
                    end

                -- 2. Fallback for raw strings
                elseif type(toolDef) == "string" then
                    local toolID = string.gsub(toolDef:split("=")[1], "%s+", "")
                    if not string.find(toolID, "%.") then toolID = "Base." .. toolID end
                    requiredTools[toolID] = { isTag = false }
                end
            end
        end
    end

    -- Convert our dictionary into a neat table containing the Display Names
    local toolsList = {}
    local scriptManager = getScriptManager()

    for id, info in pairs(requiredTools) do
        if info.isTag then
            -- Format the tag so it looks good in the UI
            -- e.g., "base:wrench" -> "wrench"
            local cleanTag = id
            if string.find(cleanTag, ":") then
                cleanTag = cleanTag:split(":")[2]
            end

            -- Capitalize the first letter (wrench -> Wrench)
            cleanTag = cleanTag:gsub("^%l", string.upper)
            -- Replace underscores with spaces just in case (lug_wrench -> Lug Wrench)
            cleanTag = cleanTag:gsub("_", " ")

            -- Add an indicator so the player knows it's a category, not a specific item
            toolsList[id] = cleanTag .. " (Any)"
        else
            -- Process standard items exactly like before
            local itemScript = scriptManager:getItem(id)
            if itemScript then
                toolsList[id] = itemScript:getDisplayName()
            else
                toolsList[id] = id
            end
        end
        --DebugLog.log("-> Required tool: " .. toolsList[id] .. " (ID: " .. id .. ")")
    end

    return toolsList
end

