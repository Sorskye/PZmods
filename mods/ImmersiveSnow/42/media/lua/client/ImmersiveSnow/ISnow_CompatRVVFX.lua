-- Immersive Snow: compatibility with Real Vehicle VFX (workshop 3788393574, mod id RVVFX, checked
-- against its 2.6 code).
--
-- RVVFX replaces nothing we wrap (no BaseVehicle / VehiclePart methods, no metatables) and draws in
-- OnPostRender with its own blend and depth state, set and reset there, so our
-- RenderOpaqueObjectsInWorld pass is untouched. Its tire traces are skid marks (burnout, brake,
-- handbrake, drift) and short streaks of material a wheel picked up, dark rubber on "hard" or "wet"
-- ground. It tells snow by floor sprite names ("snow", "winter") or vehicle:getRoadMaterial(), and
-- vanilla snow is no sprite of the square (IsoCell draws e_newsnow_ground over it), so snowy asphalt
-- stays "hard" to it: a braking car left black rubber on top of our ruts in the snow.
--
-- So while our tire tracks are on, the wheels on a square with snow (the same test that places our
-- ruts) are taken out of RVS.TireTraces.UpdateVehicle; the rest go on as RVVFX wants. Its smoke,
-- snow spray and everything else stay. With our tire tracks off, RVVFX is left alone.

require "ImmersiveSnow/ISnow_Config"
require "ImmersiveSnow/ISnow_Decals"

local wrapped = false
local stats = { calls = 0, dropped = 0, errors = 0 }

local function snowyWheels(vehicle, wheelIds, context, geo)
    local cell = getCell()
    local keep = {}
    local z = context and context.vehicleZ or nil
    for _, wheelId in ipairs(wheelIds) do
        local wx, wy, wz = geo.GetWheelGroundWorld(vehicle, wheelId, z)
        if wx and ISnow.Decals.isSnowSquare(cell, math.floor(wx), math.floor(wy), math.floor(wz or 0)) then
            stats.dropped = stats.dropped + 1
        else
            keep[#keep + 1] = wheelId
        end
    end
    return keep
end

local function wrap()
    local RVS = RVS
    local traces = RVS and RVS.TireTraces
    local geo = RVS and (RVS.VehicleGeometry or RVS.Offsets)
    if wrapped or not traces or type(traces.UpdateVehicle) ~= "function"
        or not geo or type(geo.GetWheelGroundWorld) ~= "function" then return end
    wrapped = true
    local original = traces.UpdateVehicle
    traces.UpdateVehicle = function(vehicle, wheelIds, kind, intensity, now, context, isLocal)
        if kind and vehicle and ISnow.opt("TireTracks") and ISnow.Decals.snowActive() then
            stats.calls = stats.calls + 1
            local ok, result = pcall(function()
                local ids = wheelIds
                if geo.NormalizeWheelIds then ids = geo.NormalizeWheelIds(vehicle, ids) end
                if not ids or #ids == 0 then return ids end
                return snowyWheels(vehicle, ids, context, geo)
            end)
            if ok then
                wheelIds = result
                -- no wheel left: the call without a kind, which ends the vehicle's open marks
                if not wheelIds or #wheelIds == 0 then return original(vehicle, nil, nil, 0, now, context, isLocal) end
            else
                stats.errors = stats.errors + 1
                if stats.errors <= 3 then print("[ImmersiveSnow] RVVFX compat: " .. tostring(result)) end
            end
        end
        return original(vehicle, wheelIds, kind, intensity, now, context, isLocal)
    end
    print("[ImmersiveSnow] Real Vehicle VFX found: its tire traces skip snowy squares while our tire tracks are on")
end

ISnow.CompatRVVFX = {
    stats = function()
        print(string.format("[ImmersiveSnow] RVVFX compat: wrapped=%s calls=%d wheelsDropped=%d errors=%d",
            tostring(wrapped), stats.calls, stats.dropped, stats.errors))
    end,
}

Events.OnGameStart.Add(wrap)
