local Ammo = require("WeaponSystems/Utils/Ammo")
local StatsFactory = require("WeaponSystems/Utils/StatsFactory")

-------------------------------------------------
-- Restore Stats: stats that ammo profiles may modify
-------------------------------------------------
Ammo.RegisterRestoreStats({
    "MaxDamage",
    "MinDamage",
    "CritDmgMultiplier",
    "CriticalChance",
    "ConditionLowerChanceOneIn",
})

-------------------------------------------------
-- Item -> Ammo Family mappings
-------------------------------------------------
Ammo.RegisterMultipleItemsWithFamilies({
    [".38 .357"] = {
        "Base.Revolver",
        "Base.Revolver_Short",
    },
})

-------------------------------------------------
-- Ammo Families (bullet types per caliber)
-------------------------------------------------
Ammo.RegisterMultipleAmmoFamilies({
    [".38 .357"] = {
        { type = "Base.Bullets357", enum = AmmoType.BULLETS_357, profile = "357MagnumAmmo" },
        { type = "Base.Bullets38",  enum = AmmoType.BULLETS_38,  profile = "38SpecialAmmo" },
    },
})

-------------------------------------------------
-- Ammo Stat Profiles
-------------------------------------------------
Ammo.RegisterMultipleAmmoStats({
    ["38SpecialAmmo"] = {
        StatsFactory.Multiply("MaxDamage", 0.8),
        StatsFactory.Multiply("MinDamage", 0.8),
        StatsFactory.Multiply("CritDmgMultiplier", 0.80),
        StatsFactory.Multiply("CriticalChance", 0.9),
        StatsFactory.Multiply("ConditionLowerChanceOneIn", 1.20),
    },
})
