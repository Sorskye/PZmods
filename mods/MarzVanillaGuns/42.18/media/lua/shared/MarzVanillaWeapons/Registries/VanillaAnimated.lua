local Animations    = require("WeaponSystems/Utils/Animations")

local fn            = { SingleAttachment = { open = "Base.OpenBolt", locked = "Base.CloseBolt" } }
local fn_fast       = { SingleAttachment = { open = "Base.OpenBolt", locked = "Base.CloseBolt" }, cycleTicks = 3 }
local fn_sidebyside = {
    MultipleAttachmentsVariant = {
        Barrel = {
            partType = "Barrel",
            variants = {
                ["Base.Side_By_Side_Barrel_Close"]         = { open = "Base.Side_By_Side_Barrel_Open", locked = "Base.Side_By_Side_Barrel_Close" },
                ["Base.Side_By_Side_Barrel_Open"]          = { open = "Base.Side_By_Side_Barrel_Open", locked = "Base.Side_By_Side_Barrel_Close" },
                ["Base.Side_By_Side_Barrel_Sawnoff_Close"] = { open = "Base.Side_By_Side_Barrel_Sawnoff_Open", locked = "Base.Side_By_Side_Barrel_Sawnoff_Close" },
                ["Base.Side_By_Side_Barrel_Sawnoff_Open"]  = { open = "Base.Side_By_Side_Barrel_Sawnoff_Open", locked = "Base.Side_By_Side_Barrel_Sawnoff_Close" },
            },
        },
    }
}

Animations.RegisterMultipleWeaponsWithAnimatedParts({
    ["Base.Pistol"] = fn,
    ["Base.PistolGlock"] = fn,
    ["Base.Pistolm93r"] = fn,
    ["Base.Pistol2"] = fn,
    ["Base.Pistol3"] = fn,
    ["Base.AssaultRifle"] = fn_fast,
    ["Base.AssaultRifle2"] = fn_fast,
    ["Base.AssaultRifleAK47"] = fn_fast,
    ["Base.AssaultRifleA3"] = fn_fast,
    ["Base.AssaultRifleM4"] = fn_fast,
    ["Base.SR25_Rifle"] = fn_fast,
    ["Base.Shotgun"] = fn,
    ["Base.ShotgunSawnoff"] = fn,
    ["Base.VarmintRifle"] = fn,
    ["Base.HuntingRifle"] = fn,
    ["Base.MSR7T_Rifle"] = fn,
    ["Base.JS3T_Shotgun"] = fn,
    ["Base.JS14_Rifle"] = fn_fast,
    ["Base.L92_Carbine"] = fn,
    ["Base.L94_Rifle"] = fn,
    ["Base.TrapperCarbine"] = fn,
    ["Base.MP5_SMG"] = fn_fast,
    ["Base.MP5SD_SMG"] = fn_fast,
    ["Base.Side_By_Side"] = fn_sidebyside,
    ["Base.AC556"] = fn_fast,
})
