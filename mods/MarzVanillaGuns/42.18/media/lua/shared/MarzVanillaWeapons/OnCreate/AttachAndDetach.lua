require("GunworksUtils/GunworksAttachAndDetach")

MarzVanillaGuns_AttachAndDetach = Gunworks_AttachAndDetach

local Check = Gunworks_AttachAndDetach.Check

Gunworks_AttachAndDetach.RegisterPartTools({
    ["Muzzle"]    = { Check.Wrench },
    ["Canon"]     = { Check.Screwdriver },
    ["Scope"]     = { Check.Screwdriver },
    ["Sling"]     = { Check.Screwdriver },
    ["RecoilPad"] = { Check.Screwdriver },
    ["Barrel"]    = { Check.Wrench, Check.Screwdriver },
})
