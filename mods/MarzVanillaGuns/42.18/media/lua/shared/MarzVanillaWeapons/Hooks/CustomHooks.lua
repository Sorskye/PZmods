require("TimedActions/ISReloadWeaponAction")
require("TimedActions/ISUpgradeWeapon")
require("TimedActions/ISRemoveWeaponUpgrade")

local ISReloadWeaponAction_canShoot = ISReloadWeaponAction.canShoot

ISReloadWeaponAction.canShoot = function(player, weapon)
    if weapon:getFullType() == "Base.Side_By_Side" then
        local barrel = weapon:getWeaponPart("Barrel")
        if not barrel then return false end
    end
    return ISReloadWeaponAction_canShoot(player, weapon);
end

local ISUpgradeWeapon_complete = ISUpgradeWeapon.complete
function ISUpgradeWeapon:complete()
    local part = self.part
    local toReplace = false
    local newPart = nil
    if part:getPartType() == "Barrel" then
        local fullType = part:getFullType()
        if fullType:sub(-5) == "_Open" then
            toReplace = true
            local closedFullType = fullType:sub(1, -6) .. "_Close"
            newPart = instanceItem(closedFullType)
        end
    end

    ISUpgradeWeapon_complete(self)

    if toReplace then
        self.weapon:attachWeaponPart(self.character, newPart)
    end
end
