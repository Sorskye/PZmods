BAM = BAM or {}

BAM.InstallCategories = {
    {
        key = "everything",
        label = "UI_BAM_Uninstall_Everything",
        ids = nil, -- nil means match all parts
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

function BAM.CreateInstallAllMenu(self, context, player, vehicle)
    if not context then return end

    -- Parent Option "Install ..."
    local parentOption = context:addOption(getText("UI_BAM_Install_Title"), nil)
    parentOption.iconTexture = getTexture("Item_Wrench")

    local subMenu = context:getNew(context)
    context:addSubMenu(parentOption, subMenu)

    local anyEnabled = false

    for _, category in ipairs(BAM.InstallCategories) do
        local categoryIds
        if category.ids then
            categoryIds = {}
            for _, id in ipairs(category.ids) do
                categoryIds[id] = true
            end
        end

        local parts = BAM.GetInstallablePartsByCategory(player, vehicle, categoryIds)
        local count = #parts

        local label = getText(category.label or category.key)
        if category.key ~= "everything" then
            label = getText("UI_BAM_Uninstall_All", label)
            label = label .. " (" .. tostring(count) .. ")"
        end

        local option = subMenu:addOption(label, self, BAM.InstallCategory, player, vehicle, categoryIds)

        -- GetInstallablePartsByCategory already filters by canInstallPart, so a count of 0
        -- means the player is missing the tools, the parts or the skill for all of them
        option.notAvailable = count == 0
        if not option.notAvailable then
            anyEnabled = true
        end

        -- The tooltip is still shown while greyed out, so it can explain what is missing
        local optionTooltip = ISToolTip:new()
        optionTooltip:initialise()
        optionTooltip:setVisible(true)
        optionTooltip.description = BAM.GenerateInstallDescription(player, vehicle, parts, count > 0)
        option.toolTip = optionTooltip
    end

    if not anyEnabled then
        parentOption.notAvailable = true
    end
end

-- @param hasTools boolean|nil  False when the player can't install any part of this category
function BAM.GenerateInstallDescription(player, vehicle, parts, hasTools)
    local newline = " <LINE>"
    local msg = ""

    -- Explain the greyed out button right at the top
    if hasTools == false then
        msg = "<RED>" .. getText("UI_BAM_button_desc.no_tools") .. newline .. newline .. "<RGB:1,1,1>"
    end

    msg = msg .. getText("UI_BAM_button_desc.needs") .. ":"

    local requiredTools = BAM.GetRequiredToolsForParts(parts, "install")

    local needsScrewdriver = false
    local needsWrench = false
    local needsLugWrench = false
    local needsJack = false

     for toolID, _ in pairs(requiredTools) do
        local lowerID = string.lower(toolID)
        if string.find(lowerID, "screwdriver") then needsScrewdriver = true
        elseif string.find(lowerID, "lug") then needsLugWrench = true
        elseif string.find(lowerID, "wrench") then needsWrench = true
        elseif string.find(lowerID, "jack") then needsJack = true
        end
    end

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

    local requiredRecipes = BAM.GetRequiredInstallRecipes(vehicle, parts)
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

    if not BAM.PlayerHasCarAccess(player, vehicle) then
        msg = msg .. newline
        msg = msg .. newline .. "<RGB:1,1,1>" .. getText("UI_BAM_button_desc.no_car_access")
        msg = msg .. newline .. "<ORANGE> - " .. getText("UI_BAM_button_desc.parts_inaccessible")
    end

    msg = msg .. newline
    msg = msg .. newline .. "<RGB:1,1,1>" .. getText("UI_BAM_button_desc.empty_seats")

    return msg
end

function BAM.InstallCategory(playerOrSelf, player, vehicle, categoryIds)
    ISTimedActionQueue.clear(player)
    BAM.StopMechanicsWork(nil)

    local parts = BAM.GetInstallablePartsByCategory(player, vehicle, categoryIds)
    if #parts == 0 then return end

    DebugLog.log("=================================")
    DebugLog.log("BAM: Starting batch install of " .. #parts .. " parts...")
    BAM.IsCurrentlyBatchInstalling = true
    BAM.BatchInstallCategoryIds = categoryIds
    BAM.Vehicle = vehicle
    BAM.workOnNextInstallPart(player, vehicle)
end

function BAM.workOnNextInstallPart(player, vehicle)
    if not player or not vehicle then
        BAM.StopMechanicsWork(nil)
        return
    end

    local distanceToCar = player:DistToSquared(vehicle)
    if distanceToCar > 10 and BAM.LastWorkedPart then
        DebugLog.log("BAM: Player is too far from vehicle (" .. tostring(distanceToCar) .. " tiles). Stopping batch install.")
        BAM.StopMechanicsWork(nil)
        return
    end

    DebugLog.log("Deciding on next batch install part...")
    local parts = BAM.GetInstallablePartsByCategory(player, vehicle, BAM.BatchInstallCategoryIds)

    for _, part in ipairs(parts) do
        local item = BAM.PartCanBeBatchInstalled(player, vehicle, part)
        if item then
            DebugLog.log("BAM: Next part to batch install: " .. part:getId())
            BAM.InstallPart(player, part, item)
            return
        end
    end

    DebugLog.log("BAM: No more accessible parts to batch install.")
    BAM.StopMechanicsWork(nil)
end

function BAM.GetInstallablePartsByCategory(player, vehicle, categoryIds)
    local validParts = {}
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        if categoryIds == nil or categoryIds[part:getId()] then
            table.insert(validParts, part)
        end
    end

    local sortedParts = BAM.SortParts(validParts)
    local installableParts = {}

    for _, part in ipairs(sortedParts) do
        if BAM.PartCanBeBatchInstalled(player, vehicle, part) then
             table.insert(installableParts, part)
        end
    end
    return installableParts
end


function BAM.PartCanBeBatchInstalled(player, vehicle, part)
    if part:getInventoryItem() then return nil end
    if not part:getVehicle():canInstallPart(player, part) then return nil end
    if BAM.IsPartInaccessible(part) then return nil end

    local successChance = BAM.GetPartSuccessChance(player, part, "install")
    if successChance < 1 then return nil end

    if part:getId():find("WindowFront") or part:getId():find("Seat") then
        local scriptName = vehicle:getScript():getName()
        if string.find(scriptName, "Burnt") or string.find(scriptName, "Smashed") then
            return nil
        end
    end

    local item = BAM.GetBestItemForPart(player, part)
    if not item then return nil end

    if BAM.WouldExceedWeightLimit(player, item) then return nil end

    return item
end

function BAM.GetRequiredInstallRecipes(vehicle, parts)
    local recipes = {}
    recipes["Basic Mechanics"] = false
    recipes["Intermediate Mechanics"] = false
    recipes["Advanced Mechanics"] = false

    if not parts then
         parts = {}
         for i = 0, vehicle:getPartCount() - 1 do
            table.insert(parts, vehicle:getPartByIndex(i))
         end
    end

    for _, part in ipairs(parts) do
        local keyvalues = part:getTable("install")
        if keyvalues and keyvalues.recipes and keyvalues.recipes ~= "" then
            for _, recipe in ipairs(keyvalues.recipes:split(";")) do
                recipes[recipe] = true
            end
        end
    end

    for recipe, required in pairs(recipes) do
        if not required then
            recipes[recipe] = nil
        end
    end
    return recipes
end

