require "ISUI/ISPanel"
require "ISUI/ISButton"
require "ISUI/ISModalDialog"
require "ISUI/ISLabel"
require "ISUI/ISTextEntryBox"
require "ISUI/Maps/ISMapDefinitions"
require "ISUI/Maps/ISWorldMapKey"
require "OptionScreens/MapsOrder"
require "SpawnSelector/SpawnSelectorRegions"
require "SpawnSelector/SpawnSelectorPOIs"

SpawnSelectorUI = ISPanel:derive("SpawnSelectorUI")

local MODULE = "SpawnSelector"
local BUTTON_HEIGHT = 32
local MARGIN = 16
local COORDINATE_PANEL_WIDTH = 220
local COORDINATE_PANEL_HEIGHT = 156
local COORDINATE_ANIMATION_MS = 180
local KEY_PANEL_NAMES = {
    "Community",
    "Hospitality",
    "Industrial",
    "Medical",
    "Parks",
    "Residential",
    "RestaurantsEntertainment",
    "RetailCommercial",
}
local KEY_FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local KEY_FONT_HGT_MEDIUM = getTextManager():getFontHeight(UIFont.Medium)
local KEY_ROW_SPACING = 10
local KEY_ROW_HGT = math.max(KEY_FONT_HGT_SMALL + 6, 32)
local KEY_ICON_WIDTH = math.max(KEY_FONT_HGT_SMALL + 6, 32) * 2
local KEY_PANEL_HEIGHT = KEY_FONT_HGT_MEDIUM
    + KEY_ROW_SPACING * 2
    + 1
    + #KEY_PANEL_NAMES * (KEY_ROW_HGT + KEY_ROW_SPACING)
    + 1
local KEY_PANEL_WIDTH = 0
for _, keyName in ipairs(KEY_PANEL_NAMES) do
    local labelWidth = getTextManager():MeasureStringX(UIFont.Medium, "IGUI_Map_" .. keyName)
    KEY_PANEL_WIDTH = math.max(KEY_PANEL_WIDTH, (KEY_ROW_SPACING + 1) * 2 + KEY_ICON_WIDTH + labelWidth)
end
local pendingLocalSpawn = nil
local pendingServerCandidate = nil
local safetyTick = 0
local disableBuildingAlarmAt
local clearNearbyZombies
local localArrivalSafety = nil
local layerWarningShown = false
local PROJECT_INDIANA_MOD_ID = "PIE42"
local PROJECT_INDIANA_MAP_DIRECTORY = "PIElots"

local function tr(key, ...)
    local text = getText("UI_SpawnSelector_" .. key, ...)
    local normalized = text:gsub("<LINE>", "\n")
    return normalized
end

local function isProjectIndianaActive()
    return getActivatedMods():contains(PROJECT_INDIANA_MOD_ID)
end

local function clearTemporaryMapKnowledge(player)
    if WorldMapVisited then
        WorldMapVisited.getInstance():forget()
    end
    if isClient() then
        sendClientCommand(player, "map", "forget", {})
    end
end

for index = #MapsOrder, 1, -1 do
    if MapsOrder[index] == SpawnSelector.REGION_NAME then
        table.remove(MapsOrder, index)
    end
end
table.insert(MapsOrder, 1, SpawnSelector.REGION_NAME)

local TOWN_LABELS = {
    { key = "MapLabel_WestPoint", x = 11654, y = 6864 },
    { key = "MapLabel_Riverside", x = 6450, y = 5430 },
    { key = "MapLabel_Muldraugh", x = 10754, y = 9926 },
    { key = "MapLabel_Brandenburg", x = 2056, y = 6070 },
    { key = "MapLabel_Ekron", x = 634, y = 9746 },
    { key = "MapLabel_Irvington", x = 2427, y = 14185 },
    { key = "MapLabel_EchoCreek", x = 3589, y = 10952 },
    { key = "MapLabel_Louisville", x = 13077, y = 2238 },
    { key = "MapLabel_MarchRidge", x = 10130, y = 12801 },
    { key = "MapLabel_FallasLake", x = 7253, y = 8279 },
    { key = "MapLabel_Rosewood", x = 8159, y = 11661 },
    { key = "MapLabel_ValleyStation", x = 13447, y = 5278 },
}

SpawnSelectorMap = ISUIElement:derive("SpawnSelectorMap")

function SpawnSelectorMap:instantiate()
    self.javaObject = UIWorldMap.new(self)
    self.mapAPI = self.javaObject:getAPIv3()
    self.mapAPI:setBoolean("ClampBaseZoomToPoint5", false)
    self.mapAPI:setBoolean("DebugInfo", false)
    self.mapAPI:setBoolean("ImagePyramid", false)
    self.mapAPI:setBoolean("InfiniteZoom", true)
    self.mapAPI:setBoolean("Isometric", false)
    self.javaObject:setX(self.x)
    self.javaObject:setY(self.y)
    self.javaObject:setWidth(self.width)
    self.javaObject:setHeight(self.height)
    self.javaObject:setAnchorLeft(true)
    self.javaObject:setAnchorRight(true)
    self.javaObject:setAnchorTop(true)
    self.javaObject:setAnchorBottom(true)
end

function SpawnSelectorMap:prerender()
    ISUIElement.prerender(self)
    if self.ready or self.mapAPI:getDataCount() == 0 or not self.mapAPI:isDataLoaded() then
        return
    end

    self.ready = true
    MapUtils.initDefaultStyleV1(self)
    MapUtils.overlayPaper(self)
    self.mapAPI:setBoundsFromData()
    self.mapAPI:resetView()
    if self.parent.randomButton then
        self.parent.randomButton:setEnable(true)
    end
    if self.parent.randomBuildingButton then
        self.parent.randomBuildingButton:setEnable(true)
    end
end

local DEATH_ZONE_SEGMENTS = 48
local deathZoneSkullTexture = nil
local TOWN_LABEL_MAX_ZOOM = 13.5
-- POIs replace broad town labels as the player zooms in.
local POI_MIN_ZOOM = 13.6
local POI_MARKER_RADIUS = 8
local POI_HIT_RADIUS = 11
local poiCircleTexture = nil
local poiCircleTextureResolved = false
local POI_GROUP_COLOURS = {
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

function SpawnSelectorMap:drawTownLabels()
    if self.mapAPI:getZoomF() > TOWN_LABEL_MAX_ZOOM then
        return
    end

    for _, town in ipairs(TOWN_LABELS) do
        local x = self.mapAPI:worldToUIX(town.x, town.y)
        local y = self.mapAPI:worldToUIY(town.x, town.y)
        if x >= -200 and x <= self.width + 200 and y >= -30 and y <= self.height + 30 then
            local label = getText(town.key)
            self:drawTextCentre(label, x, y, 0.05, 0.05, 0.05, 1, UIFont.Medium)
        end
    end
end

local function drawPOIMarker(map, x, y, colour)
    if not poiCircleTextureResolved then
        poiCircleTextureResolved = true
        poiCircleTexture = getTexture("media/ui/circle.png")
    end
    if not poiCircleTexture then
        return
    end

    local outerSize = POI_MARKER_RADIUS * 2
    local innerSize = outerSize - 4
    map:drawTextureScaled(poiCircleTexture, x - POI_MARKER_RADIUS, y - POI_MARKER_RADIUS,
        outerSize, outerSize, 0.95, 0.05, 0.05, 0.05)
    map:drawTextureScaled(poiCircleTexture, x - innerSize / 2, y - innerSize / 2,
        innerSize, innerSize, 1.00, colour.r, colour.g, colour.b)
end

local poiResolvedPositions = {}

local function resolvePOIPosition(poi)
    if poi.placement then return poi.x, poi.y end
    local cached = poiResolvedPositions[poi]
    if cached then return cached.x, cached.y end

    local resolvedX, resolvedY = poi.x, poi.y
    local metaGrid = getWorld() and getWorld():getMetaGrid()
    local tileX, tileY = math.floor(poi.x), math.floor(poi.y)
    local building = metaGrid and metaGrid:getBuildingAt(tileX, tileY, poi.z or 0)
    if building then
        local rooms = building:getRooms()
        for i = 0, rooms:size() - 1 do
            local room = rooms:get(i)
            if room:isInside(tileX, tileY, poi.z or 0) then
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
                    resolvedX = weightedX / totalArea
                    resolvedY = weightedY / totalArea
                else
                    resolvedX = room:getX() + room:getW() / 2
                    resolvedY = room:getY() + room:getH() / 2
                end
                break
            end
        end
    end

    cached = { x = resolvedX, y = resolvedY }
    poiResolvedPositions[poi] = cached
    return cached.x, cached.y
end

function SpawnSelectorMap:drawPOIs()
    if SandboxVars.SpawnSelector and SandboxVars.SpawnSelector.ShowPOIs == false then
        return
    end
    if not self.parent.poiVisible or self.mapAPI:getZoomF() < POI_MIN_ZOOM then
        return
    end

    local mouseX, mouseY = self:getMouseX(), self:getMouseY()
    local hovered = nil
    for _, poi in ipairs(SpawnSelectorPOIs.entries) do
        local x = self.mapAPI:worldToUIX(poi.x, poi.y)
        local y = self.mapAPI:worldToUIY(poi.x, poi.y)
        -- Resolve building geometry only for nearby markers. This keeps the first
        -- POI frame cheap even after the catalogue grows to hundreds of entries.
        if x >= -64 and x <= self.width + 64 and y >= -64 and y <= self.height + 64 then
            local worldX, worldY = resolvePOIPosition(poi)
            x = self.mapAPI:worldToUIX(worldX, worldY)
            y = self.mapAPI:worldToUIY(worldX, worldY)
        end
        if x >= -POI_MARKER_RADIUS and x <= self.width + POI_MARKER_RADIUS
            and y >= -POI_MARKER_RADIUS and y <= self.height + POI_MARKER_RADIUS then
            drawPOIMarker(self, x, y, POI_GROUP_COLOURS[poi.group] or POI_GROUP_COLOURS.retail)
            local distanceX, distanceY = mouseX - x, mouseY - y
            if distanceX * distanceX + distanceY * distanceY <= POI_HIT_RADIUS * POI_HIT_RADIUS then
                hovered = poi
            end
        end
    end

    if hovered then
        local typeName = hovered.type == "custom_poi" and hovered.name or getText(hovered.labelKey)
        local label = hovered.location .. " - " .. typeName
        local textWidth = getTextManager():MeasureStringX(UIFont.Small, label)
        local tooltipX = math.max(4, math.min(self.width - textWidth - 18, mouseX + 16))
        local tooltipY = math.max(4, math.min(self.height - 30, mouseY + 16))
        self:drawRect(tooltipX, tooltipY, textWidth + 14, 24, 0.94, 0.03, 0.03, 0.03)
        self:drawRectBorder(tooltipX, tooltipY, textWidth + 14, 24, 1, 0.75, 0.75, 0.75)
        self:drawText(label, tooltipX + 7, tooltipY + 4, 1, 1, 1, 1, UIFont.Small)
    end
end

function SpawnSelectorMap:drawDeathZone(zone)
    local centerX = self.mapAPI:worldToUIX(zone.x, zone.y)
    local centerY = self.mapAPI:worldToUIY(zone.x, zone.y)
    local edgeX = self.mapAPI:worldToUIX(zone.x + zone.radius, zone.y)
    local pixelRadius = math.abs(edgeX - centerX)
    if pixelRadius < 1 then
        return
    end

    local previousX, previousY = nil, nil
    for index = 0, DEATH_ZONE_SEGMENTS do
        local angle = (index / DEATH_ZONE_SEGMENTS) * math.pi * 2
        local pointX = centerX + math.cos(angle) * pixelRadius
        local pointY = centerY + math.sin(angle) * pixelRadius
        if previousX then
            self:drawPolygon(nil, centerX, centerY, previousX, previousY, pointX, pointY, centerX, centerY, 0.9, 0.15, 0.15, 0.18)
            self:drawLine(nil, previousX, previousY, pointX, pointY, 2, 0.85, 0.9, 0.15, 0.15)
        end
        previousX, previousY = pointX, pointY
    end

    if not deathZoneSkullTexture then
        deathZoneSkullTexture = getTexture("media/ui/Moodles/64/Mood_Dead.png")
    end
    if deathZoneSkullTexture then
        local iconSize = 24
        self:drawTextureScaled(
            deathZoneSkullTexture,
            centerX - iconSize / 2,
            centerY - iconSize / 2,
            iconSize,
            iconSize,
            1, 1, 1, 1
        )
    end
end

function SpawnSelectorMap:render()
    ISUIElement.render(self)

    self:drawTownLabels()
    self:drawPOIs()

    if self.parent.deathZones then
        for _, zone in ipairs(self.parent.deathZones) do
            self:drawDeathZone(zone)
        end
    end

    if not self.parent.selectedX then
        return
    end

    local markerX = self.mapAPI:worldToUIX(self.parent.selectedX, self.parent.selectedY)
    local markerY = self.mapAPI:worldToUIY(self.parent.selectedX, self.parent.selectedY)
    self:drawRect(markerX - 6, markerY - 6, 12, 12, 0.9, 0.85, 0.1, 0.1)
    self:drawRectBorder(markerX - 7, markerY - 7, 14, 14, 1, 1, 1, 1)
end

function SpawnSelectorMap:onMouseDown(x, y)
    self.dragging = true
    self.dragMoved = false
    self.dragStartX = x
    self.dragStartY = y
    self.dragStartCX = self.mapAPI:getCenterWorldX()
    self.dragStartCY = self.mapAPI:getCenterWorldY()
    self.dragStartZoomF = self.mapAPI:getZoomF()
    self.dragStartWorldX = self.mapAPI:uiToWorldX(x, y)
    self.dragStartWorldY = self.mapAPI:uiToWorldY(x, y)
    return true
end

function SpawnSelectorMap:onMouseMove(dx, dy)
    if not self.dragging then
        return true
    end

    local mouseX = self:getMouseX()
    local mouseY = self:getMouseY()
    if not self.dragMoved and math.abs(mouseX - self.dragStartX) <= 4 and math.abs(mouseY - self.dragStartY) <= 4 then
        return true
    end

    self.dragMoved = true
    local worldX = self.mapAPI:uiToWorldX(mouseX, mouseY, self.dragStartZoomF, self.dragStartCX, self.dragStartCY)
    local worldY = self.mapAPI:uiToWorldY(mouseX, mouseY, self.dragStartZoomF, self.dragStartCX, self.dragStartCY)
    self.mapAPI:centerOn(
        self.dragStartCX + self.dragStartWorldX - worldX,
        self.dragStartCY + self.dragStartWorldY - worldY
    )
    return true
end

function SpawnSelectorMap:onMouseMoveOutside(dx, dy)
    return self:onMouseMove(dx, dy)
end

function SpawnSelectorMap:onMouseUp(x, y)
    self.dragging = false
    if not self.dragMoved then
        self.parent:setSelectedPosition(
            math.floor(self.mapAPI:uiToWorldX(x, y)),
            math.floor(self.mapAPI:uiToWorldY(x, y))
        )
    end
    return true
end

function SpawnSelectorMap:onMouseUpOutside(x, y)
    self.dragging = false
    return true
end

function SpawnSelectorMap:onMouseWheel(delta)
    self.mapAPI:zoomAt(self:getMouseX(), self:getMouseY(), delta)
    return true
end

function SpawnSelectorMap:setDetailedView(enabled)
    local styleAPI = self.mapAPI:getStyleAPI()
    styleAPI:clear()
    self.mapAPI:setBoolean("ImagePyramid", enabled)

    if enabled then
        local pyramidLayer = styleAPI:newPyramidLayer("pyramid")
        pyramidLayer:setPyramidFileName("pyramid.zip")
        pyramidLayer:addFill(0, 255, 255, 255, 255)
        MapUtils.initDefaultTextLayersV3(self)
    else
        MapUtils.initDefaultStyleV1(self)
        MapUtils.overlayPaper(self)
    end

    self.mapAPI:setBoolean("TerrainImage", enabled)
end

function SpawnSelectorMap:new(x, y, width, height)
    return ISUIElement.new(self, x, y, width, height)
end

function SpawnSelectorUI:createChildren()
    ISPanel.createChildren(self)

    local headerHeight = 64
    local footerHeight = BUTTON_HEIGHT + MARGIN * 2

    self.map = SpawnSelectorMap:new(0, headerHeight, self.width, self.height - headerHeight - footerHeight)
    self.map:initialise()
    self.map:instantiate()
    self:addChild(self.map)

    local directories = getLotDirectories()
    local loadedDirectories = {}
    for index = 0, directories:size() - 1 do
        local directory = directories:get(index)
        MapUtils.initDirectoryMapData(self.map, "media/maps/" .. directory)
        loadedDirectories[directory] = true
    end

    if isProjectIndianaActive() and loadedDirectories[PROJECT_INDIANA_MAP_DIRECTORY] then
        self.projectIndianaActive = true
    end

    self.confirmButton = ISButton:new(
        self.width - 180 - MARGIN,
        self.height - BUTTON_HEIGHT - MARGIN,
        180,
        BUTTON_HEIGHT,
        tr("SpawnHere"),
        self,
        SpawnSelectorUI.confirmSpawn
    )
    self.confirmButton:initialise()
    self.confirmButton:instantiate()
    self.confirmButton:setEnable(false)
    self.confirmButton.anchorLeft = false
    self.confirmButton.anchorRight = true
    self.confirmButton.anchorTop = false
    self.confirmButton.anchorBottom = true
    self:addChild(self.confirmButton)

    self.viewButton = ISButton:new(
        self.confirmButton.x - 180 - MARGIN,
        self.confirmButton.y,
        180,
        BUTTON_HEIGHT,
        tr("DetailedMap"),
        self,
        SpawnSelectorUI.toggleMapView
    )
    self.viewButton:initialise()
    self.viewButton:instantiate()
    self.viewButton.anchorLeft = false
    self.viewButton.anchorRight = true
    self.viewButton.anchorTop = false
    self.viewButton.anchorBottom = true
    self:addChild(self.viewButton)

    self.randomButton = ISButton:new(
        self.viewButton.x - 180 - MARGIN,
        self.viewButton.y,
        180,
        BUTTON_HEIGHT,
        tr("RandomSpawn"),
        self,
        SpawnSelectorUI.confirmRandomSpawn
    )
    self.randomButton:initialise()
    self.randomButton:instantiate()
    self.randomButton:setEnable(false)
    self.randomButton.anchorLeft = false
    self.randomButton.anchorRight = true
    self.randomButton.anchorTop = false
    self.randomButton.anchorBottom = true
    self:addChild(self.randomButton)

    self.randomBuildingButton = ISButton:new(
        self.randomButton.x - 180 - MARGIN,
        self.randomButton.y,
        180,
        BUTTON_HEIGHT,
        tr("RandomBuilding"),
        self,
        SpawnSelectorUI.confirmRandomBuildingSpawn
    )
    self.randomBuildingButton:initialise()
    self.randomBuildingButton:instantiate()
    self.randomBuildingButton:setEnable(false)
    self.randomBuildingButton.anchorLeft = false
    self.randomBuildingButton.anchorRight = true
    self.randomBuildingButton.anchorTop = false
    self.randomBuildingButton.anchorBottom = true
    self:addChild(self.randomBuildingButton)

    local layerSize = 32
    local layerX = self.confirmButton.x + self.confirmButton.width - layerSize
    local layerDownY = self.map.y + self.map.height - MARGIN - layerSize

    self.layerUpButton = ISButton:new(
        layerX,
        layerDownY - layerSize * 2,
        layerSize,
        layerSize,
        "^",
        self,
        SpawnSelectorUI.increaseLayer
    )
    self.layerUpButton:initialise()
    self.layerUpButton:instantiate()
    self.layerUpButton.anchorLeft = false
    self.layerUpButton.anchorRight = true
    self.layerUpButton.anchorTop = false
    self.layerUpButton.anchorBottom = true
    self:addChild(self.layerUpButton)

    self.layerInfo = ISButton:new(
        layerX,
        layerDownY - layerSize,
        layerSize,
        layerSize,
        "GF",
        self,
        nil
    )
    self.layerInfo:initialise()
    self.layerInfo:instantiate()
    self.layerInfo:setEnable(false)
    self.layerInfo.anchorLeft = false
    self.layerInfo.anchorRight = true
    self.layerInfo.anchorTop = false
    self.layerInfo.anchorBottom = true
    self:addChild(self.layerInfo)

    self.layerDownButton = ISButton:new(
        layerX,
        layerDownY,
        layerSize,
        layerSize,
        "v",
        self,
        SpawnSelectorUI.decreaseLayer
    )
    self.layerDownButton:initialise()
    self.layerDownButton:instantiate()
    self.layerDownButton.anchorLeft = false
    self.layerDownButton.anchorRight = true
    self.layerDownButton.anchorTop = false
    self.layerDownButton.anchorBottom = true
    self:addChild(self.layerDownButton)

    local searchSize = 40
    self.coordinateSearchButton = ISButton:new(
        self.width - searchSize - MARGIN,
        headerHeight + MARGIN,
        searchSize,
        searchSize,
        "",
        self,
        SpawnSelectorUI.toggleCoordinateSearch
    )
    self.coordinateSearchButton:initialise()
    self.coordinateSearchButton:instantiate()
    self.coordinateSearchButton:setImage(getTexture("media/ui/Search_Icon_Off.png"))
    self.coordinateSearchButton.tooltip = tr("CoordinateTooltip")
    self.coordinateSearchButton.anchorLeft = false
    self.coordinateSearchButton.anchorRight = true
    self.coordinateSearchButton.anchorTop = true
    self.coordinateSearchButton.anchorBottom = false
    self:addChild(self.coordinateSearchButton)

    self.coordinatePanelX = self.coordinateSearchButton.x
        + self.coordinateSearchButton.width
        - COORDINATE_PANEL_WIDTH
    self.coordinatePanelY = self.coordinateSearchButton.y + self.coordinateSearchButton.height + 8

    self.coordinatePanel = ISPanel:new(
        self.coordinatePanelX,
        self.coordinatePanelY,
        COORDINATE_PANEL_WIDTH,
        0
    )
    self.coordinatePanel:initialise()
    self.coordinatePanel.backgroundColor = { r = 0.03, g = 0.03, b = 0.03, a = 0.94 }
    self.coordinatePanel.borderColor = { r = 0.7, g = 0.7, b = 0.7, a = 0.9 }
    self.coordinatePanel.onMouseDown = function()
        return true
    end
    self.coordinatePanel.onMouseUp = function()
        return true
    end
    self.coordinatePanel.onMouseMove = function()
        return true
    end
    self.coordinatePanel.onMouseWheel = function()
        return true
    end
    self.coordinatePanel:setVisible(false)
    self:addChild(self.coordinatePanel)

    local entryX = self.coordinatePanelX + 42
    local entryWidth = COORDINATE_PANEL_WIDTH - 58
    local entryHeight = 26

    self.coordinateXLabel = ISLabel:new(
        self.coordinatePanelX + 16,
        self.coordinatePanelY + 12,
        entryHeight,
        "X",
        1,
        1,
        1,
        1,
        UIFont.Small,
        true
    )
    self.coordinateXLabel:initialise()
    self:addChild(self.coordinateXLabel)

    self.coordinateYLabel = ISLabel:new(
        self.coordinatePanelX + 16,
        self.coordinatePanelY + 46,
        entryHeight,
        "Y",
        1,
        1,
        1,
        1,
        UIFont.Small,
        true
    )
    self.coordinateYLabel:initialise()
    self:addChild(self.coordinateYLabel)

    self.coordinateZLabel = ISLabel:new(
        self.coordinatePanelX + 16,
        self.coordinatePanelY + 80,
        entryHeight,
        "Z",
        1,
        1,
        1,
        1,
        UIFont.Small,
        true
    )
    self.coordinateZLabel:initialise()
    self:addChild(self.coordinateZLabel)

    self.coordinateXEntry = ISTextEntryBox:new("", entryX, self.coordinatePanelY + 12, entryWidth, entryHeight)
    self.coordinateXEntry:initialise()
    self.coordinateXEntry:instantiate()
    self.coordinateXEntry:setMaxLines(1)
    self.coordinateXEntry.onMouseDown = function(entry)
        entry:focus()
        entry:selectAll()
        return true
    end
    self.coordinateXEntry.onMouseUp = function()
        return true
    end
    self.coordinateXEntry.onCommandEntered = function()
        self:applyCoordinateSearch()
    end
    self:addChild(self.coordinateXEntry)

    self.coordinateYEntry = ISTextEntryBox:new("", entryX, self.coordinatePanelY + 46, entryWidth, entryHeight)
    self.coordinateYEntry:initialise()
    self.coordinateYEntry:instantiate()
    self.coordinateYEntry:setMaxLines(1)
    self.coordinateYEntry.onMouseDown = function(entry)
        entry:focus()
        entry:selectAll()
        return true
    end
    self.coordinateYEntry.onMouseUp = function()
        return true
    end
    self.coordinateYEntry.onCommandEntered = function()
        self:applyCoordinateSearch()
    end
    self:addChild(self.coordinateYEntry)

    self.coordinateZEntry = ISTextEntryBox:new("0", entryX, self.coordinatePanelY + 80, entryWidth, entryHeight)
    self.coordinateZEntry:initialise()
    self.coordinateZEntry:instantiate()
    self.coordinateZEntry:setMaxLines(1)
    self.coordinateZEntry.onMouseDown = function(entry)
        entry:focus()
        entry:selectAll()
        return true
    end
    self.coordinateZEntry.onMouseUp = function()
        return true
    end
    self.coordinateZEntry.onCommandEntered = function()
        self:applyCoordinateSearch()
    end
    self:addChild(self.coordinateZEntry)

    self.coordinateSetButton = ISButton:new(
        self.coordinatePanelX + 12,
        self.coordinatePanelY + 114,
        COORDINATE_PANEL_WIDTH - 24,
        30,
        tr("SetPin"),
        self,
        SpawnSelectorUI.applyCoordinateSearch
    )
    self.coordinateSetButton:initialise()
    self.coordinateSetButton:instantiate()
    self.coordinateSetButton.anchorLeft = false
    self.coordinateSetButton.anchorRight = true
    self.coordinateSetButton.anchorTop = true
    self.coordinateSetButton.anchorBottom = false
    self:addChild(self.coordinateSetButton)

    self.keyButton = ISButton:new(
        MARGIN,
        headerHeight + MARGIN,
        110,
        BUTTON_HEIGHT,
        tr("Key"),
        self,
        SpawnSelectorUI.toggleKeyPanel
    )
    self.keyButton:initialise()
    self.keyButton:instantiate()
    self.keyButton.anchorLeft = true
    self.keyButton.anchorRight = false
    self.keyButton.anchorTop = true
    self.keyButton.anchorBottom = false
    self:addChild(self.keyButton)

    self.poiButton = ISButton:new(
        self.keyButton.x + self.keyButton.width + MARGIN,
        self.keyButton.y,
        140,
        BUTTON_HEIGHT,
        "",
        self,
        SpawnSelectorUI.togglePOIs
    )
    self.poiButton:initialise()
    self.poiButton:instantiate()
    self.poiButton.anchorLeft = true
    self.poiButton.anchorRight = false
    self.poiButton.anchorTop = true
    self.poiButton.anchorBottom = false
    self:addChild(self.poiButton)
    self.poiButton:setVisible(not (SandboxVars.SpawnSelector
        and SandboxVars.SpawnSelector.ShowPOIs == false))
    self:updatePOIButton()

    self.keyPanelX = MARGIN
    self.keyPanelY = self.keyButton.y + self.keyButton.height + 8

    self.keyBackdrop = ISPanel:new(
        self.keyPanelX,
        self.keyPanelY,
        KEY_PANEL_WIDTH,
        0
    )
    self.keyBackdrop:initialise()
    self.keyBackdrop.backgroundColor = { r = 0, g = 0, b = 0, a = 0.8 }
    self.keyBackdrop.borderColor = { r = 0.4, g = 0.4, b = 0.4, a = 1 }
    self.keyBackdrop.onMouseDown = function()
        return true
    end
    self.keyBackdrop.onMouseUp = function()
        return true
    end
    self.keyBackdrop.onMouseMove = function()
        return true
    end
    self.keyBackdrop.onMouseWheel = function()
        return true
    end
    self.keyBackdrop:setVisible(false)
    self.keyBackdrop.anchorLeft = true
    self.keyBackdrop.anchorRight = false
    self.keyBackdrop.anchorTop = true
    self.keyBackdrop.anchorBottom = false
    self:addChild(self.keyBackdrop)

    self.keyUI = ISWorldMapKey:new(
        self.keyPanelX,
        self.keyPanelY,
        KEY_PANEL_WIDTH,
        KEY_PANEL_HEIGHT,
        self
    )
    self.keyUI:initialise()
    self.keyUI:setIso(false)
    self.keyUI:setVisible(false)
    self.keyUI.anchorLeft = true
    self.keyUI.anchorRight = false
    self.keyUI.anchorTop = true
    self.keyUI.anchorBottom = false
    self:addChild(self.keyUI)

    self:setCoordinateControlsVisible(false)
end

function SpawnSelectorUI:setCoordinateControlsVisible(visible)
    self.coordinateXLabel:setVisible(visible)
    self.coordinateYLabel:setVisible(visible)
    self.coordinateZLabel:setVisible(visible)
    self.coordinateXEntry:setVisible(visible)
    self.coordinateYEntry:setVisible(visible)
    self.coordinateZEntry:setVisible(visible)
    self.coordinateSetButton:setVisible(visible)
end

function SpawnSelectorUI:toggleCoordinateSearch()
    self.coordinateSearchOpen = not self.coordinateSearchOpen
    self.coordinateAnimationFrom = self.coordinatePanelProgress
    self.coordinateAnimationTo = self.coordinateSearchOpen and 1 or 0
    self.coordinateAnimationStartedAt = getTimestampMs()
    self.coordinateSearchButton:setImage(getTexture(
        self.coordinateSearchOpen and "media/ui/Search_Icon_On.png" or "media/ui/Search_Icon_Off.png"
    ))
    if self.coordinateSearchOpen then
        self.coordinatePanel:setVisible(true)
    else
        self:setCoordinateControlsVisible(false)
    end
end

function SpawnSelectorUI:updateCoordinatePanel()
    if self.coordinatePanelProgress == self.coordinateAnimationTo then
        return
    end

    local elapsed = getTimestampMs() - self.coordinateAnimationStartedAt
    local amount = math.min(1, elapsed / COORDINATE_ANIMATION_MS)
    local eased = amount * amount * (3 - 2 * amount)
    self.coordinatePanelProgress = self.coordinateAnimationFrom
        + (self.coordinateAnimationTo - self.coordinateAnimationFrom) * eased
    self.coordinatePanel:setHeight(math.floor(COORDINATE_PANEL_HEIGHT * self.coordinatePanelProgress))

    if amount >= 1 then
        self.coordinatePanelProgress = self.coordinateAnimationTo
        if self.coordinateSearchOpen then
            self:setCoordinateControlsVisible(true)
            self.coordinateXEntry:focus()
            self.coordinateXEntry:selectAll()
        else
            self.coordinatePanel:setVisible(false)
        end
    end
end

function SpawnSelectorUI:applyCoordinateSearch()
    if self.waitingForServer then
        return
    end

    local x = tonumber(self.coordinateXEntry:getText())
    local y = tonumber(self.coordinateYEntry:getText())
    local z = tonumber(self.coordinateZEntry:getText())
    if not x or not y or not z then
        self.statusMessage = tr("ErrorWholeNumbers")
        self.statusIsError = true
        return
    end

    x = math.floor(x)
    y = math.floor(y)
    z = math.floor(z)
    if x <= -1000000 or x >= 1000000 or y <= -1000000 or y >= 1000000 then
        self.statusMessage = tr("ErrorCoordinateRange")
        self.statusIsError = true
        return
    end
    if z < SpawnSelector.MIN_Z or z > SpawnSelector.MAX_Z then
        self.statusMessage = tr(
            "ErrorZRange",
            SpawnSelector.MIN_Z,
            SpawnSelector.MAX_Z
        )
        self.statusIsError = true
        return
    end

    self.selectedZ = z
    self.layerInfo:setTitle(self:getLayerLabel())
    self:setSelectedPosition(x, y)
    self.map.mapAPI:centerOn(x, y)
end

function SpawnSelectorUI:getLayerLabel()
    if self.selectedZ == 0 then
        return "GF"
    end
    if self.selectedZ > 0 then
        return "F" .. tostring(self.selectedZ)
    end
    return "B" .. tostring(math.abs(self.selectedZ))
end

function SpawnSelectorUI:showLayerWarning()
    if layerWarningShown then
        return false
    end

    layerWarningShown = true
    self.layerPreviousGameSpeed = getGameSpeed()
    local width = 540
    local height = 180
    local modal = ISModalDialog:new(
        (getCore():getScreenWidth() - width) / 2,
        (getCore():getScreenHeight() - height) / 2,
        width,
        height,
        tr("LayerWarning"),
        false,
        self,
        SpawnSelectorUI.onLayerWarningClosed,
        self.player:getPlayerNum()
    )
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
    return true
end

function SpawnSelectorUI:onLayerWarningClosed()
    if not isClient() and self.layerPreviousGameSpeed == 0 then
        setGameSpeed(0)
    end
end

function SpawnSelectorUI:changeLayer(delta)
    if self:showLayerWarning() then
        return
    end

    self.selectedZ = math.max(SpawnSelector.MIN_Z, math.min(SpawnSelector.MAX_Z, self.selectedZ + delta))
    self.layerInfo:setTitle(self:getLayerLabel())
    self.coordinateZEntry:setText(tostring(self.selectedZ))
end

function SpawnSelectorUI:increaseLayer()
    self:changeLayer(1)
end

function SpawnSelectorUI:decreaseLayer()
    self:changeLayer(-1)
end

function SpawnSelectorUI:toggleMapView()
    self.detailedView = not self.detailedView
    self.map:setDetailedView(self.detailedView)
    self.viewButton:setTitle(self.detailedView and tr("StandardMap") or tr("DetailedMap"))
end

function SpawnSelectorUI:getMapBounds()
    local mapAPI = self.map.mapAPI
    local minX = mapAPI:getMinXInSquares()
    local minY = mapAPI:getMinYInSquares()
    local maxX = mapAPI:getMaxXInSquares()
    local maxY = mapAPI:getMaxYInSquares()

    if minX > maxX or minY > maxY then
        return nil
    end

    return {
        minX = minX,
        minY = minY,
        maxX = maxX,
        maxY = maxY,
    }
end

function SpawnSelectorUI:getRandomMappedPosition()
    local randomBounds = self:getMapBounds()
    if not randomBounds then
        return nil, nil
    end

    local x, y = SpawnSelector.rollRandomPosition(randomBounds, self.player)
    return x, y, randomBounds
end

function SpawnSelectorUI:confirmRandomSpawn()
    if self.waitingForServer then
        return
    end

    self.randomPreviousGameSpeed = getGameSpeed()
    local width = 420
    local height = 150
    local modal = ISModalDialog:new(
        (getCore():getScreenWidth() - width) / 2,
        (getCore():getScreenHeight() - height) / 2,
        width,
        height,
        tr("RandomConfirm"),
        true,
        self,
        SpawnSelectorUI.onRandomSpawnAnswer,
        self.player:getPlayerNum()
    )
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
end

function SpawnSelectorUI:onRandomSpawnAnswer(button)
    if button.internal ~= "YES" then
        if not isClient() and self.randomPreviousGameSpeed == 0 then
            setGameSpeed(0)
        end
        return
    end

    local x, y, randomBounds = self:getRandomMappedPosition()
    if not x then
        if not isClient() and self.randomPreviousGameSpeed == 0 then
            setGameSpeed(0)
        end
        self.statusMessage = tr("ErrorRandomLocation")
        self.statusIsError = true
        return
    end

    self.selectedX = nil
    self.selectedY = nil
    self.statusMessage = tr("ChoosingRandomLocation")
    self.statusIsError = false
    self:submitSpawn(x, y, 0, randomBounds)
end

function SpawnSelectorUI:confirmRandomBuildingSpawn()
    if self.waitingForServer then
        return
    end

    self.randomPreviousGameSpeed = getGameSpeed()
    local width = 460
    local height = 160
    local modal = ISModalDialog:new(
        (getCore():getScreenWidth() - width) / 2,
        (getCore():getScreenHeight() - height) / 2,
        width,
        height,
        tr("RandomBuildingConfirm"),
        true,
        self,
        SpawnSelectorUI.onRandomBuildingSpawnAnswer,
        self.player:getPlayerNum()
    )
    modal:initialise()
    modal:addToUIManager()
    modal:setAlwaysOnTop(true)
end

function SpawnSelectorUI:onRandomBuildingSpawnAnswer(button)
    if button.internal ~= "YES" then
        if not isClient() and self.randomPreviousGameSpeed == 0 then
            setGameSpeed(0)
        end
        return
    end

    local randomBounds = self:getMapBounds()
    local x, y
    if randomBounds then
        x, y = SpawnSelector.rollRandomBuildingTile(randomBounds, self.player)
    end
    if not x then
        if not isClient() and self.randomPreviousGameSpeed == 0 then
            setGameSpeed(0)
        end
        self.statusMessage = tr("ErrorRandomBuildingShort")
        self.statusIsError = true
        return
    end

    self.selectedX = nil
    self.selectedY = nil
    self.statusMessage = tr("SearchingRandomBuilding")
    self.statusIsError = false
    self:submitSpawn(x, y, 0, randomBounds, true)
end

function SpawnSelectorUI:isPositionInDeathZone(x, y)
    if not self.deathZones then
        return false
    end

    for _, zone in ipairs(self.deathZones) do
        local deltaX = x - zone.x
        local deltaY = y - zone.y
        if deltaX * deltaX + deltaY * deltaY <= zone.radius * zone.radius then
            return true
        end
    end

    return false
end

function SpawnSelectorUI:setSelectedPosition(x, y)
    if self:isPositionInDeathZone(x, y) then
        self.statusMessage = tr("ErrorDeathZone")
        self.statusIsError = true
        return
    end

    self.selectedX = x
    self.selectedY = y
    self.statusMessage = nil
    self.statusIsError = false
    self.confirmButton:setEnable(true)
    self.coordinateXEntry:setText(tostring(x))
    self.coordinateYEntry:setText(tostring(y))
    self.coordinateZEntry:setText(tostring(self.selectedZ))
end

function SpawnSelectorUI:confirmSpawn()
    if not self.selectedX or self.waitingForServer then
        return
    end

    self:submitSpawn(self.selectedX, self.selectedY, self.selectedZ)
end

function SpawnSelectorUI:submitSpawn(selectedX, selectedY, selectedZ, randomBounds, randomBuilding)
    if not isClient() and getGameSpeed() == 0 then
        setGameSpeed(1)
    end

    self.waitingForServer = true
    self.confirmButton:setEnable(false)

    if isClient() then
        sendClientCommand(self.player, MODULE, "SelectSpawn", {
            x = selectedX,
            y = selectedY,
            z = selectedZ,
            random = randomBounds ~= nil,
            randomBuilding = randomBuilding == true,
            minX = randomBounds and randomBounds.minX or nil,
            minY = randomBounds and randomBounds.minY or nil,
            maxX = randomBounds and randomBounds.maxX or nil,
            maxY = randomBounds and randomBounds.maxY or nil,
        })
        return
    end

    local x = selectedX + 0.5
    local y = selectedY + 0.5
    disableBuildingAlarmAt(x, y, selectedZ)
    SpawnSelectorUI.moveLocalPlayer(self.player, x, y, 0)
    pendingLocalSpawn = {
        player = self.player,
        x = x,
        y = y,
        z = selectedZ,
        validationZ = 0,
        randomBounds = randomBounds,
        randomBuilding = randomBuilding == true,
        randomAttempts = 1,
        validationStartedAt = getTimestampMs(),
    }
end

function SpawnSelectorUI.moveLocalPlayer(player, x, y, z)
    player:setX(x)
    player:setY(y)
    player:setZ(z)
    player:setLastX(x)
    player:setLastY(y)
    player:setLastZ(z)
end

function SpawnSelectorUI:finish()
    self.player:setBlockMovement(false)
    UIManager.setShowPausedMessage(true)
    self:setVisible(false)
    self:removeFromUIManager()
    SpawnSelectorUI.instance = nil
end

function SpawnSelectorUI:toggleKeyPanel()
    self.keyPanelOpen = not self.keyPanelOpen
    self.keyAnimationFrom = self.keyPanelProgress
    self.keyAnimationTo = self.keyPanelOpen and 1 or 0
    self.keyAnimationStartedAt = getTimestampMs()
    self.keyButton:setTitle(self.keyPanelOpen and tr("CloseKey") or tr("Key"))
end

function SpawnSelectorUI:updatePOIButton()
    local stateKey = self.poiVisible and "UI_On" or "UI_Off"
    self.poiButton:setTitle(tr("POIs") .. ": " .. getText(stateKey))
end

function SpawnSelectorUI:togglePOIs()
    if SandboxVars.SpawnSelector and SandboxVars.SpawnSelector.ShowPOIs == false then
        self.poiVisible = false
        return
    end
    self.poiVisible = not self.poiVisible
    self:updatePOIButton()
end

function SpawnSelectorUI:updateKeyPanel()
    if self.keyPanelProgress ~= self.keyAnimationTo then
        local elapsed = getTimestampMs() - self.keyAnimationStartedAt
        local amount = math.min(1, elapsed / COORDINATE_ANIMATION_MS)
        local eased = amount * amount * (3 - 2 * amount)
        self.keyPanelProgress = self.keyAnimationFrom
            + (self.keyAnimationTo - self.keyAnimationFrom) * eased
        if amount >= 1 then
            self.keyPanelProgress = self.keyAnimationTo
        end
    end

    self.keyBackdrop:setHeight(math.floor(KEY_PANEL_HEIGHT * self.keyPanelProgress))
    self.keyBackdrop:setVisible(self.keyPanelProgress > 0)
    self.keyUI:setVisible(self.keyPanelOpen and self.keyPanelProgress >= 1)
end

function SpawnSelectorUI:prerender()
    -- Focus loss can re-enable PZ's pause overlay above this screen.  The world
    -- is intentionally paused during selection, but this UI must remain active.
    UIManager.setShowPausedMessage(false)
    self.confirmButton:setEnable(self.selectedX ~= nil and not self.waitingForServer)
    ISPanel.prerender(self)
    self:updateCoordinatePanel()
    self:updateKeyPanel()
    self:drawRect(0, 0, self.width, 64, 0.95, 0.03, 0.03, 0.03)
    self:drawTextCentre(tr("Title"), self.width / 2, 10, 1, 1, 1, 1, UIFont.Large)

    local instruction = tr("Instructions")
    if self.statusMessage then
        instruction = self.statusMessage
    elseif self.selectedX then
        instruction = tr("Selected", self.selectedX, self.selectedY)
    end
    local red, green, blue = 0.85, 0.85, 0.85
    if self.statusMessage and self.statusIsError ~= false then
        red, green, blue = 1, 0.35, 0.35
    end
    self:drawTextCentre(instruction, self.width / 2, 38, red, green, blue, 1, UIFont.Small)
    if self.projectIndianaActive then
        self:drawTextRight(
            tr("ProjectIndianaDetected"),
            self.width - MARGIN,
            self.height - 27,
            0.65,
            0.75,
            0.55,
            1,
            UIFont.Small
        )
    end
    self:drawRainbowCredit()
end

function SpawnSelectorUI:drawRainbowCredit()
    local text = tr("Credit")
    local colorOffset = math.floor(getTimestampMs() / 180) % 7
    local x = MARGIN
    local y = self.height - 27

    for index = 1, #text do
        local character = text:sub(index, index)
        local phase = math.floor((index + colorOffset - 2) % 7)
        local red, green, blue = 1.00, 0.25, 0.25
        if phase == 1 then
            red, green, blue = 1.00, 0.60, 0.15
        elseif phase == 2 then
            red, green, blue = 1.00, 0.90, 0.20
        elseif phase == 3 then
            red, green, blue = 0.30, 0.90, 0.35
        elseif phase == 4 then
            red, green, blue = 0.25, 0.65, 1.00
        elseif phase == 5 then
            red, green, blue = 0.55, 0.35, 1.00
        elseif phase == 6 then
            red, green, blue = 0.90, 0.30, 0.90
        end
        self:drawText(character, x, y, red, green, blue, 1, UIFont.Small)
        x = x + getTextManager():MeasureStringX(UIFont.Small, character)
    end
end

function SpawnSelectorUI:onKeyRelease(key)
    return true
end

function SpawnSelectorUI:new(player)
    local width = getCore():getScreenWidth()
    local height = getCore():getScreenHeight()
    local ui = ISPanel.new(self, 0, 0, width, height)
    ui.player = player
    ui.backgroundColor = { r = 0, g = 0, b = 0, a = 1 }
    ui.selectedZ = 0
    ui.deathZones = {}
    ui.coordinateSearchOpen = false
    ui.coordinatePanelProgress = 0
    ui.coordinateAnimationFrom = 0
    ui.coordinateAnimationTo = 0
    ui.coordinateAnimationStartedAt = 0
    ui.keyPanelOpen = false
    ui.poiVisible = false
    ui.keyPanelProgress = 0
    ui.keyAnimationFrom = 0
    ui.keyAnimationTo = 0
    ui.keyAnimationStartedAt = 0
    ui.moveWithMouse = false
    ui.anchorLeft = true
    ui.anchorRight = true
    ui.anchorTop = true
    ui.anchorBottom = true
    return ui
end

function SpawnSelectorUI.open(player)
    if SpawnSelectorUI.instance then
        return
    end

    player:setBlockMovement(true)
    local ui = SpawnSelectorUI:new(player)
    ui:initialise()
    ui:addToUIManager()
    ui:setAlwaysOnTop(true)
    UIManager.setShowPausedMessage(false)
    SpawnSelectorUI.instance = ui
    clearNearbyZombies(player:getX(), player:getY(), player:getZ())

    if isClient() then
        sendClientCommand(player, MODULE, "SelectionStarted", {})
    else
        ui.deathZones = SpawnSelector.getActiveDeathZones(player)
    end
end

local function shouldOpen(player)
    if not player or player:getModData().SpawnSelectorComplete then
        return false
    end

    return math.floor(player:getX()) == SpawnSelector.STAGING_X
        and math.floor(player:getY()) == SpawnSelector.STAGING_Y
end

local function onCreatePlayer(playerIndex, player)
    if SpawnSelectorUI.instance and SpawnSelectorUI.instance.player ~= player then
        SpawnSelectorUI.instance:setVisible(false)
        SpawnSelectorUI.instance:removeFromUIManager()
        SpawnSelectorUI.instance = nil
        pendingLocalSpawn = nil
        pendingServerCandidate = nil
        localArrivalSafety = nil
    end

    if shouldOpen(player) then
        SpawnSelectorUI.open(player)
    end
end

local function onServerCommand(module, command, args)
    if module ~= MODULE then
        return
    end

    if command == "RandomRelocated" then
        local player = getPlayer()
        if player then
            SpawnSelectorUI.moveLocalPlayer(player, args.x, args.y, args.z)
        end
        return
    end

    if command == "RandomSpawnReady" then
        local player = getPlayer()
        if player then
            if args and args.clearMapKnowledge then
                clearTemporaryMapKnowledge(player)
            end
            localArrivalSafety = {
                player = player,
                x = player:getX(),
                y = player:getY(),
                z = player:getZ(),
                expiresAt = getTimestampMs() + SpawnSelector.ARRIVAL_GRACE_MS,
            }
        end
        if SpawnSelectorUI.instance then
            SpawnSelectorUI.instance:finish()
        end
        return
    end

    if command == "DeathZones" then
        if SpawnSelectorUI.instance then
            SpawnSelectorUI.instance.deathZones = (args and args.zones) or {}
        end
        return
    end

    if command == "SpawnCandidate" then
        local player = SpawnSelectorUI.instance and SpawnSelectorUI.instance.player or getPlayer()
        if player then
            pendingServerCandidate = {
                player = player,
                x = args.x,
                y = args.y,
                z = args.z,
            }
            SpawnSelectorUI.moveLocalPlayer(player, args.x, args.y, args.z)
        end
        return
    end

    if not SpawnSelectorUI.instance then
        return
    end

    if command == "SpawnRejected" then
        pendingServerCandidate = nil
        if args and args.reason == "RandomBuildingUnavailable" then
            clearTemporaryMapKnowledge(SpawnSelectorUI.instance.player)
        end
        if args and args.x and args.y and args.z then
            SpawnSelectorUI.moveLocalPlayer(
                SpawnSelectorUI.instance.player,
                args.x,
                args.y,
                args.z
            )
        end
        SpawnSelectorUI.instance.waitingForServer = false
        if args and args.reason == "RandomUnavailable" then
            SpawnSelectorUI.instance.statusMessage = tr("ErrorRandomLocation")
        elseif args and args.reason == "RandomBuildingUnavailable" then
            SpawnSelectorUI.instance.statusMessage = tr("ErrorRandomBuilding")
        elseif args and args.reason == "InvalidLayer" then
            SpawnSelectorUI.instance.statusMessage = tr("ErrorLayerRange")
        elseif args and args.reason == "LayerUnavailable" then
            SpawnSelectorUI.instance.statusMessage = tr("ErrorNoFloor")
        elseif args and args.reason == "Water" then
            SpawnSelectorUI.instance.statusMessage = tr("ErrorWater")
        elseif args and args.reason == "DeathZone" then
            SpawnSelectorUI.instance.statusMessage = tr("ErrorDeathZone")
        elseif args and args.reason == "BlockedRoomType" then
            SpawnSelectorUI.instance.statusMessage = tr("ErrorBuildingDisabledServer")
        else
            SpawnSelectorUI.instance.statusMessage = tr("ErrorSafehouse")
        end
        SpawnSelectorUI.instance.statusIsError = true
        SpawnSelectorUI.instance.confirmButton:setEnable(true)
        return
    end

    if command ~= "SpawnConfirmed" then
        return
    end

    local player = SpawnSelectorUI.instance.player
    pendingServerCandidate = nil
    SpawnSelectorUI.moveLocalPlayer(player, args.x, args.y, args.z)
    if args.random then
        return
    end

    localArrivalSafety = {
        player = player,
        x = args.x,
        y = args.y,
        z = args.z,
        expiresAt = getTimestampMs() + SpawnSelector.ARRIVAL_GRACE_MS,
    }
    SpawnSelectorUI.instance:finish()
end

clearNearbyZombies = function(x, y, z, radius, room)
    local zombies = getCell():getZombieList()
    local clearRadius = radius or SpawnSelector.SAFE_RADIUS
    local radiusSquared = clearRadius * clearRadius

    for index = zombies:size() - 1, 0, -1 do
        local zombie = zombies:get(index)
        local deltaX = zombie:getX() - x
        local deltaY = zombie:getY() - y
        local zombieSquare = zombie:getSquare()
        local sameFloor = zombieSquare and zombieSquare:getZ() == math.floor(z)
        local inRoom = room and zombieSquare and zombieSquare:getRoom() == room
        if sameFloor and (inRoom or deltaX * deltaX + deltaY * deltaY <= radiusSquared) then
            zombie:removeFromWorld()
            zombie:removeFromSquare()
        end
    end
end

local function turnOnRoomLights(square)
    local room = square:getRoom()
    if not room then
        return
    end

    local switches = room:getLightSwitches()
    for index = 0, switches:size() - 1 do
        switches:get(index):setActive(true)
    end
end

local function disableBuildingAlarm(square)
    local building = square and square:getBuilding()
    local definition = building and building:getDef()
    if definition and definition:isAlarmed() then
        definition:setAlarmed(false)
    end
end

disableBuildingAlarmAt = function(x, y, z)
    local world = getWorld()
    local metaGrid = world and world:getMetaGrid()
    local definition = metaGrid and metaGrid:getBuildingAt(math.floor(x), math.floor(y), z or 0)
    if definition and definition:isAlarmed() then
        definition:setAlarmed(false)
    end
end

local function rejectPendingLocalSpawn(message)
    local spawn = pendingLocalSpawn
    if not spawn then
        return
    end

    if spawn.randomBuilding then
        clearTemporaryMapKnowledge(spawn.player)
    end
    SpawnSelectorUI.moveLocalPlayer(
        spawn.player,
        SpawnSelector.STAGING_X + 0.5,
        SpawnSelector.STAGING_Y + 0.5,
        SpawnSelector.STAGING_Z
    )
    pendingLocalSpawn = nil
    if SpawnSelectorUI.instance then
        SpawnSelectorUI.instance.waitingForServer = false
        SpawnSelectorUI.instance.statusMessage = message
        SpawnSelectorUI.instance.statusIsError = true
        SpawnSelectorUI.instance.confirmButton:setEnable(true)
    end
    setGameSpeed(0)
end

local function rerollPendingLocalSpawn(spawn)
    if spawn.randomAttempts >= SpawnSelector.RANDOM_BUILDING_MAX_ATTEMPTS then
        local message = spawn.randomBuilding
            and tr("ErrorRandomBuilding")
            or tr("ErrorRandomLocation")
        rejectPendingLocalSpawn(message)
        return
    end

    local x, y
    if spawn.randomBuilding then
        x, y = SpawnSelector.rollRandomBuildingTile(spawn.randomBounds, spawn.player)
    else
        x, y = SpawnSelector.rollRandomPosition(spawn.randomBounds, spawn.player)
    end
    if not x then
        rejectPendingLocalSpawn(tr("ErrorRandomLocation"))
        return
    end

    spawn.x = x + 0.5
    spawn.y = y + 0.5
    spawn.randomAttempts = spawn.randomAttempts + 1
    spawn.validationStartedAt = getTimestampMs()
    disableBuildingAlarmAt(spawn.x, spawn.y, spawn.z)
    SpawnSelectorUI.moveLocalPlayer(spawn.player, spawn.x, spawn.y, spawn.z)
end

local function onTick()
    if pendingServerCandidate then
        SpawnSelectorUI.moveLocalPlayer(
            pendingServerCandidate.player,
            pendingServerCandidate.x,
            pendingServerCandidate.y,
            pendingServerCandidate.z
        )
    end

    safetyTick = safetyTick + 1
    if safetyTick >= 15 then
        safetyTick = 0
        if SpawnSelectorUI.instance and not isClient() then
            clearNearbyZombies(
                SpawnSelector.STAGING_X + 0.5,
                SpawnSelector.STAGING_Y + 0.5,
                SpawnSelector.STAGING_Z
            )
        end
        if localArrivalSafety then
            if getTimestampMs() >= localArrivalSafety.expiresAt then
                localArrivalSafety = nil
            else
                local square = getCell():getGridSquare(
                    math.floor(localArrivalSafety.x),
                    math.floor(localArrivalSafety.y),
                    localArrivalSafety.z
                )
                if square then
                    turnOnRoomLights(square)
                end
                if not isClient() then
                    clearNearbyZombies(
                        localArrivalSafety.x,
                        localArrivalSafety.y,
                        localArrivalSafety.z,
                        SpawnSelector.ARRIVAL_SAFE_RADIUS,
                        square and square:getRoom() or nil
                    )
                end
            end
        end
    end

    if not pendingLocalSpawn then
        return
    end

    local spawn = pendingLocalSpawn
    -- Disarm through the meta-grid before moving into the destination to load it.
    disableBuildingAlarmAt(spawn.x, spawn.y, spawn.z)
    SpawnSelectorUI.moveLocalPlayer(spawn.player, spawn.x, spawn.y, spawn.validationZ)
    local validationSquare = getCell():getGridSquare(
        math.floor(spawn.x),
        math.floor(spawn.y),
        spawn.validationZ
    )
    local square = getCell():getGridSquare(math.floor(spawn.x), math.floor(spawn.y), spawn.z)
    if not square then
        if spawn.randomBounds
            and getTimestampMs() - spawn.validationStartedAt >= SpawnSelector.LAYER_VALIDATION_MS then
            rerollPendingLocalSpawn(spawn)
            return
        end
        if validationSquare then
            rejectPendingLocalSpawn(tr("ErrorNoFloor"))
        elseif getTimestampMs() - spawn.validationStartedAt >= SpawnSelector.LAYER_VALIDATION_MS then
            rejectPendingLocalSpawn(tr("ErrorFloorLoad"))
        end
        return
    end

    if not square:getFloor() then
        if spawn.randomBounds then
            rerollPendingLocalSpawn(spawn)
            return
        end
        rejectPendingLocalSpawn(tr("ErrorNoFloor"))
        return
    end

    if square:isWaterSquare() and not spawn.randomBounds then
        rejectPendingLocalSpawn(tr("ErrorWater"))
        return
    end

    if spawn.randomBounds and square:isWaterSquare() then
        rerollPendingLocalSpawn(spawn)
        return
    end

    if spawn.randomBuilding and not square:getBuilding() then
        rerollPendingLocalSpawn(spawn)
        return
    end

    if not SpawnSelector.isSquareRoomTypeAllowed(square) then
        if spawn.randomBounds then
            rerollPendingLocalSpawn(spawn)
            return
        end
        rejectPendingLocalSpawn(tr("ErrorBuildingDisabled"))
        return
    end

    disableBuildingAlarm(square)
    SpawnSelector.giveBuildingKey(spawn.player, square)
    if spawn.randomBuilding then
        clearTemporaryMapKnowledge(spawn.player)
    end
    SpawnSelectorUI.moveLocalPlayer(spawn.player, spawn.x, spawn.y, spawn.z)
    clearNearbyZombies(spawn.x, spawn.y, spawn.z, SpawnSelector.ARRIVAL_SAFE_RADIUS, square:getRoom())
    turnOnRoomLights(square)
    spawn.player:getModData().SpawnSelectorComplete = true
    spawn.player:transmitModData()
    localArrivalSafety = {
        player = spawn.player,
        x = spawn.x,
        y = spawn.y,
        z = spawn.z,
        expiresAt = getTimestampMs() + SpawnSelector.ARRIVAL_GRACE_MS,
    }
    pendingLocalSpawn = nil

    if SpawnSelectorUI.instance then
        SpawnSelectorUI.instance:finish()
    end
end

local function onPlayerDeath(playerObj)
    if isClient() then
        return
    end
    SpawnSelector.recordDeathZone(playerObj)
end

Events.OnCreatePlayer.Add(onCreatePlayer)
Events.OnServerCommand.Add(onServerCommand)
Events.OnTick.Add(onTick)
Events.OnPlayerDeath.Add(onPlayerDeath)
