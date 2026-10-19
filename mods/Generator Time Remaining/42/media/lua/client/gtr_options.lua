local GTR = {}

GTR.Options = {
  ReqElecLvl    = 0,
  ConvertToRT  = false
}

if Mod.IsMCMInstalled_v1 then
  local MyModOptions = ModOptionTable:New(
    "GeneratorTimeRemaining",
    "Generator Time Remaining",
    false
  )

  MyModOptions:AddModOption(
    "ReqElecLvl", "number_slider",
    GTR.Options.ReqElecLvl, { min = 0, max = 10, step = 1},
    getText("UI_GTR_Options_ReqLevel"), nil,
    function(value) GTR.Options.ReqElecLvl  = value end
  )

  MyModOptions:AddModOption(
    "ConvertToIRL", "checkbox",
    GTR.Options.ConvertToRT, nil,
    getText("UI_GTR_Options_Convert"), nil,
    function(value) GTR.Options.ConvertToRT  = value end
  )
end

return GTR