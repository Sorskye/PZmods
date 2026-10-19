BAM = BAM or {}


-- Create the main section in the "MODS" tab
local modOptions = PZAPI.ModOptions:create("better-auto-mechanics", "Better Auto Mechanics")


-- Arguments: ID, Display Name, Default Value, Tooltip Description
BAM_Options_MinSuccessChance = modOptions:addSlider(
    "BAM_MinSuccessChance",
    getText("UI_BAM_options_title.min_success_chance"),
    0,    -- Min
    100,  -- Max
    1,    -- Step
    30    -- Default
)

-- Add a more detailed description below the option
local desc = getText("UI_BAM_options_desc.min_success_chance_1") .. " <LINE> " ..
       "  - 0%% -> " .. getText("UI_BAM_options_desc.min_success_chance_2") .. " <LINE> " ..
       "  - 30%% -> " .. getText("UI_BAM_options_desc.min_success_chance_3") .. " <LINE> " ..
       "  - 100%% -> " .. getText("UI_BAM_options_desc.min_success_chance_4")
modOptions:addDescription(desc)

BAM_Options_PlayFailureSound = modOptions:addTickBox(
    "BAM_PlayFailureSound",
    getText("UI_BAM_options_title.play_failure_sound"),
    true
)
modOptions:addDescription(getText("UI_BAM_options_desc.play_failure_sound"))


-- Option and Sandbox Utility functions
function BAM.GetOptionPlayFailureSound()
    return BAM_Options_PlayFailureSound:getValue()
end


function BAM.GetOptionMinPartSuccessChance()
    local successChance = nil

    if BAM.IsServerOverwritingOptionMinPartSuccessChance() then
        successChance = SandboxVars.BAM_Server_MinSuccessChance
        --DebugLog.log("Getting server option part success chance: " .. tostring(successChance) .. "%")
        return successChance
    end

    successChance = BAM_Options_MinSuccessChance:getValue()
    --DebugLog.log("Getting local option part success cashance: " .. tostring(successChance) .. "%")
    return successChance
end


function BAM.IsServerOverwritingOptionMinPartSuccessChance()
    if isClient() and SandboxVars and SandboxVars.BAM_Server_MinSuccessChance and SandboxVars.BAM_Server_MinSuccessChance ~= -1 then
        return true
    end
    return false
end
