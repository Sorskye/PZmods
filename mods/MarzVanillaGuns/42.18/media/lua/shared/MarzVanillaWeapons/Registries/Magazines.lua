local Magazine = require("WeaponSystems/Utils/Magazine")

-------------------------------------
--- Magazine Profiles
-------------------------------------
Magazine.RegisterMultipleMagazineProfiles({
    ["STANAG"] = {
        "Base.556Clip_20",
        "Base.556Clip",
        "Base.556Clip_75",
    },

    ["762x39"] = {
        "Base.762Clip_30",
        "Base.762Clip_75",
    },

    ["762x51"] = {
        "Base.308Clip_10",
        "Base.308Clip_20",
    },

    ["9mm MP5"] = {
        "Base.9mmClip_25",
        "Base.9mmClip_30",
        "Base.9mmClip_40",
        "Base.9mmClip_100",
    },

    ["JS14"] = {
        "Base.JS14_Clip",
        "Base.JS14_Clip_30",
    },
})

-------------------------------------
--- Weapon in Magazine Profiles
-------------------------------------
Magazine.RegisterMultipleWeaponsWithProfiles({
    ["STANAG"] = {
        "Base.AssaultRifle",
        "Base.AssaultRifleA3",
        "Base.AssaultRifleM4",
    },

    ["762x39"] = {
        "Base.AssaultRifleAK47",
    },

    ["762x51"] = {
        "Base.SR25_Rifle",
    },

    ["9mm MP5"] = {
        "Base.MP5_SMG",
        "Base.MP5SD_SMG"
    },

    ["JS14"] = {
        "Base.JS14_Rifle",
        "Base.AC556"
    },
})
