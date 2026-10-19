-- Immersive Snow, MP client: the water from snow not sent to the server yet (ISnow_SnowWetness.lua,
-- every SEND_MS) goes when the player quits from the in-game menu, before the game disconnects.
-- Quitting (Core.quit / exitToMenu) sets Core.exiting, and the next IngameState update calls
-- doDisconnect before GameWindow.save raises OnSave (bytecode 42): OnSave, OnPostSave and
-- OnDisconnect all come too late to send anything. So the menu items themselves are hooked.
--
-- The in-game menu (MainScreen, made by LoadMainScreenPanelIngame on OnGameStart) keeps the item
-- handler it is given when it is made (item.onMouseDown = MainScreen.onMenuItemMouseDownMainMenu),
-- so the hook goes in when this file loads, before OnGameStart, and also onto the items of a menu
-- already there (a live reload).

require "ImmersiveSnow/ISnow_SnowWetness"
require "OptionScreens/MainScreen"

local QUIT_ITEMS = { EXIT = true, QUIT_TO_DESKTOP = true }

local function hook()
    if not (MainScreen and MainScreen.onMenuItemMouseDownMainMenu) or MainScreen.ISnowWetHooked then return end
    local vanilla = MainScreen.onMenuItemMouseDownMainMenu
    local function onItem(item, x, y)
        if item and QUIT_ITEMS[item.internal] and isClient() then
            local ok, err = pcall(ISnow.SnowWetness.flushAll)
            if not ok then print("[ImmersiveSnow] wetness flush failed: " .. tostring(err)) end
        end
        return vanilla(item, x, y)
    end
    MainScreen.onMenuItemMouseDownMainMenu = onItem
    MainScreen.ISnowWetHooked = true
    local menu = MainScreen.instance
    if menu then
        for _, item in ipairs({ menu.exitOption, menu.quitToDesktopOption }) do
            if item and item.onMouseDown == vanilla then item.onMouseDown = onItem end
        end
    end
end

hook()
ISnow.SnowWetness.hookQuitMenu = hook   -- for a live reload by hand and the offline test
