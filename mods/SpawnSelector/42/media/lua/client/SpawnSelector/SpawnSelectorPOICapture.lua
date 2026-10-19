require "ISUI/ISContextMenu"
require "ISUI/ISTextBox"
require "ISUI/Maps/ISWorldMap"
require "SpawnSelector/SpawnSelectorPOIs"

local POICapture = {}

local GROUPS = {
    { labelKey = "IGUI_Map_Community", types = {
        { id = "police_station", labelKey = "IGUI_PoliceKey", group = "publicServices" },
        { id = "state_police_station", labelKey = "IGUI_PoliceStateKey", group = "publicServices" },
        { id = "fire_station", labelKey = "IGUI_FireDeptKey", group = "publicServices" },
        { id = "prison", labelKey = "IGUI_PrisonKey", group = "publicServices" },
        { id = "post_office", labelKey = "IGUI_postKey", group = "publicServices" },
        { id = "office", labelKey = "IGUI_officeKey", group = "publicServices" },
    } },
    { labelKey = "IGUI_Map_Medical", types = {
        { id = "hospital", labelKey = "IGUI_hospitalroomKey", group = "medical" },
        { id = "clinic", labelKey = "IGUI_DoctorKey", group = "medical" },
        { id = "pharmacy", labelKey = "IGUI_PharmacyKey", group = "medical" },
        { id = "dentist", labelKey = "IGUI_DentistKey", group = "medical" },
        { id = "optometrist", labelKey = "IGUI_optometristKey", group = "medical" },
        { id = "nursing_home", labelKey = "IGUI_NursingHomeKey", group = "medical" },
    } },
    { labelKey = "IGUI_Map_Industrial", types = {
        { id = "fuel_station", labelKey = "IGUI_gasstoreKey", fallbackKey = "POITypeFuelStation", group = "transport" },
        { id = "vehicle_repair", labelKey = "IGUI_CarRepairKey", group = "transport" },
        { id = "vehicle_dealership", labelKey = "IGUI_NolansUsedCarsKey", group = "transport" },
        { id = "auto_parts_store", labelKey = "UI_SpawnSelector_POITypeAutoPartsStore", group = "transport" },
        { id = "warehouse", labelKey = "IGUI_warehouseKey", group = "industrial" },
        { id = "factory", labelKey = "IGUI_FactoryKey", group = "industrial" },
        { id = "construction_site", labelKey = "IGUI_ConstructionSiteKey", group = "industrial" },
        { id = "metal_shop", labelKey = "IGUI_metalshopKey", group = "industrial" },
        { id = "farm", labelKey = "IGUI_FarmKey", group = "industrial" },
        { id = "barn", labelKey = "IGUI_RanchKey", group = "industrial" },
    } },
    { labelKey = "IGUI_Map_RestaurantsEntertainment", types = {
        { id = "restaurant", labelKey = "IGUI_RestaurantKey", group = "food" },
        { id = "diner", labelKey = "IGUI_DinnerKey", group = "food" },
        { id = "cafe", labelKey = "IGUI_cafeKey", group = "food" },
        { id = "coffee_shop", labelKey = "IGUI_CoffeeshopKey", group = "food" },
        { id = "bakery", labelKey = "IGUI_bakeryKey", group = "food" },
        { id = "bar", labelKey = "IGUI_BarKey", group = "food" },
        { id = "butcher", labelKey = "IGUI_butcherKey", group = "food" },
        { id = "ice_cream_shop", labelKey = "IGUI_icecreamKey", group = "food" },
        { id = "donut_shop", labelKey = "IGUI_donut_Key", group = "food" },
        { id = "candy_store", labelKey = "UI_SpawnSelector_POITypeCandyStore", group = "food" },
    } },
    { labelKey = "IGUI_Map_RetailCommercial", types = {
        { id = "gun_store", labelKey = "IGUI_gunstoreKey", group = "retail" },
        { id = "grocery_store", labelKey = "IGUI_groceryKey", group = "food" },
        { id = "convenience_store", labelKey = "IGUI_conveniencestoreKey", group = "food" },
        { id = "department_store", labelKey = "IGUI_departmentstoreKey", fallbackKey = "POITypeDepartmentStore", group = "retail" },
        { id = "general_store", labelKey = "IGUI_generalstoreKey", group = "retail" },
        { id = "corner_store", labelKey = "IGUI_cornerstoreKey", group = "retail" },
        { id = "army_surplus_store", labelKey = "IGUI_armysurplusKey", group = "retail" },
        { id = "tool_store", labelKey = "IGUI_toolstoreKey", group = "retail" },
        { id = "farming_store", labelKey = "IGUI_FarmingStoreKey", group = "retail" },
        { id = "garden_store", labelKey = "IGUI_gardenstoreKey", group = "retail" },
        { id = "outdoor_supply_store", labelKey = "UI_SpawnSelector_POITypeOutdoorSupplyStore", group = "retail" },
        { id = "sporting_goods_store", labelKey = "IGUI_sportstoreKey", fallbackKey = "POITypeSportingGoodsStore", group = "retail" },
        { id = "fishing_store", labelKey = "UI_SpawnSelector_POITypeFishingStore", group = "retail" },
        { id = "baseball_store", labelKey = "IGUI_baseballstoreKey", group = "retail" },
        { id = "hair_salon", labelKey = "UI_SpawnSelector_POITypeHairSalon", group = "retail" },
        { id = "spa", labelKey = "IGUI_SpaKey", group = "retail" },
        { id = "bookstore", labelKey = "IGUI_bookstoreKey", group = "retail" },
        { id = "comic_store", labelKey = "UI_SpawnSelector_POITypeComicStore", group = "retail" },
        { id = "vhs_store", labelKey = "IGUI_movierentalKey", group = "retail" },
        { id = "music_store", labelKey = "IGUI_musicstoreKey", group = "retail" },
        { id = "camera_store", labelKey = "IGUI_camerastoreKey", group = "retail" },
        { id = "electronics_store", labelKey = "IGUI_electronicsstoreKey", fallbackKey = "POITypeElectronicsStore", group = "retail" },
        { id = "clothing_store", labelKey = "IGUI_clothingstoreKey", fallbackKey = "POITypeClothingStore", group = "retail" },
        { id = "leatherwear_store", labelKey = "IGUI_leatherclothesstoreKey", group = "retail" },
        { id = "lingerie_store", labelKey = "IGUI_lingeriestoreKey", group = "retail" },
        { id = "shoe_store", labelKey = "IGUI_shoestoreKey", group = "retail" },
        { id = "sewing_store", labelKey = "IGUI_sewingstoreKey", fallbackKey = "POITypeSewingStore", group = "retail" },
        { id = "tailor", labelKey = "IGUI_Tailor", group = "retail" },
        { id = "wedding_store", labelKey = "UI_SpawnSelector_POITypeWeddingStore", group = "retail" },
        { id = "furniture_store", labelKey = "IGUI_furniturestoreKey", fallbackKey = "POITypeFurnitureStore", group = "retail" },
        { id = "houseware_store", labelKey = "IGUI_housewarestoreKey", group = "retail" },
        { id = "kitchenware_store", labelKey = "IGUI_kitchenwaresKey", group = "retail" },
        { id = "barbecue_store", labelKey = "IGUI_barbecuestoreKey", group = "retail" },
        { id = "liquor_store", labelKey = "IGUI_liquorstoreKey", group = "retail" },
        { id = "tobacco_store", labelKey = "UI_SpawnSelector_POITypeTobaccoStore", group = "retail" },
        { id = "jewelry_store", labelKey = "IGUI_jewelrystoreKey", fallbackKey = "POITypeJewelryStore", group = "retail" },
        { id = "gift_store", labelKey = "IGUI_giftstoreKey", fallbackKey = "POITypeGiftStore", group = "retail" },
        { id = "art_store", labelKey = "IGUI_artstoreKey", group = "retail" },
        { id = "florist", labelKey = "UI_SpawnSelector_POITypeFlorist", group = "retail" },
        { id = "toy_store", labelKey = "IGUI_toystoreKey", group = "retail" },
        { id = "pet_store", labelKey = "UI_SpawnSelector_POITypePetStore", group = "retail" },
        { id = "bag_store", labelKey = "UI_SpawnSelector_POITypeBagStore", group = "retail" },
        { id = "wallet_store", labelKey = "IGUI_walletshopKey", group = "retail" },
        { id = "knife_store", labelKey = "IGUI_knifestoreKey", group = "retail" },
        { id = "paint_store", labelKey = "IGUI_paintershopKey", group = "retail" },
        { id = "masonry_supply_store", labelKey = "UI_SpawnSelector_POITypeMasonrySupplyStore", group = "retail" },
        { id = "pawnshop", labelKey = "IGUI_pawnshopKey", group = "retail" },
        { id = "clock_repair", labelKey = "UI_SpawnSelector_POITypeClockRepair", group = "retail" },
        { id = "shoe_repair", labelKey = "UI_SpawnSelector_POITypeShoeRepair", group = "retail" },
        { id = "storage_units", labelKey = "IGUI_storageunitKey", group = "retail" },
        { id = "bank", labelKey = "IGUI_BankKey", group = "retail" },
    } },
    { labelKey = "IGUI_Map_Hospitality", types = {
        { id = "hotel", labelKey = "IGUI_FancyHotelKey", group = "accommodation" },
        { id = "motel", labelKey = "IGUI_motelroomKey", group = "accommodation" },
        { id = "trailer_park", labelKey = "IGUI_TrailerParkKey", group = "accommodation" },
        { id = "shelter", labelKey = "IGUI_Shelter", group = "accommodation" },
        { id = "cabin", labelKey = "IGUI_ForestKey", group = "accommodation" },
    } },
    { labelKey = "IGUI_Map_Parks", types = {
        { id = "campground", labelKey = "IGUI_campingKey", group = "recreation" },
        { id = "golf_course", labelKey = "IGUI_GolfKey", group = "recreation" },
        { id = "gym", labelKey = "IGUI_gymKey", group = "recreation" },
        { id = "movie_theatre", labelKey = "IGUI_theatreKey", group = "recreation" },
        { id = "bowling_alley", labelKey = "IGUI_BowlingKey", group = "recreation" },
        { id = "swimming_pool", labelKey = "IGUI_SwimmingPoolKey", group = "recreation" },
        { id = "shooting_range", labelKey = "IGUI_shootingrangeKey", group = "recreation" },
        { id = "art_gallery", labelKey = "IGUI_Gallery", group = "recreation" },
    } },
    { labelKey = "IGUI_SchoolKey", types = {
        { id = "school", labelKey = "IGUI_SchoolKey", group = "community" },
        { id = "library", labelKey = "IGUI_libraryKey", group = "community" },
        { id = "church", labelKey = "IGUI_churchKey", group = "community" },
    } },
    { labelKey = "IGUI_ArmyKey", types = {
        { id = "military_site", labelKey = "IGUI_ArmyKey", group = "restricted" },
        { id = "army_hangar", labelKey = "IGUI_armyhangerKey", group = "restricted" },
        { id = "laboratory", labelKey = "IGUI_laboratoryKey", group = "restricted" },
        { id = "secret_base", labelKey = "IGUI_SecretBaseKey", group = "restricted" },
    } },
}

local COLOURS = {
    publicServices = { r = 0.16, g = 0.48, b = 0.92 },
    medical = { r = 0.90, g = 0.20, b = 0.25 },
    transport = { r = 0.95, g = 0.52, b = 0.12 },
    food = { r = 0.25, g = 0.70, b = 0.30 },
    retail = { r = 0.65, g = 0.35, b = 0.85 },
    industrial = { r = 0.55, g = 0.38, b = 0.22 },
    accommodation = { r = 0.10, g = 0.70, b = 0.75 },
    community = { r = 0.95, g = 0.78, b = 0.15 },
    recreation = { r = 0.45, g = 0.75, b = 0.18 },
    restricted = { r = 0.25, g = 0.25, b = 0.25 },
    landmark = { r = 0.95, g = 0.82, b = 0.20 },
}

local captured = {}
local circleTexture = nil
local showMappedPOIs = false

local function tr(key, ...)
    return getText("UI_SpawnSelector_" .. key, ...):gsub("<LINE>", "\n")
end

local function typeLabel(poiType)
    local label = getText(poiType.labelKey)
    if label == poiType.labelKey and poiType.fallbackKey then
        return tr(poiType.fallbackKey)
    end
    return label
end

local function jsonString(value)
    local escaped = tostring(value or ""):gsub("\\", "\\\\"):gsub('"', '\\"')
        :gsub("\r", "\\r"):gsub("\n", "\\n"):gsub("\t", "\\t")
    return '"' .. escaped .. '"'
end

local function roomCentreAt(worldX, worldY, z)
    local metaGrid = getWorld() and getWorld():getMetaGrid()
    local tileX, tileY = math.floor(worldX), math.floor(worldY)
    local building = metaGrid and metaGrid:getBuildingAt(tileX, tileY, z or 0)
    if not building then return nil, nil end

    local rooms = building:getRooms()
    for i = 0, rooms:size() - 1 do
        local room = rooms:get(i)
        if room:isInside(tileX, tileY, z or 0) then
            local rects = room:getRects()
            local weightedX, weightedY, totalArea = 0, 0, 0
            for rectIndex = 0, rects:size() - 1 do
                local rect = rects:get(rectIndex)
                local area = rect:getW() * rect:getH()
                weightedX = weightedX + (rect:getX() + rect:getW() / 2) * area
                weightedY = weightedY + (rect:getY() + rect:getH() / 2) * area
                totalArea = totalArea + area
            end
            if totalArea > 0 then
                return weightedX / totalArea, weightedY / totalArea
            end
            return room:getX() + room:getW() / 2, room:getY() + room:getH() / 2
        end
    end
    return nil, nil
end

local function buildingCentreAt(worldX, worldY, z)
    local metaGrid = getWorld() and getWorld():getMetaGrid()
    local tileX, tileY = math.floor(worldX), math.floor(worldY)
    local building = metaGrid and metaGrid:getBuildingAt(tileX, tileY, z or 0)
    if not building then return nil, nil end

    local weightedX, weightedY, totalArea = 0, 0, 0
    local rooms = building:getRooms()
    for roomIndex = 0, rooms:size() - 1 do
        local rects = rooms:get(roomIndex):getRects()
        for rectIndex = 0, rects:size() - 1 do
            local rect = rects:get(rectIndex)
            local area = rect:getW() * rect:getH()
            weightedX = weightedX + (rect:getX() + rect:getW() / 2) * area
            weightedY = weightedY + (rect:getY() + rect:getH() / 2) * area
            totalArea = totalArea + area
        end
    end
    if totalArea > 0 then return weightedX / totalArea, weightedY / totalArea end
    return building:getX() + building:getW() / 2, building:getY() + building:getH() / 2
end

local function capturePosition(mapAPI, uiX, uiY, placement)
    local worldX, worldY = mapAPI:uiToWorldX(uiX, uiY), mapAPI:uiToWorldY(uiX, uiY)
    local centreX, centreY
    if placement == "building" then
        centreX, centreY = buildingCentreAt(worldX, worldY, 0)
    else
        centreX, centreY = roomCentreAt(worldX, worldY, 0)
    end
    if centreX then return centreX, centreY end
    return math.floor(worldX * 100 + 0.5) / 100, math.floor(worldY * 100 + 0.5) / 100
end

local function openPrompt(target, prompt, capture, callback, multipleLines, required)
    local width = 420
    local height = multipleLines and 220 or 180
    local modal = ISTextBox:new((getCore():getScreenWidth() - width) / 2,
        (getCore():getScreenHeight() - height) / 2, width, height, prompt, "",
        target, callback, target.playerNum or 0, capture)
    if multipleLines then
        modal:setMultipleLine(true)
        modal:setNumberOfLines(3)
        modal:setMaxLines(3)
    end
    modal.noEmpty = required == true
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
end

function POICapture:start(poiType, x, y, placement)
    local worldX, worldY = capturePosition(self.mapAPI, x, y, placement)
    local capture = { type = poiType.id, typeLabel = typeLabel(poiType), group = poiType.group,
        custom = poiType.custom == true, placement = placement,
        x = worldX, y = worldY, z = 0 }
    local prompt = capture.custom and tr("CustomPOINamePrompt") or tr("POINamePrompt")
    openPrompt(self, prompt, capture, POICapture.onName, false, capture.custom)
end

function POICapture:onName(button, capture)
    if button.internal ~= "OK" then return end
    capture.name = button.parent.entry:getText()
    if capture.custom then
        capture.typeLabel = capture.name
    end
    openPrompt(self, tr("POILocationPrompt"), capture, POICapture.onLocation)
end

function POICapture:onLocation(button, capture)
    if button.internal ~= "OK" then return end
    capture.location = button.parent.entry:getText()
    openPrompt(self, tr("POINotesPrompt"), capture, POICapture.onNotes, true)
end

function POICapture:onNotes(button, capture)
    if button.internal ~= "OK" then return end
    capture.notes = button.parent.entry:getText()
    table.insert(captured, capture)
    local record = '{"type":' .. jsonString(capture.type) .. ',"typeLabel":' .. jsonString(capture.typeLabel)
        .. ',"group":' .. jsonString(capture.group) .. ',"name":' .. jsonString(capture.name)
        .. ',"location":' .. jsonString(capture.location) .. ',"x":' .. capture.x .. ',"y":' .. capture.y
        .. ',"z":0,"placement":' .. jsonString(capture.placement)
        .. ',"notes":' .. jsonString(capture.notes) .. ',"build":"42.20"}'
    print("[SpawnSelectorPOI] " .. record)
    print("[SpawnSelector] " .. tr("POIRecorded", capture.x, capture.y, 0))
end

local function toggleMappedPOIs()
    showMappedPOIs = not showMappedPOIs
end

local originalRightMouseUp = ISWorldMap.onRightMouseUp

local function addPOITypes(context, parentMenu, map, x, y, placement)
    parentMenu:addOption(tr("CustomPOI"), map, POICapture.start,
        { id = "custom_poi", labelKey = "UI_SpawnSelector_CustomPOI", group = "landmark", custom = true },
        x, y, placement)
    for _, group in ipairs(GROUPS) do
        local groupMenu = context:getNew(context)
        for _, poiType in ipairs(group.types) do
            groupMenu:addOption(typeLabel(poiType), map, POICapture.start, poiType, x, y, placement)
        end
        local groupOption = parentMenu:addOption(getText(group.labelKey), nil, nil)
        parentMenu:addSubMenu(groupOption, groupMenu)
    end
end

function ISWorldMap:onRightMouseUp(x, y)
    local handled = originalRightMouseUp(self, x, y)
    if not isDebugEnabled() then return handled end
    local playerNum = self.playerNum or 0
    local context = getPlayerContextMenu(playerNum)
    if not context or not context:getIsVisible() or context.numOptions == 0 then
        context = ISContextMenu.get(playerNum, x + self:getAbsoluteX(), y + self:getAbsoluteY())
    end
    local placementMenu = context:getNew(context)
    local roomMenu = context:getNew(context)
    addPOITypes(context, roomMenu, self, x, y, "room")
    local roomOption = placementMenu:addOption(tr("POIRoomCentre"), nil, nil)
    placementMenu:addSubMenu(roomOption, roomMenu)
    local buildingMenu = context:getNew(context)
    addPOITypes(context, buildingMenu, self, x, y, "building")
    local buildingOption = placementMenu:addOption(tr("POIBuildingCentre"), nil, nil)
    placementMenu:addSubMenu(buildingOption, buildingMenu)
    local option = context:addOption(tr("AddPOI"), nil, nil)
    context:addSubMenu(option, placementMenu)
    option = context:addOption(tr("ShowMappedPOIs"), nil, toggleMappedPOIs)
    context:setOptionChecked(option, showMappedPOIs)
    return true
end

local originalRender = ISWorldMap.render
function ISWorldMap:render()
    originalRender(self)
    if not isDebugEnabled() then return end
    circleTexture = circleTexture or getTexture("media/ui/circle.png")
    if not circleTexture then return end
    local function drawEntries(entries)
        for _, poi in ipairs(entries) do
            local x, y = self.mapAPI:worldToUIX(poi.x, poi.y), self.mapAPI:worldToUIY(poi.x, poi.y)
            if x >= -8 and x <= self.width + 8 and y >= -8 and y <= self.height + 8 then
                local colour = COLOURS[poi.group] or COLOURS.retail
                self:drawTextureScaled(circleTexture, x - 8, y - 8, 16, 16, 0.95, 0.05, 0.05, 0.05)
                self:drawTextureScaled(circleTexture, x - 6, y - 6, 12, 12, 1, colour.r, colour.g, colour.b)
            end
        end
    end
    if showMappedPOIs then
        drawEntries(SpawnSelectorPOIs.entries)
    end
    drawEntries(captured)
end
