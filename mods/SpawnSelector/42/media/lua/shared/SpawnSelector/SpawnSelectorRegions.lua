SpawnSelector = SpawnSelector or {}

SpawnSelector.REGION_NAME = "Spawn Selector"
SpawnSelector.STAGING_X = 12425
SpawnSelector.STAGING_Y = 3702
SpawnSelector.STAGING_Z = 0
SpawnSelector.SAFE_RADIUS = 10
SpawnSelector.ARRIVAL_SAFE_RADIUS = 20
SpawnSelector.ARRIVAL_GRACE_MS = 15000
SpawnSelector.MIN_Z = -17
SpawnSelector.MAX_Z = 29
SpawnSelector.LAYER_VALIDATION_MS = 10000
SpawnSelector.RANDOM_BUILDING_MAX_ATTEMPTS = 25
SpawnSelector.RANDOM_BUILDING_SCAN_ATTEMPTS = 200
SpawnSelector.DEATH_ZONE_MODDATA_KEY = "SpawnSelectorDeathZones"

SpawnSelector.RANDOM_REGIONS = {
    { minX = 11763, minY = 1213, maxX = 12500, maxY = 3503 },
    { minX = 12423, minY = 1202, maxX = 14694, maxY = 7444 },
    { minX = 4975, minY = 5234, maxX = 7467, maxY = 5871 },
    { minX = 9352, minY = 6631, maxX = 14625, maxY = 7469 },
    { minX = 135, minY = 5754, maxX = 7288, maxY = 14746 },
    { minX = 7393, minY = 7516, maxX = 12726, maxY = 14617 },
}

function SpawnSelector.isRandomSpawnAllowed(x, y)
    for _, region in ipairs(SpawnSelector.RANDOM_REGIONS) do
        if x >= region.minX
            and x <= region.maxX
            and y >= region.minY
            and y <= region.maxY then
            return true
        end
    end

    return false
end

SpawnSelector.ROOM_TYPE_GROUPS = {
    {
        sandboxKey = "AllowWeaponsMilitary",
        roomTypes = {
            "gunstore", "gunstorestorage", "armystorage", "armysurplus",
            "armytent", "oldarmy", "hunterstorage", "hunting",
        },
    },
    {
        sandboxKey = "AllowMedical",
        roomTypes = {
            "dentist", "dentiststorage", "hospitalhallway", "hospitalroom",
            "hospitalstorage", "laboratory", "medical", "medicaloffice",
            "medicalstorage", "oldmedical", "pharmacy", "pharmacystorage",
            "morgue", "coroneroffice",
        },
    },
    {
        sandboxKey = "AllowLawEnforcement",
        roomTypes = {
            "policearchive", "policegarage", "policegunstorage",
            "policelibrary", "policelocker", "policeoffice",
            "policeoutfitstorage", "policestorage", "policeswat",
            "swatlocker", "prisoncells", "prisonerbelongings",
            "prisonlaundry", "prisonlocker", "prisonstorage",
            "detectiveoffice", "interrogationroom", "evidenceroom",
            "captainoffice", "firegarage", "firestorage", "ww_sherrif",
        },
    },
    {
        sandboxKey = "AllowRetailShops",
        roomTypes = {
            "generalstore", "generalstorestorage", "grocery",
            "grocerystorage", "conveniencestore", "cornerstore",
            "cornerstorecounter", "cornerstorestorage", "departmentstore",
            "departmentstorage", "clothingstore", "clothingstorage",
            "electronicstore", "electronicsstorage", "furniturestore",
            "jewelrystore", "jewelrystorage", "bookstore", "toystore",
            "toystorestorage", "sportstore", "sportstorage", "toolstore",
            "toolstorestorage", "gardenstore", "housewarestore",
            "kitchenwares", "leatherclothesstore", "liquorstore",
            "musicstore", "paintershop", "pawnshop", "pawnshopcooking",
            "pawnshopoffice", "pawnshopstorage", "giftstore", "giftstorage",
            "artstore", "camerastore", "walletshop", "zippeestore",
            "zippeestorage", "gigamart", "gigamartkitchen", "gasstore",
            "gasstorage", "gas2go", "movierental", "baseballstore",
            "baseballstorage", "baseballgiftstorage", "knifestore",
            "cdstore", "bagstore", "comicstore", "comicstorage",
            "candystore", "candystorage", "glassesstore", "shoestore",
            "petstore", "tailoringstore", "masonrystore", "plazastore1",
            "cardealershipoffice", "nolansoffice", "weddingstoredress",
            "weddingstoresuit", "weddingstorestorage", "tobaccostore",
            "tobaccostorage", "carsupply", "carsupplysport",
            "ww_generalstore", "ww_toolstore", "golfstore", "barbecuestore",
            "batstorage", "laundry", "laundryshirts", "laundrysuits",
            "aesthetic", "aestheticstorage", "ww_aesthetic",
        },
    },
    {
        sandboxKey = "AllowFoodDrink",
        roomTypes = {
            "bakery", "bakerykitchen", "bar", "barkitchen", "barstorage",
            "barcountertwiggy", "beergarden", "brewery", "brewerystorage",
            "burgerdining", "burgerkitchen", "butcher", "cafe",
            "cafekitchen", "cafeteria", "cafeteriakitchen", "catfish_dining",
            "catfish_kitchen", "chinesekitchen", "chineserestaurant",
            "deepfry_kitchen", "dinerbackroom", "dinercounter",
            "dinerkitchen", "dining", "dining_crepe", "donut_dining",
            "donut_kitchen", "donut_kitchenstorage", "fishchipskitchen",
            "hotdogstand", "icecream", "icecreamkitchen", "italiankitchen",
            "italianrestaurant", "jayschicken_dining", "jayschicken_kitchen",
            "juicestand", "kitchen_crepe", "mexicankitchen", "pizzakitchen",
            "pizzawhirled", "pizzawhirledcounter", "restaurantdining",
            "restaurantkitchen", "restaurantkitchen_fancy", "seafoodkitchen",
            "sodatruck", "spiffo_dining", "spiffoservice", "spiffoskitchen",
            "spiffosstorage", "stripclub", "stripclubvip", "sushidining",
            "sushikitchen", "westerndining", "westernkitchen",
            "whiskeybottling", "ww_bar", "ww_kitchen",
        },
    },
    {
        sandboxKey = "AllowIndustrial",
        roomTypes = {
            "batfactory", "batteryfactory", "batterystorage",
            "cabinetfactory", "cabinetshipping", "construction",
            "dogfoodfactory", "dogfoodshipping", "dogfoodstorage",
            "factory", "factorystorage", "fossoil", "fryshipping",
            "furnitureworkshop", "garagestorage", "glassmakingworkshop",
            "golffactory", "golfshipping", "jerkycoldroom", "jerkyfactory",
            "jerkyshipping", "jerkysmoker", "knappingworkshop",
            "knifefactory", "knifeshipping", "leatherworkshop",
            "loggingfactory", "loggingtruck", "loggingwarehouse",
            "mannequinfactory", "mannequinpainting", "mapfactory",
            "metalfabrication", "metalfabricationstorage", "metalshipping",
            "metalshop", "potteryworkshop", "radiofactory", "radioshipping",
            "storageunit", "tailoringworkshop", "upholsteryworkshop",
            "warehouse", "waterstorage", "weldingstorage",
            "weldingworkshop", "whittlerworkshop", "wirefactory",
            "producestorage", "potatostorage", "mechanic", "railroadrepair",
            "railroadstorage", "clockrepair", "clockrepairworkshop",
            "cobbler", "blacksmith", "carpentryworkshop", "bagworkshop",
            "ww_blacksmith", "farmstorage", "eggstorage", "outdoorsupply",
            "outdoorsupply_storage", "garage_ranger", "rangerhall",
            "rangerlocker", "rangeroffice", "rangerstorage",
            "fishingstorage", "kennels", "greenhouse", "florist",
        },
    },
    {
        sandboxKey = "AllowResidentialLodging",
        roomTypes = {
            "bedroom", "kidsbedroom", "hoarderbedroom", "hoarder",
            "hoarderkitchen", "hoarderoffice", "livingroom", "attic",
            "sunroom", "motelroom", "motelroomoccupied", "shed", "barn",
            "agriworkerdorm", "campworkerdorm", "ww_bedroom",
            "ww_livingroom",
        },
    },
    {
        sandboxKey = "AllowCivicPublic",
        roomTypes = {
            "church", "officechurch", "office", "officestorage", "library",
            "universitylibrary", "universitystorage", "post", "poststorage",
            "classroom", "classroom_anthro", "classroom_medieval",
            "classroom_pioneer", "classroom_pottery", "elementaryclassroom",
            "elementaryschool", "secondaryclassroom", "secondaryhall",
            "schoollab", "schoolstorage", "schoolgymstorage", "daycare",
            "musicschool", "newspaperprint_herald",
            "newspapershipping_herald", "newspaperstorage_herald",
            "mayorwestpointoffice", "judgematthassset", "cybercafe",
            "lostandfound",
        },
    },
    {
        sandboxKey = "AllowRecreation",
        roomTypes = {
            "bowlingalley", "boxing", "camping", "campingstorage",
            "dartgame", "duckshootgame", "gym", "gymstorage", "homecinema",
            "hoopgame", "lasertag", "pool", "ringtossgame", "theatre",
            "theatrekitchen", "theatrestorage", "throwgame", "recreation",
            "studio", "backstage", "catwalk", "viplounge", "smokingroom",
            "spa", "arenakitchen", "arenakitchenstorage", "bandkitchen",
            "bandlivingroom", "bandmerch", "changeroom", "changeroomjockey",
            "woodcraftset",
        },
    },
}

local roomTypeToSandboxKey = {}
local residentialRoomTypeSet = {}
for _, group in ipairs(SpawnSelector.ROOM_TYPE_GROUPS) do
    for _, roomType in ipairs(group.roomTypes) do
        roomTypeToSandboxKey[roomType] = group.sandboxKey
        if group.sandboxKey == "AllowResidentialLodging" then
            residentialRoomTypeSet[roomType] = true
        end
    end
end

function SpawnSelector.isRoomTypeAllowed(roomName)
    if not roomName then
        return true
    end

    local sandboxKey = roomTypeToSandboxKey[roomName:lower()]
    if not sandboxKey then
        return true
    end

    local sandboxVars = SandboxVars.SpawnSelector
    return not (sandboxVars and sandboxVars[sandboxKey] == false)
end

function SpawnSelector.isBuildingResidential(buildingDef)
    if not buildingDef then
        return false
    end

    local rooms = buildingDef:getRooms()
    if not rooms then
        return false
    end

    for index = 0, rooms:size() - 1 do
        local name = rooms:get(index):getName()
        if name and residentialRoomTypeSet[name:lower()] then
            return true
        end
    end

    return false
end

function SpawnSelector.isSquareRoomTypeAllowed(square)
    if not square then
        return true
    end

    local building = square:getBuilding()
    local buildingDef = building and building:getDef()
    local rooms = buildingDef and buildingDef:getRooms()
    if rooms then
        if SpawnSelector.isBuildingResidential(buildingDef) then
            return SpawnSelector.isRoomTypeAllowed("bedroom")
        end
        for index = 0, rooms:size() - 1 do
            if not SpawnSelector.isRoomTypeAllowed(rooms:get(index):getName()) then
                return false
            end
        end
        return true
    end

    local room = square:getRoom()
    if room then
        return SpawnSelector.isRoomTypeAllowed(room:getName())
    end

    return true
end

function SpawnSelector.giveBuildingKey(player, square)
    if not player or not square then
        return nil
    end

    local sandboxVars = SandboxVars.SpawnSelector
    if sandboxVars and sandboxVars.GiveBuildingKey == false then
        return nil
    end

    local building = square:getBuilding()
    local buildingDef = building and building:getDef()
    local keyId = buildingDef and buildingDef:getKeyId()
    if not keyId or keyId == 0 then
        return nil
    end

    local key = instanceItem("Base.Key1")
    if not key then
        return nil
    end

    key:setKeyId(keyId)
    ItemPickerJava.keyNamerBuilding(key, square)
    player:getInventory():AddItem(key)
    return key
end

function SpawnSelector.rollRandomPosition(bounds, player)
    local minX = math.max(bounds.minX, 135)
    local minY = math.max(bounds.minY, 1202)
    local maxX = math.min(bounds.maxX, 14694)
    local maxY = math.min(bounds.maxY, 14746)

    if minX > maxX or minY > maxY then
        return nil, nil
    end

    for attempt = 1, 1000 do
        local x = ZombRand(minX, maxX + 1)
        local y = ZombRand(minY, maxY + 1)
        if SpawnSelector.isRandomSpawnAllowed(x, y) and not SpawnSelector.isDeathZoneBlocked(player, x, y) then
            return x, y
        end
    end

    return nil, nil
end

function SpawnSelector.rollRandomBuildingTile(bounds, player)
    local world = getWorld()
    local metaGrid = world and world:getMetaGrid()
    local buildings = metaGrid and metaGrid:getBuildings()
    if not buildings or buildings:size() == 0 then
        return nil, nil
    end

    local minX = math.max(bounds and bounds.minX or 135, 135)
    local minY = math.max(bounds and bounds.minY or 1202, 1202)
    local maxX = math.min(bounds and bounds.maxX or 14694, 14694)
    local maxY = math.min(bounds and bounds.maxY or 14746, 14746)
    if minX > maxX or minY > maxY then
        return nil, nil
    end

    local buildingCount = buildings:size()
    for attempt = 1, SpawnSelector.RANDOM_BUILDING_SCAN_ATTEMPTS do
        local building = buildings:get(ZombRand(buildingCount))
        local rooms = building and building:getRooms()
        local roomCount = rooms and rooms:size() or 0
        if roomCount > 0 then
            local room = rooms:get(ZombRand(roomCount))
            local roomMinX, roomMinY = room:getX(), room:getY()
            local roomMaxX, roomMaxY = room:getX2(), room:getY2()
            local roomZ = room:getZ()
            if roomMaxX > roomMinX
                and roomMaxY > roomMinY
                and roomZ == 0
                and roomMinX >= minX and roomMaxX <= maxX
                and roomMinY >= minY and roomMaxY <= maxY
                and SpawnSelector.isRandomSpawnAllowed(roomMinX, roomMinY)
                and SpawnSelector.isRoomTypeAllowed(room:getName()) then
                for _ = 1, 20 do
                    local x = ZombRand(roomMinX, roomMaxX + 1)
                    local y = ZombRand(roomMinY, roomMaxY + 1)
                    if room:isInside(x, y, roomZ) and not SpawnSelector.isDeathZoneBlocked(player, x, y) then
                        return x, y
                    end
                end
            end
        end
    end

    return nil, nil
end

function SpawnSelector.getPlayerIdentity(player)
    if not player then
        return nil
    end

    local username = player:getUsername()
    if username and username ~= "" then
        return username
    end

    return "SinglePlayer"
end

function SpawnSelector.getDeathZoneStore()
    return ModData.getOrCreate(SpawnSelector.DEATH_ZONE_MODDATA_KEY)
end

function SpawnSelector.pruneDeathZones(zones, now)
    if not zones then
        return
    end

    for index = #zones, 1, -1 do
        local zone = zones[index]
        if zone.expiresAt ~= 0 and zone.expiresAt <= now then
            table.remove(zones, index)
        end
    end
end

function SpawnSelector.isDeathZoneFeatureEnabled()
    return SandboxVars.SpawnSelector ~= nil and SandboxVars.SpawnSelector.DeathZoneEnabled == true
end

function SpawnSelector.recordDeathZone(player)
    if not SpawnSelector.isDeathZoneFeatureEnabled() then
        return
    end

    local identity = SpawnSelector.getPlayerIdentity(player)
    if not identity then
        return
    end

    local durationHours = SandboxVars.SpawnSelector.DeathZoneDurationHours or 0
    local radius = SandboxVars.SpawnSelector.DeathZoneRadius or 100

    local expiresAt = 0
    if durationHours > 0 then
        expiresAt = getTimestampMs() + math.floor(durationHours * 3600000)
    end

    local store = SpawnSelector.getDeathZoneStore()
    local zones = store[identity]
    if not zones then
        zones = {}
        store[identity] = zones
    end

    table.insert(zones, {
        x = player:getX(),
        y = player:getY(),
        z = player:getZ(),
        radius = radius,
        expiresAt = expiresAt,
    })
end

function SpawnSelector.getActiveDeathZones(player)
    if not SpawnSelector.isDeathZoneFeatureEnabled() then
        return {}
    end

    local identity = SpawnSelector.getPlayerIdentity(player)
    if not identity then
        return {}
    end

    local zones = SpawnSelector.getDeathZoneStore()[identity]
    if not zones then
        return {}
    end

    SpawnSelector.pruneDeathZones(zones, getTimestampMs())
    return zones
end

function SpawnSelector.isDeathZoneBlocked(player, x, y)
    if not player or not SpawnSelector.isDeathZoneFeatureEnabled() then
        return false
    end

    local zones = SpawnSelector.getActiveDeathZones(player)
    for _, zone in ipairs(zones) do
        local deltaX = x - zone.x
        local deltaY = y - zone.y
        if deltaX * deltaX + deltaY * deltaY <= zone.radius * zone.radius then
            return true
        end
    end

    return false
end

function SpawnSelector.createSpawnRegion()
    return {
        name = SpawnSelector.REGION_NAME,
        points = {
            unemployed = {
                {
                    posX = SpawnSelector.STAGING_X,
                    posY = SpawnSelector.STAGING_Y,
                    posZ = SpawnSelector.STAGING_Z,
                },
            },
        },
    }
end

function SpawnSelector.ensureSpawnRegion(regions)
    if not regions then
        return SpawnSelector.createSpawnRegion()
    end

    for _, region in ipairs(regions) do
        if region.name == SpawnSelector.REGION_NAME then
            return region
        end
    end

    local region = SpawnSelector.createSpawnRegion()
    table.insert(regions, 1, region)
    return region
end

local function addSpawnSelectorRegion(regions)
    SpawnSelector.ensureSpawnRegion(regions)
end

Events.OnSpawnRegionsLoaded.Add(addSpawnSelectorRegion)
