local CSA = require("WeaponSystems/Utils/CustomStatsAttachments")
local SF  = require("WeaponSystems/Utils/StatsFactory")

CSA.RegisterRestoreStats({
    "SoundRadius",
    "SoundVolume",
    "MaxDamage",
    "MinDamage",
    "SwingSound",
    "MuzzleFlashModelKey",
    "AimingTime",
    "HitChance",
    "ProjectileSpread",
})

CSA.RegisterMultipleParts({

    ["Base.Pistol_Silencer"] = {
        SF.Multiply("SoundRadius", 0.3),
        SF.Multiply("SoundVolume", 0.3),
        SF.Multiply("MaxDamage", 0.9),
        SF.Multiply("MinDamage", 0.9),
        SF.Set("SwingSound", "CapGunRifleShoot"),
        SF.Set("MuzzleFlashModelKey", nil),
    },

    ["Base.Heavy_Pistol_Silencer"] = {
        SF.Multiply("SoundRadius", 0.3),
        SF.Multiply("SoundVolume", 0.3),
        SF.Multiply("MaxDamage", 0.9),
        SF.Multiply("MinDamage", 0.9),
        SF.Set("SwingSound", "CapGunRevolverShoot"),
        SF.Set("MuzzleFlashModelKey", nil),
    },

    ["Base.AR_Silencer"] = {
        SF.Multiply("SoundRadius", 0.3),
        SF.Multiply("SoundVolume", 0.3),
        SF.Multiply("MaxDamage", 0.9),
        SF.Multiply("MinDamage", 0.9),
        SF.Set("SwingSound", "CapGunRevolverShoot"),
        SF.Set("MuzzleFlashModelKey", nil),
    },

    ["Base.556Muzzle"] = {
        SF.Multiply("SoundRadius", 0.99),
        SF.Multiply("SoundVolume", 0.99),
    },

    ["Base.762Muzzle"] = {
        SF.Multiply("SoundRadius", 0.99),
        SF.Multiply("SoundVolume", 0.99),
    },

    ["Base.Side_By_Side_Barrel_Sawnoff_Close"] = {
        SF.Set("AimingTime", 30),
        SF.Set("HitChance", 70),
        SF.Set("ProjectileSpread", 2.0)
    },

    ["Base.Side_By_Side_Barrel_Sawnoff_Open"] = {
        SF.Set("AimingTime", 30),
        SF.Set("HitChance", 70),
        SF.Set("ProjectileSpread", 2.0)
    },
})
