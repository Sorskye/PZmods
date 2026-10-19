BAM = BAM or {}
BAM.IsCurrentlyTraining = false
BAM.IsCurrentlyBatchUninstalling = false
BAM.IsCurrentlyBatchInstalling = false
BAM.BatchUninstallCategoryIds = nil  -- nil = everything, or a set-like table of part IDs
BAM.BatchInstallCategoryIds = nil
BAM.Vehicle = nil
BAM.WorkDelayTimer = 0
BAM.GameSpeedCheckTimer = 0
BAM.LastWorkedPart = nil
BAM.LastWorkedActionType = nil -- 1 = uninstall, 2 = install
BAM.InaccessibleParts = {}
BAM.WorkedParts = {}
BAM.PrevGameSpeed = 1
BAM.PrevTimeMultiplier = 1
BAM.DroppedItems = {}


--- Returns true if the player is currently doing any automated BAM work (training or batch uninstalling).
function BAM.IsCurrentlyWorking()
    return BAM.IsCurrentlyTraining or BAM.IsCurrentlyBatchUninstalling or BAM.IsCurrentlyBatchInstalling
end


--- Dispatches to the correct "work on next part" function depending on which mode is active.
function BAM.ContinueWork(player, vehicle)
    if BAM.IsCurrentlyTraining then
        BAM.workOnNextPart(player, vehicle)
    elseif BAM.IsCurrentlyBatchUninstalling then
        BAM.workOnNextUninstallPart(player, vehicle)
    elseif BAM.IsCurrentlyBatchInstalling then
        BAM.workOnNextInstallPart(player, vehicle)
    else
        DebugLog.log("Error: ContinueWork called but no active BAM work in progress.")
        BAM.StopMechanicsWork(nil)
    end
end


function BAM:StartMechanicsTraining(player, vehicle)
    -- Stop any active training or batch uninstall first
    ISTimedActionQueue.clear(player)
    BAM.StopMechanicsWork(nil)

    DebugLog.log("=================================")
    DebugLog.log("Starting mechanics training!")
    BAM.IsCurrentlyTraining = true
    BAM.Vehicle = vehicle

    -- Stop Tidy Up Meister from re-equipping tools mid-work
    if P4TidyUpMeister then
        DebugLog.log("Disabled Tidy Up Meister temporarily.")
        P4TidyUpMeister.doNotReequip = true
    end

    BAM.workOnNextPart(player, vehicle)
end


function BAM.StopMechanicsWork(player, msgOverride, r, g, b)
    if BAM.IsCurrentlyTraining then
        DebugLog.log("Finished mechanics training!")
    elseif BAM.IsCurrentlyBatchUninstalling then
        DebugLog.log("Finished batch uninstall!")
    elseif BAM.IsCurrentlyBatchInstalling then
        DebugLog.log("Finished batch install!")
    else  -- If not currently working, just reset the state
        BAM.ResetState()
        return
    end

    BAM.ResetState()
    if not isClient() then
        setGameSpeed(1)
        getGameTime():setMultiplier(1)
    end

    -- Enable Tidy Up Meister's again
    if P4TidyUpMeister then
        DebugLog.log("Re-enabled Tidy Up Meister.")
        P4TidyUpMeister.doNotReequip = false
    end

    local msg = msgOverride or getText("UI_BAM_message.car_completed")
    r = r or 0
    g = g or 255
    b = b or 0

    -- Display an in-game notification to inform the player that training has finished
    if player then
        -- Also pickup items dropped by the player during training, if any
        local pickedUpAnyItems = BAM.PickupItems(player, BAM.DroppedItems)
        BAM.DroppedItems = {}
        if pickedUpAnyItems then
            msg = msg .. " " .. getText("UI_BAM_message.car_completed_pickup_items")
        end

        HaloTextHelper.addText(player, msg, "[br/]", r, g, b)
    end

    getPlayer():setSneaking(false)

    --for i, partInfo in ipairs(BAM.WorkedParts) do
    --    DebugLog.log(i .. ". " .. partInfo)
    --end

    DebugLog.log("=================================")
end


function BAM.ResetState()
    BAM.IsCurrentlyTraining = false
    BAM.IsCurrentlyBatchUninstalling = false
    BAM.IsCurrentlyBatchInstalling = false
    BAM.BatchUninstallCategoryIds = nil
    BAM.BatchInstallCategoryIds = nil
    BAM.Vehicle = nil
    BAM.WorkDelayTimer = 0
    BAM.LastWorkedPart = nil
    BAM.LastWorkedActionType = nil
    BAM.InaccessibleParts = {}
    BAM.WorkedParts = {}
    BAM.PrevGameSpeed = 1
    BAM.PrevTimeMultiplier = 1
end


function BAM.workOnNextPart(player, vehicle)
    -- Safety check: ensure player and vehicle are valid
    if not player or not vehicle then
        BAM.StopMechanicsWork(nil)
        return
    end

    -- First check if we are too far away from the vehicle
    local distanceToCar = player:DistToSquared(vehicle)
    --DebugLog.log("Player distance to vehicle squared: " .. distanceToCar)
    if distanceToCar > 10 and BAM.LastWorkedPart then
        DebugLog.log("Player is too far from vehicle (" .. tostring(distanceToCar) .. " tiles). Stopping training.")
        BAM.StopMechanicsWork(nil)
        return
    end

    -- Gather info about next parts to install/uninstall
    DebugLog.log("Deciding on next part...")
    local partUninstall = BAM.GetNextUninstallablePart(player, vehicle)
    local partInstall, itemInstall = BAM.GetNextInstallablePartAndItem(player, vehicle)
    --DebugLog.log("Next part to uninstall: " .. (partUninstall and partUninstall:getId() or "None"))
    --DebugLog.log("Next part to install: " .. (partInstall and partInstall:getId() or "None"))

    -- If no parts to install or uninstall, stop training
    if partUninstall == nil and partInstall == nil then
        DebugLog.log("No more parts to work on.")
        BAM.StopMechanicsWork(player)
        return
    end

    -- Before we install any part, check if it requires other parts to be installed first.
    -- If yes, uninstall those parts first.
    if partInstall then
        local requiredParts = BAM.GetRequiredInstalledPartsForPart(partInstall)
        for _, requiredPart in ipairs(requiredParts) do
            if BAM.PartCanBeUninstalled(player, vehicle, requiredPart) then
                DebugLog.log("Uninstalling " .. partInstall:getId() .. " made part " .. requiredPart:getId() .. " available for uninstall.")
                BAM.UninstallPart(player, requiredPart)
                return
            end
        end
    end

    -- If we can install any part, do it. We always prioritize installation over uninstallation (except for multi-level installations above)
    if partInstall and itemInstall then
        BAM.InstallPart(player, partInstall, itemInstall)
        return
    end

    -- Otherwise, uninstall the next part
    if partUninstall then
        BAM.UninstallPart(player, partUninstall)
        return
    end

    -- If we reach here, something went wrong. Probably because we have a part to install but no item for it.
    DebugLog.log("Error: Unable to determine next part to work on.")
    BAM.StopMechanicsWork(player)
end


function BAM.InstallPart(player, part, item)
    local successChance = BAM.GetPartSuccessChance(player, part, "install")
    DebugLog.log("-> Installing part: " .. part:getId() .. " - Success chance: " .. successChance .. "%")
    BAM.LastWorkedPart = part
    BAM.LastWorkedActionType = 2
    table.insert(BAM.WorkedParts, part:getId() .. " - Install")

    -- Drop broken items before installing and then drop items until the new part can fit into the inventory
    BAM.DropBrokenItems(player)
    local droppedItems = BAM.DropItemsUntilGivenItemFits(player, item)
    for i = #droppedItems, 1, -1 do  -- Insert them in reverse, so the lightest items are picked up first when we pickup items after training
        table.insert(BAM.DroppedItems, droppedItems[i])
    end

    ISVehiclePartMenu.onInstallPart(player, part, item)  -- Start timed task
end


function BAM.UninstallPart(player, part)
    local successChance = BAM.GetPartSuccessChance(player, part, "uninstall")
    DebugLog.log("-> Uninstalling part: " .. part:getId() .. " - Success chance: " .. successChance .. "%")
    BAM.LastWorkedPart = part
    BAM.LastWorkedActionType = 1
    table.insert(BAM.WorkedParts, part:getId() .. " - Uninstall")
    BAM.DropBrokenItems(player)  -- Drop broken items before uninstalling
    ISVehiclePartMenu.onUninstallPart(player, part)  -- Start timed task
end
