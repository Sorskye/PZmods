-- Immersive Snow, MP server: puts the water from snow a client sent for its own player into that
-- player's clothes (ISnow_SnowWetness.lua, "wet"); the clothing wetness then reaches the client as
-- the game syncs it.

if not isServer() then return end

require "ImmersiveSnow/ISnow_SnowWetness"

local MODULE = "ISnow"

local function onClientCommand(module, command, player, args)
    if module ~= MODULE or command ~= "wet" or not player then return end
    local ok, err = pcall(ISnow.SnowWetness.onClientWet, player, args)
    if not ok then print("[ImmersiveSnow] wetness from a client failed: " .. tostring(err)) end
end
Events.OnClientCommand.Add(onClientCommand)
