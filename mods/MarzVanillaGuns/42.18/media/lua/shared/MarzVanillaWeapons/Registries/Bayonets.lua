local Bayonet = require("WeaponSystems/Utils/Bayonet")

-------------------------------------------------
-- Mountable Weapons (weapon -> bayonet attachment)
-------------------------------------------------
Bayonet.RegisterMountableWeapon({ "Base.M9_Bayonet_Attachment" }, {
    "Base.AssaultRifle",
    "Base.AssaultRifle2",
    "Base.AssaultRifleAK47",
    "Base.AssaultRifleA3",
    "Base.AssaultRifleM4",
})

-------------------------------------------------
-- Bayonet Knives (knife -> bayonet attachment -> spear substitute)
-------------------------------------------------
Bayonet.RegisterBayonetKnife("Base.M9_Bayonet", "Base.M9_Bayonet_Attachment", "Base.Attack_Bayonet")

Bayonet.SetExclusives({ "Base.M9_Bayonet_Attachment" }, {
    "Base.AR_Silencer",
})
