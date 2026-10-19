-- Immersive Snow: the Options > Mods page (ISnow.initModOptions in ISnow_Config.lua).
--
-- ISnow_Config.lua is shared and loads before client/PZAPI/ModOptions.lua, so it cannot make the
-- page itself; this client file requires the API first and then makes it.

require "PZAPI/ModOptions"
require "ImmersiveSnow/ISnow_Config"

ISnow.initModOptions()
