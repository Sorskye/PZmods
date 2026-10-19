local SpentCasingPhysics

if getActivatedMods():contains("HBVCEFb42") then
    SpentCasingPhysics = require("SpentCasingPhysics/Init")
end

if SpentCasingPhysics then
    SpentCasingPhysics.RegisterWeaponParams({

        ["Base.AssaultRifle"] = {
            forwardOffset = 0.30,
            sideOffset    = 0.10,
            heightOffset  = 0.45,
            shellForce    = 0.90,
            sideSpread    = 60,
            heightSpread  = 30,
            ejectAngle    = 75,
            spinForce     = { 64, 128 }
        },

        ["Base.AssaultRifleAK47"] = {
            forwardOffset = 0.35,
            sideOffset    = 0.10,
            heightOffset  = 0.45,
            shellForce    = 0.90,
            sideSpread    = 60,
            heightSpread  = 75,
            ejectAngle    = 45,
            spinForce     = { 64, 128 }
        },

        ["Base.AssaultRifleA3"] = {
            forwardOffset = 0.30,
            sideOffset    = 0.10,
            heightOffset  = 0.45,
            shellForce    = 0.90,
            sideSpread    = 60,
            heightSpread  = 30,
            ejectAngle    = 75,
            spinForce     = { 64, 128 }
        },

        ["Base.AssaultRifleM4"] = {
            forwardOffset = 0.30,
            sideOffset    = 0.10,
            heightOffset  = 0.45,
            shellForce    = 0.90,
            sideSpread    = 60,
            heightSpread  = 30,
            ejectAngle    = 75,
            spinForce     = { 64, 128 }
        },

        ["Base.AssaultRifle2"] = {
            forwardOffset = 0.35,
            sideOffset    = 0.10,
            heightOffset  = 0.45,
            shellForce    = 0.55,
            sideSpread    = 90,
            heightSpread  = { 80, 90 },
            ejectAngle    = 25,
            spinForce     = { 64, 128 }
        },

        ["Base.HuntingRifle"] = {
            forwardOffset = 0.38,
            sideOffset    = 0.10,
            heightOffset  = 0.45,
            shellForce    = 0.45,
            sideSpread    = 60,
            heightSpread  = 60,
            ejectAngle    = 70,
            spinForce     = { 8, 12 }
        },

        ["Base.MSR7T_Rifle"] = {
            forwardOffset = 0.40,
            sideOffset    = 0.10,
            heightOffset  = 0.45,
            shellForce    = 0.45,
            sideSpread    = 60,
            heightSpread  = 60,
            spinForce     = { 8, 12 }
        },

        ["Base.L92_Carbine"] = {
            forwardOffset = 0.35,
            sideOffset    = 0.10,
            heightOffset  = 0.45,
            shellForce    = 0.35,
            sideSpread    = 50,
            heightSpread  = { 40, 50 },
            ejectAngle    = 10,
            spinForce     = { 6, 8 }
        },

        ["Base.L94_Rifle"] = {
            forwardOffset = 0.35,
            sideOffset    = 0.10,
            heightOffset  = 0.45,
            shellForce    = 0.35,
            sideSpread    = 50,
            heightSpread  = 30,
            ejectAngle    = 55,
            spinForce     = { 6, 8 }
        },

        ["Base.Pistol"] = {
            forwardOffset = 0.40,
            sideOffset    = 0.0,
            heightOffset  = 0.50,
            shellForce    = 0.60,
            sideSpread    = 45,
            heightSpread  = 60,
            spinForce     = { 12, 16 }
        },

        ["Base.Pistolm93r"] = {
            forwardOffset = 0.40,
            sideOffset    = 0.0,
            heightOffset  = 0.50,
            shellForce    = 0.60,
            sideSpread    = 45,
            heightSpread  = 60,
            ejectAngle    = 45,
            spinForce     = { 12, 16 }
        },

        ["Base.Pistol2"] = {
            forwardOffset = 0.40,
            sideOffset    = 0.0,
            heightOffset  = 0.50,
            shellForce    = 0.60,
            sideSpread    = 50,
            heightSpread  = 45,
            spinForce     = { 12, 16 }
        },

        ["Base.Pistol3"] = {
            forwardOffset = 0.35,
            sideOffset    = 0.0,
            heightOffset  = 0.50,
            shellForce    = 0.35,
            sideSpread    = 30,
            heightSpread  = { 100, 130 },
            ejectAngle    = 0,
            spinForce     = { 12, 16 }
        },

        ["Base.Revolver_Long"] = {
            forwardOffset = 0.10,
            sideOffset    = 0.0,
            heightOffset  = 0.30,
            shellForce    = 0.10,
            sideSpread    = 50,
            heightSpread  = { 30, 50 },
            spinForce     = { 3, 6 }
        },

        ["Base.Revolver_Short"] = {
            forwardOffset = 0.10,
            sideOffset    = 0.0,
            heightOffset  = 0.30,
            shellForce    = 0.10,
            sideSpread    = 50,
            heightSpread  = { 30, 50 },
            spinForce     = { 3, 6 }
        },

        ["Base.Revolver"] = {
            forwardOffset = 0.10,
            sideOffset    = 0.0,
            heightOffset  = 0.30,
            shellForce    = 0.10,
            sideSpread    = 50,
            heightSpread  = { 30, 50 },
            spinForce     = { 3, 6 }
        },

        ["Base.Side_By_Side"] = {
            forwardOffset = 0.27,
            sideOffset    = 0.0,
            heightOffset  = 0.45,
            shellForce    = 0.15,
            sideSpread    = 30,
            heightSpread  = { 80, 100 },
            ejectAngle    = 180,
            spinForce     = { 2, 6 }
        },

        ["Base.Side_By_Side_Sawnoff"] = {
            forwardOffset = 0.27,
            sideOffset    = 0.0,
            heightOffset  = 0.45,
            shellForce    = 0.15,
            sideSpread    = 30,
            heightSpread  = { 80, 100 },
            ejectAngle    = 180,
            spinForce     = { 2, 6 }
        },
    })

    SpentCasingPhysics.RegisterCasingToAmmo({
        ["Base.762Bullets"] = "HBVCEF.762x39_Casing",
    })
end
