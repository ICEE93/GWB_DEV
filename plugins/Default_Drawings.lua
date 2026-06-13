local Nn, GWB = ...

-- plugin object eh
local plugin = {}
plugin.name = "Drawings"

-- TODO: add these for API or whatever? maybe just use Interface/build nrs?
plugin.xpacs = "legion|tww" 

-- this is handy for when a users wants to select from a GUI soonTM?
plugin.author = "your_name"

--local tickerNameCombat = plugin.name .. "_" .. "draw"

-- register stuff
plugin.cb_priority = GWB.enums.cb_priority.DEFAULT
plugin.callbacks = {}

plugin.settings = {
    ["draw_debug"] = {
        ["label"] = "Draw debug info",
        ["value"] = false
    },
    ["draw_mover_path"] = {
        ["label"] = "Draw dynamic mesh path",
        ["value"] = true,
    },
    ["draw_waypoints"] = {
        ["label"] = "Draw waypoint nodes",
        ["value"] = true,
    }
}

local Draw = nil
local function DrawTick(draw)
    local drawDebug = plugin.settings.draw_debug.value
    local drawDynLine = plugin.settings.draw_mover_path.value
    local drawWaypoints = plugin.settings.draw_waypoints

    if drawDynLine then
        draw:SetColor(draw.colors.white)

        local prev = nil
        local path = GWB.Mover.path
        if path ~= nil and #path > 0 and GWB.Mover:IsMoving() then
            -- always draw lines?
            for i=1, #path do
                local v = path[i]
                if prev ~= nil then
                    draw:Line(prev.x, prev.y, prev.z+0.1, v.x, v.y, v.z+0.1)
                end
                prev = v
            end
        end
    end

    if drawWaypoints then
        draw:SetColor(draw.colors.yellow)

        -- check if waypoint plugin is OK?
        local wpPlugin = GWB.plugins["Waypoints"]
        if wpPlugin ~= nil then
            local useGlider = wpPlugin.settings.use_glider.value
            local gliderOffZ = wpPlugin.settings.glider_z_offset.value
            -- ehh?
            local waypoints = GWB:GetPointsForCurrentMap()
            --draw:Circle()
            for i=1, #waypoints do
                local p = waypoints[i]
                --draw:Line(p.wx, p.wy, p.wz, p.wx, p.wy, p.wz+1.5)
                
                -- triangle on floor?
                -- base size and apex height
                local r = 0.825           -- radius/size of base triangle
                local baseZ = p.wz + 0.1
                local apexOffsetZ = 1.5 -- positive = point above base, negative = below

                -- base triangle vertices (flat in X-Y at baseZ)
                local x1, y1 = p.wx,           p.wy + r
                local x2, y2 = p.wx - r*0.866, p.wy - r*0.5
                local x3, y3 = p.wx + r*0.866, p.wy - r*0.5

                -- apex (center, offset in Z)
                local ax, ay, az = p.wx, p.wy, baseZ + apexOffsetZ

                -- draw top edges
                draw:Line(x1, y1, az,  x2, y2, az)
                draw:Line(x2, y2, az,  x3, y3, az)
                draw:Line(x3, y3, az,  x1, y1, az)

                -- draw side edges from base to apex
                draw:Line(x1, y1, az,  ax, ay, baseZ)
                draw:Line(x2, y2, az,  ax, ay, baseZ)
                draw:Line(x3, y3, az,  ax, ay, baseZ)

                 
                if useGlider then
                    draw:SetColor(draw.colors.white)
                    draw:Line(p.wx, p.wy, baseZ + 10, p.wx, p.wy, baseZ+gliderOffZ-20)
                    draw:SetColor(draw.colors.red)
                    draw:Line(p.wx, p.wy, baseZ + gliderOffZ -4, p.wx, p.wy, baseZ+gliderOffZ+4)
                    draw:SetColor(draw.colors.yellow)
                end

            end
        end
    end
end

local function OnLoad()
    Draw = Nn.Utils.Draw:New()
    Draw:Sync(DrawTick)
    Draw:Enable()
end

--GWB:RegisterTicker(tickerNameCombat, tick)
GWB:RegisterPlugin(plugin)

OnLoad() -- maybe call this external??
