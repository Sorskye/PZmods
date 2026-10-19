require("Items/ProceduralDistributions")
require("Vehicles/VehicleDistributions")
require("Items/Distributions")
require("Items/Distribution_BagsAndContainers")
require("Definitions/AttachedWeaponDefinitions")

local Distribution = require("Distribution/Functions.lua")

local tables = { ProceduralDistributions.list, VehicleDistributions, SuburbsDistributions, BagsAndContainers }
local zombieTables = { AttachedWeaponDefinitions }

local function applyDistributionPass()
    Distribution.Insert("Base.Pistol", 0.15, tables, "Base.Pistolm93r")
    Distribution.Insert("Base.Pistol", 0.75, tables, "Base.PistolGlock")

    Distribution.Insert("Base.AssaultRifle", 0.25, tables, "Base.AssaultRifleA3")
    Distribution.Insert("Base.AssaultRifle", 0.15, tables, "Base.AssaultRifleM4")
    Distribution.Insert("Base.AssaultRifle", 0.1, tables, "Base.AssaultRifleAK47")
    Distribution.Insert("Base.AssaultRifle", 0.1, tables, "Base.MP5_SMG")
    Distribution.Insert("Base.AssaultRifle", 0.05, tables, "Base.MP5SD_SMG")

    Distribution.Insert("Base.556Box", 0.15, tables, "Base.762Box")
    Distribution.Insert("Base.556Carton", 0.15, tables, "Base.762Carton")

    Distribution.Insert("Base.AssaultRifle2", 0.3, tables, "Base.SR25_Rifle")

    Distribution.Insert("Base.DoubleBarrelShotgun", 0.3, tables, "Base.Side_By_Side")

    Distribution.Insert("Base.JS14_Rifle", 0.25, tables, "Base.AC556")
    Distribution.Insert("Base.MP5_SMG", 0.25, tables, "Base.AC556")

    Distribution.Insert("Base.Laser", 0.05, tables, "Base.Pistol_Silencer")
    Distribution.Insert("Base.GunLight", 0.05, tables, "Base.Pistol_Silencer")

    Distribution.Insert("Base.Laser", 0.05, tables, "Base.Heavy_Pistol_Silencer")
    Distribution.Insert("Base.GunLight", 0.05, tables, "Base.Heavy_Pistol_Silencer")

    Distribution.Insert("Base.Laser", 0.05, tables, "Base.AR_Silencer")
    Distribution.Insert("Base.GunLight", 0.05, tables, "Base.AR_Silencer")
end

Events.OnPostDistributionMerge.Add(applyDistributionPass)

Events.OnInitGlobalModData.Add(
    function()
        Distribution.Insert("Base.Pistol", 0.25, zombieTables, "Base.PistolGlock")

        Distribution.Insert("Base.AssaultRifle", 0.25, zombieTables, "Base.AssaultRifleA3")
        Distribution.Insert("Base.AssaultRifle", 0.05, zombieTables, "Base.MP5_SMG")

        Distribution.Insert("Base.AssaultRifle2", 0.3, zombieTables, "Base.SR25_Rifle")

        Distribution.Insert("Base.JS14_Rifle", 0.25, zombieTables, "Base.AC556")
        Distribution.Insert("Base.JS14_Rifle", 0.25, zombieTables, "Base.AC556")

        Distribution.Insert("Base.DoubleBarrelShotgun", 0.3, zombieTables, "Base.Side_By_Side")
    end
)
