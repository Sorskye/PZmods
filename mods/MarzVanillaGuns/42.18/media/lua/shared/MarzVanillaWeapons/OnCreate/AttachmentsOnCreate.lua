MarzVanillaGuns_OnCreate = MarzVanillaGuns_OnCreate or {}

local r = newrandom()

local attachmentsTable = {
    ["Base.AssaultRifle"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.556Clip_20:40",
            "Base.556Clip:20",
            "Base.556Clip_75:2",

            "Base.x2Scope:10",
            "Base.x4Scope:10",
            "Base.Laser:10",
            "Base.RedDot:10",

            "Base.AR_Silencer:2",

            "Base.M9_Bayonet_Attachment:2",
        },
    },

    ["Base.AssaultRifleAK47"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.762Clip_30:20",
            "Base.762Clip_75:2",

            "Base.x2Scope:10",
            "Base.x4Scope:10",
            "Base.Laser:10",
            "Base.RedDot:10",

            "Base.762Muzzle:100",
            "Base.AR_Silencer:2",

            "Base.M9_Bayonet_Attachment:2",
        },
    },

    ["Base.AssaultRifleA3"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.556Clip_20:40",
            "Base.556Clip:20",
            "Base.556Clip_75:2",

            "Base.x2Scope:10",
            "Base.x4Scope:10",
            "Base.Laser:10",
            "Base.RedDot:10",
            "Base.556Muzzle:100",
            "Base.AR_Silencer:2",

            "Base.M9_Bayonet_Attachment:2",
        },
    },

    ["Base.AssaultRifleM4"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.556Clip_20:40",
            "Base.556Clip:20",
            "Base.556Clip_75:2",

            "Base.x2Scope:10",
            "Base.x4Scope:10",
            "Base.Laser:10",
            "Base.RedDot:10",

            "Base.556Muzzle:100",
            "Base.AR_Silencer:2",

            "Base.M9_Bayonet_Attachment:2",
        },
    },

    ["Base.AssaultRifle2"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.M14Clip:40",

            "Base.x2Scope:10",
            "Base.x4Scope:10",
            "Base.RecoilPad:10",
            "Base.Laser:10",
            "Base.RedDot:10",

            "Base.M9_Bayonet_Attachment:2",
        },
    },

    ["Base.SR25_Rifle"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.308Clip_10:40",
            "Base.308Clip_20:20",

            "Base.x2Scope:10",
            "Base.x4Scope:10",
            "Base.RecoilPad:10",
            "Base.Laser:10",
            "Base.RedDot:10",
        },
    },

    ["Base.Pistol"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.9mmClip:40",

            "Base.TritiumSights:10",
            "Base.Laser:10",
            "Base.GunLight:10",

            "Base.Pistol_Silencer:2",
        },
    },

    ["Base.PistolGlock"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.9mmClip:40",

            "Base.TritiumSights:10",
            "Base.Laser:10",
            "Base.GunLight:10",

            "Base.Pistol_Silencer:2",
        },
    },

    ["Base.Pistol2"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.45Clip:40",

            "Base.TritiumSights:10",
            "Base.Laser:10",
            "Base.GunLight:10",

            "Base.Pistol_Silencer:2",
        },
    },

    ["Base.Pistolm93r"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.9mmClip:40",

            "Base.TritiumSights:10",
            "Base.Laser:10",
            "Base.GunLight:10",

            "Base.Pistol_Silencer:2",
        },
    },

    ["Base.Pistol3"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.44Clip:40",

            "Base.TritiumSights:10",
            "Base.Laser:10",
            "Base.GunLight:10",

            "Base.Heavy_Pistol_Silencer:2",
        },
    },

    ["Base.Shotgun"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.AmmoStraps:10",
            "Base.RecoilPad:10",
            "Base.ChokeTubeImproved:10",
            "Base.ChokeTubeFull:5",
        },
    },

    ["Base.ShotgunSawnoff"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.AmmoStraps:10",
        },
    },

    ["Base.JS3T_Shotgun"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.AmmoStraps:10",
            "Base.RedDot:10"
        },
    },

    ["Base.JS14_Rifle"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.JS14_Clip:40",
            "Base.JS14_Clip_30:20",

            "Base.x2Scope:10",
            "Base.x4Scope:10",
            "Base.RedDot:10",
            "Base.Laser:10",
        },
    },

    ["Base.VarmintRifle"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.x2Scope:10",
            "Base.x4Scope:10",
            "Base.x8Scope:10",
            "Base.AmmoStraps:10",
            "Base.RecoilPad:10",
        },
    },

    ["Base.HuntingRifle"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.x2Scope:10",
            "Base.x4Scope:10",
            "Base.x8Scope:10",
            "Base.AmmoStraps:10",
            "Base.RecoilPad:10",
        },
    },

    ["Base.MSR7T_Rifle"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.x2Scope:10",
            "Base.x4Scope:10",
            "Base.x8Scope:10",
            "Base.AmmoStraps:10",
            "Base.RecoilPad:10",
            "Base.Laser:10",
        },
    },

    ["Base.TrapperCarbine"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.45Clip:40",

            "Base.x2Scope:10",
            "Base.x4Scope:10",
            "Base.Laser:10",
            "Base.RedDot:10",
        },
    },

    ["Base.L92_Carbine"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.AmmoStraps:10",
        },
    },

    ["Base.L94_Rifle"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.AmmoStraps:10",
            "Base.RecoilPad:10",
        },
    },

    ["Base.MP5_SMG"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.9mmClip_25:40",
            "Base.9mmClip_30:20",
            "Base.9mmClip_40:5",
            "Base.9mmClip_100:1",

            "Base.x2Scope:10",
            "Base.Laser:10",
            "Base.RedDot:10",
            "Base.GunLight:10",
        },
    },

    ["Base.MP5SD_SMG"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.9mmClip_25:40",
            "Base.9mmClip_30:20",
            "Base.9mmClip_40:5",
            "Base.9mmClip_100:1",

            "Base.x2Scope:10",
            "Base.Laser:10",
            "Base.RedDot:10",
            "Base.GunLight:10",
        },
    },

    ["Base.DoubleBarrelShotgun"] = {
        ["optionals"] = {
            "Base.AmmoStraps:10",
            "Base.RecoilPad:10",
            "Base.ChokeTubeImproved:10",
            "Base.ChokeTubeFull:5",
        },
    },

    ["Base.Side_By_Side"] = {
        ["required"] = {
            "Base.Side_By_Side_Barrel_Close",
        },
        ["optionals"] = {
            "Base.Side_By_Side_Barrel_Sawnoff_Close:10",
        },
    },

    ["Base.AC556"] = {
        ["required"] = {
            "Base.CloseBolt",
        },
        ["optionals"] = {
            "Base.JS14_Clip:40",
            "Base.JS14_Clip_30:20",

            "Base.x2Scope:10",
            "Base.x4Scope:10",
            "Base.RedDot:10"
        },
    },
}

local function parseOptionalAttachmentEntry(entry)
    local itemType, chance = string.match(entry, "^([^:]+):([^:]+)$")

    if itemType then
        return itemType, tonumber(chance) or 0, nil
    end

    return entry, 100, nil
end

function MarzVanillaGuns_OnCreate.AttachParts(weapon)
    if not weapon then return end

    local listOfAttachments = attachmentsTable[weapon:getFullType()]
    if listOfAttachments then
        local requiredParts = listOfAttachments["required"] or {}
        for i = 1, #requiredParts do
            local partItemType = requiredParts[i]
            local part = instanceItem(partItemType)
            if part then
                weapon:attachWeaponPart(part)
            end
        end

        local optionalParts = listOfAttachments["optionals"] or {}
        for i = 1, #optionalParts do
            local partItemTypeChance = optionalParts[i]
            local itemType, chanceNum = parseOptionalAttachmentEntry(partItemTypeChance)

            local roll = chanceNum > 0 and r:random(100) < chanceNum
            if roll then
                local part = instanceItem(itemType)
                if part then
                    weapon:attachWeaponPart(part)
                end
            end
        end
    end

    if weapon:getWeaponPart("BayonetKnife") ~= nil then
        weapon:getModData().GW_BayonetDeployed = true
    end

    if weapon:getMagazineType() == nil then
        local randomAmmo = r:random(weapon:getMaxAmmo())
        weapon:setCurrentAmmoCount(randomAmmo)
    end

    if weapon:getWeaponPart("Clip") ~= nil then
        local magazine = weapon:getWeaponPart("Clip")
        local randomAmmo = r:random(magazine:getMaxAmmo())
        weapon:setMaxAmmo(magazine:getMaxAmmo())
        weapon:setMagazineType(magazine:getFullType())
        weapon:setCurrentAmmoCount(randomAmmo)
        weapon:setContainsClip(true)
        weapon:getModData().MagazineType = magazine:getFullType()
    else
        weapon:setContainsClip(false)
    end
end
