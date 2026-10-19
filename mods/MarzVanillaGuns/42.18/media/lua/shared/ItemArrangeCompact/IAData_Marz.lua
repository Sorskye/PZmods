local function init()
    if IA then
        IA.arrangables["Base.762Box"] = IA.arrangableProfile.ammoBox
        IA.arrangables["Base.762Carton"] = IA.arrangableProfile.ammoCarton
    end
end

Events.OnInitGlobalModData.Add(init)
