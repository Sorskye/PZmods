require("SpentCasingPhysics/ModSupport")
local SpentCasingPhysics = require("SpentCasingPhysics/Init")
local GSU = require("GunworksUtils/itemAdjustments")

if SpentCasingPhysics then
    Events.OnInitWorld.Add(function()
        GSU.Adjust("Base.762Bullets", "WorldStaticModel", "HBVCEF.762x39_Round_Base")
        GSU.Adjust("Base.223Bullets", "WorldStaticModel", "HBVCEF.223_Round")
        if SandboxVars.HB.CustomIcons then
            GSU.Adjust("Base.762Bullets", "icon", "762x39_Round_Base")
            GSU.Adjust("Base.223Bullets", "icon", "223_Round")
        end
    end)
end
