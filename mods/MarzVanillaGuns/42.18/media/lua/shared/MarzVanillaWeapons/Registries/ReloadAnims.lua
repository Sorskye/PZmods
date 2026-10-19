local ReloadAnim = require("WeaponSystems/ReloadAnim/HandlerFactory")

local BREAK_ACTION_PROFILE = { animId = "breakaction", archetype = "doublebarrel" }

ReloadAnim.RegisterMultipleWeapons({
    ["Base.DoubleBarrelShotgun"] = BREAK_ACTION_PROFILE,
    ["Base.DoubleBarrelShotgunSawnoff"] = BREAK_ACTION_PROFILE,
    ["Base.Side_By_Side"] = BREAK_ACTION_PROFILE,
})
