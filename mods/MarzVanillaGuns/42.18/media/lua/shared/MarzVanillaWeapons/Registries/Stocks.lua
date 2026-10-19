local FoldingStock = require("WeaponSystems/Utils/FoldingStock")

FoldingStock.RegisterMultipleWeapons({
    ["Base.JS5_smg"] = {
        attachments = {
            partType = "StockIntegrated",
            folded   = "Base.JS5_Stock_Folded",
            deployed = "Base.JS5_Stock_Deployed",
        },
        initialState = "folded",
    },
})
