local GTR = require("gtr_options")

if not GTR then
  print("GTR Table NOT FOUND")
  return
end

GTR.days      = 0
GTR.hours     = 0
GTR.hoursDec  = 0
GTR.hoursPct  = 0
GTR.debug     = false

function GTR:_output(str)
  HaloTextHelper.addText(getPlayer(), tostring(str))
end

function GTR:_hasReqElecLvl()
  local minLevel  = self.Options.ReqElecLvl
  if minLevel == 0 then
    return true
  else
    return getPlayer():getPerkLevel(Perks.Electrical) >= minLevel
  end
end

function GTR:_getDayLength()
  return getSandboxOptions():getDayLengthMinutes()
end

function GTR:_convertToRT()
  local realTime  = 60 * 24
  local dayLength = self:_getDayLength()

  if dayLength ~= realTime then
    local hoursRT = self.hoursDec / 24 * dayLength / 60
    self.hoursDec = hoursRT
  end
end

function GTR:_getFuelMultiplier()
  return getSandboxOptions():getOptionByName("GeneratorFuelConsumption"):getValue()
end

function GTR:_getFuelConsumption(generator)
  return luautils.round(generator:getTotalPowerUsing(), 2) * self:_getFuelMultiplier()
end

function GTR:_calcFuelLeft(generator, fuel)
  local fuelConsumption = self:_getFuelConsumption(generator)
  self.hoursDec         = 100 / fuelConsumption * (fuel / 100)

  if self.Options.ConvertToRT then
    self:_convertToRT()
  end

  self.hours            = math.floor(self.hoursDec)
  self.days             = math.floor(self.hours / 24)

  if self.days >= 1 then
    self.hours = self.hours % 24
  end

  -- Hours per fuelPct. Maybe use in future
  if self.debug then
    self.hoursPct = math.floor(100 / fuelConsumption * ((fuel + 1) / 100) - self.hoursDec)
  end
end

function GTR:toString(generator, fuel)
  local isNotActive = not generator:isActivated()

  if isNotActive or not self:_hasReqElecLvl() then
    return ""
  end

  self:_calcFuelLeft(generator, fuel)

  local str = ""
  --#region New format and switch-case
  if self.days > 1 then
    if self.hours > 1 then
      str = string.format(
        " (%.0f %s, %.0f %s)",
        self.days, getText("Tooltip_GTR_Days"),
        self.hours, getText("Tooltip_GTR_Hours")
      )
    elseif self.hours == 1 then
      str = string.format(
        " (%.0f %s, %.0f %s)",
        self.days, getText("Tooltip_GTR_Days"),
        self.hours, getText("Tooltip_GTR_Hour")
      )
    else
      str = string.format(
        " (%.0f %s)",
        self.days, getText("Tooltip_GTR_Days")
      )
    end
  elseif self.days == 1 then
    if self.hours > 1 then
      str = string.format(
        " (%.0f %s, %.0f %s)",
        self.days, getText("Tooltip_GTR_Day"),
        self.hours, getText("Tooltip_GTR_Hours")
      )
    elseif self.hours == 1 then
      str = string.format(
        " (%.0f %s, %.0f %s)",
        self.days, getText("Tooltip_GTR_Day"),
        self.hours, getText("Tooltip_GTR_Hour")
      )
    else
      str = string.format(
        " (%.0f %s)",
        self.days, getText("Tooltip_GTR_Day")
      )
    end
  else
    if self.hours > 1 then
      str = string.format(
        " (%.0f %s)",
        self.hours, getText("Tooltip_GTR_Hours")
      )
    elseif self.hours == 1 then
      str = string.format(
        " (%.0f %s)",
        self.hours, getText("Tooltip_GTR_Hour")
      )
    else
      str = string.format(
        " (%.0f %s)",
        self.hoursDec * 60, getText("Tooltip_GTR_Minutes")
      )
    end
  end
  --#endregion

  return str
end

local _orig_getRichText = ISGeneratorInfoWindow.getRichText

function ISGeneratorInfoWindow.getRichText(object, displayStats)
	local square = object:getSquare()
	if not displayStats then
		local text = " <INDENT:10> "
		if square and not square:isOutside() and square:getBuilding() then
			text = text .. " <RED> " .. getText("IGUI_Generator_IsToxic")
		end
		return text
	end
	local fuel = math.ceil(object:getFuel())
	local condition = object:getCondition()
	-- local text = getText("IGUI_Generator_FuelAmount", fuel) .. " <LINE> " .. getText("IGUI_Generator_Condition", condition) .. " <LINE> "
  local fuelLeft  = GTR:toString(object, fuel)
	local text = getText("IGUI_Generator_FuelAmount", fuel) .. fuelLeft .. " <LINE> " .. getText("IGUI_Generator_Condition", condition) .. " <LINE> "
	if object:isActivated() then
		text = text ..  " <LINE> " .. getText("IGUI_PowerConsumption") .. ": <LINE> ";
		text = text .. " <INDENT:10> "
		local items = object:getItemsPowered()
		for i=0,items:size()-1 do
			text = text .. "   " .. items:get(i) .. " <LINE> ";
		end
		text = text .. getText("IGUI_Total") .. ": " .. luautils.round(object:getTotalPowerUsing(), 2) .. " L/h <LINE> ";
	end
	if square and not square:isOutside() and square:getBuilding() then
		text = text .. " <LINE> <RED> " .. getText("IGUI_Generator_IsToxic")
	end
	return text
end