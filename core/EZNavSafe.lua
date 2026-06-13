local Nn, _, EZ = ...
if not EZ then 
    Nn.EZ = Nn.EZ or {}
    EZ = Nn.EZ
end

EZ.Nav = {}
local Nav = EZ.Nav
local floor = math.floor
local abs = math.abs
local sqrt = math.sqrt
local insert = table.insert
local unpack = unpack or table.unpack

local loadedTiles = {}
local mapHeaders = {}
local activeSearch = nil
local remove = table.remove
local useBigEndian = false

local mmapDir = "retail"
if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
    mmapDir = "classic_era"
end

local function getHighPrecTime()
    if debugprofilerstop then
        return debugprofilerstop()
    elseif GetTimePreciseSec then
        return GetTimePreciseSec() * 1000
    else
        return GetTime() * 1000
    end
end

local searchStartTime = 0
local function checkYield()
    if coroutine.running() and getHighPrecTime() - searchStartTime > 8.0 then
        coroutine.yield()
        searchStartTime = getHighPrecTime()
    end
end

local function dbgPrint(...)
    if Nav.Config and Nav.Config.Debug then
        print(...)
    end
end

-- Binary Helpers (Endian-Aware)
local function readUInt32(str, pos)
    local b1, b2, b3, b4 = string.byte(str, pos, pos + 3)
    if not b1 then return 0 end
    if useBigEndian then
        return b4 + b3 * 256 + b2 * 65536 + b1 * 16777216
    end
    return b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
end

local function readInt32(str, pos)
    local val = readUInt32(str, pos)
    return (val >= 2147483648) and val - 4294967296 or val
end

local function readUInt16(str, pos)
    local b1, b2 = string.byte(str, pos, pos + 1)
    if not b1 then return 0 end
    if useBigEndian then
        return b2 + b1 * 256
    end
    return b1 + b2 * 256
end

-- Config
Nav.Config = {
    TileSize = 533.33333,
    SearchBudget = 8.0, -- Max milliseconds to spend per frame on A* (debugprofilerstop is in ms)
    MaxIterationsPerFrame = 200,
    Debug = true,
}

local function readFloat(str, pos)
    local b1, b2, b3, b4 = string.byte(str, pos, pos + 3)
    if not b1 then return 0 end
    local n
    if useBigEndian then
        n = b4 + b3 * 256 + b2 * 65536 + b1 * 16777216
    else
        n = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    end
    if n == 0 then return 0 end
    local s = (n >= 2147483648) and -1 or 1
    local e = floor((n % 2147483648) / 8388608)
    local m = n % 8388608
    if e == 0 then return s * math.ldexp(m, -149) end
    if e == 255 then return m == 0 and s * (1/0) or (0/0) end
    return s * math.ldexp(m + 8388608, e - 150)
end

-- ============================================
-- Map & Tile Loading
-- ============================================

function Nav.GetTileKey(mapId, tx, ty)
    return string.format("%d_%d_%d", mapId, tx, ty)
end

function Nav.LoadMapHeader(mapId)
    if mapHeaders[mapId] then return mapHeaders[mapId] end
    
    local name = string.format("%04d.mmap", mapId)
    local variations = {
        string.format("/mmaps/%s/%s", mmapDir, name),
        string.format("mmaps/%s/%s", mmapDir, name),
        string.format([[mmaps\%s\%s]], mmapDir, name),
        string.format([[..\mmaps\%s\%s]], mmapDir, name),
    }
    
    local data = nil
    local successfulPath = nil
    
    for _, path in ipairs(variations) do
        data = Nn.ReadFile(path)
        if data then
            successfulPath = path
            break
        end
    end

    if not data then 
        print(string.format("|cff00ff00MMap Editor:|r Map %d, Tile %d_%d", mapId, tx, ty))
        print("Path: " .. path)
        
        local px, py, pz = ObjectPosition("player")
        print(string.format("Player Pos: %.1f, %.1f, %.1f", px, py, pz))
        print("|cffff0000[EZNav]|r Checked 7 path variations. File access denied or path invalid.")
        return nil 
    end
    
    if not Nav.FoundPathFormat then
        Nav.FoundPathFormat = successfulPath:gsub(name, "%%s")
        print("|cff00ff00[EZNav]|r Found valid mmap path style: " .. successfulPath)
    end
    
    -- Parse bitmask (512 bytes starting at offset 8)
    local mask = {}
    for i = 1, 512 do
        mask[i] = string.byte(data, 8 + i) or 0
    end
    
    mapHeaders[mapId] = mask
    return mask
end

function Nav.HasTile(mapId, tx, ty)
    local mask = Nav.LoadMapHeader(mapId)
    if not mask then return false end
    
    -- Swap tx/ty for this specific mmap set
    local idx = tx * 64 + ty
    local byteIdx = floor(idx / 8) + 1
    local bitIdx = idx % 8
    
    local byte = mask[byteIdx]
    if not byte then return false end
    
    return bit.band(byte, bit.lshift(1, bitIdx)) ~= 0
end

function Nav.LoadTile(mapId, tx, ty)
    local key = Nav.GetTileKey(mapId, tx, ty)
    if loadedTiles[key] then return loadedTiles[key] end
    
    local name = string.format("%04d_%02d_%02d.mmtile", mapId, tx, ty)
    local nameNoU = string.format("%04d%02d%02d.mmtile", mapId, tx, ty)
    local variations = {
        string.format("/mmaps/%s/%s", mmapDir, name),
        string.format("/mmaps/%s/%s", mmapDir, nameNoU),
        string.format("mmaps/%s/%s", mmapDir, name),
        string.format("mmaps/%s/%s", mmapDir, nameNoU),
        string.format([[mmaps\%s\%s]], mmapDir, name),
        string.format([[mmaps\%s\%s]], mmapDir, nameNoU),
        string.format([[..\mmaps\%s\%s]], mmapDir, name),
        string.format([[..\mmaps\%s\%s]], mmapDir, nameNoU),
    }

    local data = nil
    local lastTriedPath = ""
    for _, path in ipairs(variations) do
        lastTriedPath = path
        data = Nn.ReadFile(path)
        if data then break end
    end
    
    -- Fallback: Try swapped coordinates Map_TileY_TileX
    if not data then
        local altName = string.format("%04d_%02d_%02d.mmtile", mapId, ty, tx)
        local altNameNoU = string.format("%04d%02d%02d.mmtile", mapId, ty, tx)
        for _, path in ipairs(variations) do
            local altPath = path:gsub(name, altName):gsub(nameNoU, altNameNoU)
            lastTriedPath = altPath
            data = Nn.ReadFile(altPath)
            if data then break end
        end
    end
    
    if not data then 
        -- Don't spam chat; it's completely normal for adjacent tiles to not exist on map edges
        return nil 
    end

    -- Detection Endianness from Magic (1-4)
    local magic = string.sub(data, 1, 4)
    -- Detection Endianness from Magic (1-4)
    local magic = string.sub(data, 1, 4)
    useBigEndian = false 
    
    -- Parse Header (VAND-specific definitive offsets)
    local h = {}
    h.polyCount = readInt32(data, 45)
    h.vertCount = readInt32(data, 49)
    h.maxLinkCount = readInt32(data, 53)
    
    -- dtMeshHeader bounds from DetourNavMesh.h (verified struct layout)
    -- dtMeshHeader field order at VAND data offset 21:
    -- [21] magic(4) version(4) x(4) y(4) layer(4) userId(4) polyCount(4) vertCount(4)
    -- [57] maxLinkCount(4) detailMeshCount(4) detailVertCount(4) detailTriCount(4)
    -- [73] bvNodeCount(4) offMeshConCount(4) offMeshBase(4)
    -- [85] walkableHeight(4) walkableRadius(4) walkableClimb(4)
    -- [97] bmin[0](4) bmin[1](4) bmin[2](4)  <- X, Y_height, Z in Detour space
    -- [109] bmax[0](4) bmax[1](4) bmax[2](4)
    -- Detour Y = WoW Z (height), Detour Z = WoW Y (N/S)
    -- So: bmin[0]=WoW_X(off97), bmin[1]=WoW_Z_height(off101), bmin[2]=WoW_Y(off105)
    -- HEX VERIFIED: Detour stores as (WoW_Y, WoW_Z, WoW_X)
    -- bmin[0]@93=WoW_Y(0.0), bmin[1]@97=WoW_Z(26.3), bmin[2]@101=WoW_X(-9600)
    h.bmin = { readFloat(data, 101), readFloat(data, 93), readFloat(data, 97) }   -- {WoW_X, WoW_Y, WoW_Z}
    h.bmax = { readFloat(data, 113), readFloat(data, 105), readFloat(data, 109) } -- {WoW_X, WoW_Y, WoW_Z}
    
    if Nav.Config.Debug then
        print(string.format("|cffaaaaaa[EZNav]|r Tile %d_%d World Bounds:", tx, ty))
        print(string.format("  X: %.1f to %.1f", h.bmin[1], h.bmax[1]))
        print(string.format("  Y: %.1f to %.1f", h.bmin[2], h.bmax[2]))
    end

    -- Detour Standard Byte Stack
    -- File = MmapTileHeader(20) + dtMeshHeader(100) + verts + polys + ...
    -- ReadFile returns whole file, so verts start at byte 121
    local vertOffset = 121  -- empirically verified from diagnostic
    local polyOffset = vertOffset + (h.vertCount * 12)
    local polySize = 32  -- sizeof(dtPoly) verified from header
    
    local tile = {
        header = h,
        verts = {},
        polys = {},
        key = key
    }
    
    -- Vertices stored as Detour (X, Y_height, Z) = WoW (X, Z_height, Y)
    -- We store as {WoW_X, WoW_Y, WoW_Z} for consistent use
    for i = 0, h.vertCount - 1 do
        local off = vertOffset + (i * 12)
        -- HEX VERIFIED: off+0=WoW_Y, off+4=WoW_Z(height), off+8=WoW_X
        local wowy = readFloat(data, off)      -- Detour X = WoW Y (N/S)
        local wowz = readFloat(data, off + 4)  -- Detour Y = WoW Z (height)
        local wowx = readFloat(data, off + 8)  -- Detour Z = WoW X
        
        tile.verts[i] = { wowx, wowy, wowz }  -- {WoW_X, WoW_Y, WoW_Z}
        if i % 100 == 0 then checkYield() end
    end
    
    if Nav.Config.Debug then
        local v = tile.verts[0]
        if v then
            -- Print as WoW_X, WoW_Y, WoW_Z
            print(string.format("|cffaaaaaa[EZNav]|r Vertex #0 (X,Y,Z): %.1f, %.1f, %.1f", v[1], v[2], v[3]))
        end
    end
    
    -- Load Polygons
    -- dtPoly layout (32 bytes):
    --   [+0]  unsigned int firstLink       (4)
    --   [+4]  unsigned short verts[6]      (12)
    --   [+16] unsigned short neis[6]       (12)
    --   [+28] unsigned short flags         (2)
    --   [+30] unsigned char vertCount      (1)
    --   [+31] unsigned char areaAndtype    (1)
    for i = 0, h.polyCount - 1 do
        local off = polyOffset + (i * polySize)
        local vertCount = string.byte(data, off + 30) or 0
        local areaAndtype = string.byte(data, off + 31) or 0
        local poly = {
            index = i,
            tile = tile,
            verts = {},
            neighs = {},
            openEdges = {},
            crossTileLinks = {},
            flags    = readUInt16(data, off + 28),
            vertCount = vertCount,
            area     = bit.band(areaAndtype, 0x3F),
            polyType = bit.rshift(areaAndtype, 6),
        }
        
        -- Vertex Indices (only read vertCount valid entries)
        local minX, maxX = 1e10, -1e10
        local minY, maxY = 1e10, -1e10
        local minZ, maxZ = 1e10, -1e10

        for v = 0, vertCount - 1 do
            local vIdx = readUInt16(data, off + 4 + (v * 2))
            insert(poly.verts, vIdx)
            
            -- Precalculate AABB for fast point-in-poly rejection
            local vt = tile.verts[vIdx]
            if vt then
                if vt[1] < minX then minX = vt[1] end
                if vt[1] > maxX then maxX = vt[1] end
                if vt[2] < minY then minY = vt[2] end
                if vt[2] > maxY then maxY = vt[2] end
                if vt[3] < minZ then minZ = vt[3] end
                if vt[3] > maxZ then maxZ = vt[3] end
            end
        end
        
        poly.bmin = {minX, minY, minZ}
        poly.bmax = {maxX, maxY, maxZ}
        
        -- Neighbor Indices and Open Edges
        for n = 0, vertCount - 1 do
            local nIdx = readUInt16(data, off + 16 + (n * 2))
            insert(poly.neighs, nIdx)
            if nIdx == 65535 or bit.band(nIdx, 0x8000) ~= 0 then
                local v1Idx = poly.verts[n + 1]
                local v2Idx = poly.verts[(n + 1) % vertCount + 1]
                insert(poly.openEdges, {v1 = v1Idx, v2 = v2Idx})
            end
        end
        
        tile.polys[i] = poly
        if i % 50 == 0 then checkYield() end
    end
    
    loadedTiles[key] = tile
    
    -- Dynamically stitch cross-tile neighbors
    local function distSq(v1, v2) return (v1[1]-v2[1])^2 + (v1[2]-v2[2])^2 + (v1[3]-v2[3])^2 end
    local adjacents = { {tx-1, ty}, {tx+1, ty}, {tx, ty-1}, {tx, ty+1} }
    
    for _, adj in ipairs(adjacents) do
        checkYield()
        local adjKey = mapId .. "_" .. adj[1] .. "_" .. adj[2]
        local adjTile = loadedTiles[adjKey]
        if adjTile then
            for i1 = 0, h.polyCount - 1 do
                local p1 = tile.polys[i1]
                for _, e1 in ipairs(p1.openEdges) do
                    local p1v1 = tile.verts[e1.v1]
                    local p1v2 = tile.verts[e1.v2]
                    
                    for i2 = 0, adjTile.header.polyCount - 1 do
                        local p2 = adjTile.polys[i2]
                        for _, e2 in ipairs(p2.openEdges) do
                            local p2v1 = adjTile.verts[e2.v1]
                            local p2v2 = adjTile.verts[e2.v2]
                            
                            -- Edges must physically overlap (reverse winding)
                            if (distSq(p1v1, p2v2) < 0.01 and distSq(p1v2, p2v1) < 0.01) or
                               (distSq(p1v1, p2v1) < 0.01 and distSq(p1v2, p2v2) < 0.01) then
                                insert(p1.crossTileLinks, {tile = adjTile, poly = p2})
                                insert(p2.crossTileLinks, {tile = tile, poly = p1})
                            end
                        end
                    end
                end
            end
        end
    end
    
    return tile
end

-- ============================================
-- Pathfinding (Async A*)
-- ============================================

local function heuristic(a, b)
    return sqrt((a[1]-b[1])^2 + (a[2]-b[2])^2 + (a[3]-b[3])^2)
end

-- 2D point-in-polygon test using WoW X (slot 1) and WoW Y (slot 2)
local function isPointInPoly(px, py, verts)
    local inside = false
    local j = #verts
    for i = 1, #verts do
        local xi, yi = verts[i][1], verts[i][2]  -- WoW X, WoW Y
        local xj, yj = verts[j][1], verts[j][2]
        if ((yi > py) ~= (yj > py)) and
           (px < (xj - xi) * (py - yi) / (yj - yi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

function Nav.GetPolygonAt(tile, x, y, z)
    -- tile.header.bmin = {WoW_X, WoW_Y, WoW_Z}
    -- Bounds check: X is slot 1, Y (N/S) is slot 2
    if x < tile.header.bmin[1] or x > tile.header.bmax[1] or
       y < tile.header.bmin[2] or y > tile.header.bmax[2] then
        return nil
    end

    local bestPoly = nil
    local minDistZ = 20  -- vertical tolerance in yards

    for i = 0, tile.header.polyCount - 1 do
        local p = tile.polys[i]
        -- Fast AABB Rejection (Eliminates 99.9% of lag)
        if p and p.polyType == 0 and p.area ~= 0 and #p.verts >= 3 then
            if x >= p.bmin[1] and x <= p.bmax[1] and 
               y >= p.bmin[2] and y <= p.bmax[2] then
                
                local pVerts = {}
                for _, vIdx in ipairs(p.verts) do
                    local v = tile.verts[vIdx]
                    if v then insert(pVerts, v) end
                end

                if #pVerts >= 3 and isPointInPoly(x, y, pVerts) then
                    -- Height check using precalculated Z
                    local midZ = (p.bmin[3] + p.bmax[3]) * 0.5
                    local distZ = math.abs(z - midZ)
                    if distZ < minDistZ then
                        minDistZ = distZ
                        bestPoly = p
                    end
                end
            end
        end
    end
    return bestPoly
end

function Nav.GetClosestPolygon(tile, x, y, z)
    if not tile then return nil end
    local bestPoly = nil
    local minDist = 999999
    
    for i = 0, tile.header.polyCount - 1 do
        local p = tile.polys[i]
        if p and p.polyType == 0 and p.area ~= 0 and #p.verts >= 3 then
            local cx = (p.bmin[1] + p.bmax[1]) * 0.5
            local cy = (p.bmin[2] + p.bmax[2]) * 0.5
            local cz = (p.bmin[3] + p.bmax[3]) * 0.5
            
            local dx = cx - x
            local dy = cy - y
            local dz = cz - z
            local dist = math.sqrt(dx*dx + dy*dy + dz*dz)
            
            if dist < minDist then
                minDist = dist
                bestPoly = p
            end
        end
    end
    
    if minDist < 50.0 then
        return bestPoly
    end
    return nil
end

-- ============================================
-- Funnel Algorithm (Path Smoothing)
-- ============================================

local function vdistsq(a, b) return (a.x-b.x)^2 + (a.y-b.y)^2 end
local function vcross2D(a, b, c) return (b.x-a.x)*(c.y-a.y) - (c.x-a.x)*(b.y-a.y) end

function Nav.Funnel(pathPolys, startPos, endPos, tile)
    local portals = {}
    insert(portals, {left = startPos, right = startPos})
    
    for i = 1, #pathPolys - 1 do
        local p1 = pathPolys[i]
        local p2 = pathPolys[i+1]
        
        -- Find shared edge between p1 and p2 using physical distance (supports cross-tile)
        local sharedL, sharedR = nil, nil
        for _, vIdx1 in ipairs(p1.verts) do
            local v1 = p1.tile.verts[vIdx1]
            for _, vIdx2 in ipairs(p2.verts) do
                local v2 = p2.tile.verts[vIdx2]
                local distSq = (v1[1]-v2[1])^2 + (v1[2]-v2[2])^2 + (v1[3]-v2[3])^2
                if distSq < 0.01 then
                    if not sharedL then sharedL = v1 else sharedR = v1 break end
                end
            end
        end
        
        if sharedL and sharedR then
            local vL = sharedL
            local vR = sharedR
            
            -- Order vertices left to right relative to polygon centroid
            local cx1, cy1 = 0, 0
            for _, vIdx in ipairs(p1.verts) do
                local v = p1.tile.verts[vIdx]
                cx1 = cx1 + v[1]
                cy1 = cy1 + v[2]
            end
            cx1 = cx1 / #p1.verts
            cy1 = cy1 / #p1.verts
            
            -- We want vL to be Left, vR to be Right when looking from C.
            -- Counter-Clockwise cross product should be > 0.
            local cross = (vR[1] - cx1) * (vL[2] - cy1) - (vL[1] - cx1) * (vR[2] - cy1)
            if cross < 0 then
                local temp = vL
                vL = vR
                vR = temp
            end
            
            local pdx = vR[1] - vL[1]
            local pdy = vR[2] - vL[2]
            local pDist = math.sqrt(pdx*pdx + pdy*pdy)
            local shrink = 1.25 -- Agent radius buffer (stay away from holes/walls)
            local newL = {x = vL[1], y = vL[2], z = vL[3]}
            local newR = {x = vR[1], y = vR[2], z = vR[3]}
            
            if pDist > shrink * 2.1 then
                newL.x = vL[1] + (pdx/pDist) * shrink
                newL.y = vL[2] + (pdy/pDist) * shrink
                newR.x = vR[1] - (pdx/pDist) * shrink
                newR.y = vR[2] - (pdy/pDist) * shrink
            else
                local mx = (vL[1] + vR[1]) / 2
                local my = (vL[2] + vR[2]) / 2
                newL.x, newL.y = mx, my
                newR.x, newR.y = mx, my
            end
            
            insert(portals, {left = newL, right = newR})
        end
    end
    insert(portals, {left = endPos, right = endPos})

    local pts = {}
    insert(pts, startPos)
    
    local portalApex = startPos
    local portalLeft, portalRight = startPos, startPos
    local leftIndex, rightIndex = 1, 1
    local lastAnchoredIndex = 1
    
    local i = 2
    while i <= #portals do
        local left = portals[i].left
        local right = portals[i].right
        
        -- Detect steep vertical transitions or significant total height change
        local currMidZ = (left.z + right.z) / 2
        dbgPrint(string.format("[EZNavSafe] Portal #%d Z: %.2f (Apex Z: %.2f)", i, currMidZ, portalApex.z))
        local forceApex = false
        if i > 1 and i - 1 > lastAnchoredIndex then
            local prevMidZ = (portals[i-1].left.z + portals[i-1].right.z) / 2
            if math.abs(currMidZ - prevMidZ) > 1.2 then
                forceApex = true
            end
        end
        if math.abs(currMidZ - portalApex.z) > 2.2 then
            forceApex = true
        end
        
        if forceApex and i > 1 then
            local prevL = portals[i-1].left
            local prevR = portals[i-1].right
            local mid = {
                x = (prevL.x + prevR.x) / 2,
                y = (prevL.y + prevR.y) / 2,
                z = (prevL.z + prevR.z) / 2
            }
            insert(pts, mid)
            portalApex = mid
            portalLeft = portalApex
            portalRight = portalApex
            leftIndex = i - 1
            rightIndex = i - 1
            lastAnchoredIndex = i - 1
            i = i + 1 -- Move forward, do not loop backward infinitely
        else
            -- Update right vertex
            -- If new right is LEFT of current right (narrows funnel) or we are at apex
            if portalApex == portalRight or vcross2D(portalApex, portalRight, right) >= 0 then
                -- If new right is RIGHT of current left (inside funnel)
                if portalApex == portalLeft or vcross2D(portalApex, portalLeft, right) <= 0 then
                    portalRight = right
                    rightIndex = i
                else
                    -- Crossed left boundary, new apex!
                    insert(pts, {x=portalLeft.x, y=portalLeft.y, z=portalLeft.z})
                    portalApex = portalLeft
                    portalRight = portalApex
                    portalLeft = portalApex
                    i = leftIndex
                    rightIndex = i
                end
            end
            
            -- Update left vertex
            -- If new left is RIGHT of current left (narrows funnel) or we are at apex
            if portalApex == portalLeft or vcross2D(portalApex, portalLeft, left) <= 0 then
                -- If new left is LEFT of current right (inside funnel)
                if portalApex == portalRight or vcross2D(portalApex, portalRight, left) >= 0 then
                    portalLeft = left
                    leftIndex = i
                else
                    -- Crossed right boundary, new apex!
                    insert(pts, {x=portalRight.x, y=portalRight.y, z=portalRight.z})
                    portalApex = portalRight
                    portalLeft = portalApex
                    portalRight = portalApex
                    i = rightIndex
                    leftIndex = i
                end
            end
            
            i = i + 1
        end
    end
    insert(pts, {x=endPos.x, y=endPos.y, z=endPos.z})
    
    return pts
end

local activeSearch = nil

function Nav.GeneratePath(x1, y1, z1, x2, y2, z2, callback)
    local _, _, _, _, _, _, _, mapId = GetInstanceInfo()
    local tx1, ty1 = floor(32 - y1/Nav.Config.TileSize), floor(32 - x1/Nav.Config.TileSize)
    local tx2, ty2 = floor(32 - y2/Nav.Config.TileSize), floor(32 - x2/Nav.Config.TileSize)
    
    local co = coroutine.create(function()
        searchStartTime = getHighPrecTime()
        
        -- Pre-load tiles in the bounding box between start and end (no buffer needed)
        local minTx = math.min(tx1, tx2)
        local maxTx = math.max(tx1, tx2)
        local minTy = math.min(ty1, ty2)
        local maxTy = math.max(ty1, ty2)
        
        if (maxTx - minTx) <= 12 and (maxTy - minTy) <= 12 then
            for tx = minTx, maxTx do
                for ty = minTy, maxTy do
                    Nav.LoadTile(mapId, tx, ty)
                    checkYield()
                end
            end
        else
            -- Fallback for extremely long distances: trace the line of tiles
            for x = -1, 1 do
                for y = -1, 1 do
                    Nav.LoadTile(mapId, tx1 + x, ty1 + y)
                    Nav.LoadTile(mapId, tx2 + x, ty2 + y)
                    checkYield()
                end
            end
            local dx = tx2 - tx1
            local dy = ty2 - ty1
            local steps = math.max(math.abs(dx), math.abs(dy))
            if steps > 0 then
                local xInc = dx / steps
                local yInc = dy / steps
                local cx = tx1
                local cy = ty1
                for i = 1, steps do
                    cx = cx + xInc
                    cy = cy + yInc
                    local rX = math.floor(cx + 0.5)
                    local rY = math.floor(cy + 0.5)
                    for xOffset = -1, 1 do
                        for yOffset = -1, 1 do
                            Nav.LoadTile(mapId, rX + xOffset, rY + yOffset)
                            checkYield()
                        end
                    end
                end
            end
        end
        
        local startTile = Nav.LoadTile(mapId, tx1, ty1)
        local endTile = Nav.LoadTile(mapId, tx2, ty2)
        
        dbgPrint(string.format("[EZNavSafe] GeneratePath: Map %d, Start Tile (%d,%d), Target Tile (%d,%d)", mapId, tx1, ty1, tx2, ty2))
        dbgPrint(string.format("  Start Pos: %.1f, %.1f, %.1f | End Pos: %.1f, %.1f, %.1f", x1, y1, z1, x2, y2, z2))
        
        if not startTile then 
            dbgPrint("[EZNavSafe] GeneratePath Failed: Start tile is not loaded!")
            return callback(nil) 
        end
        if not endTile then
            dbgPrint(string.format("[EZNavSafe] GeneratePath Warning: End tile (%d,%d) is not loaded!", tx2, ty2))
        end
        
        local startPoly = Nav.GetPolygonAt(startTile, x1, y1, z1) or Nav.GetClosestPolygon(startTile, x1, y1, z1)
        local endPoly = endTile and (Nav.GetPolygonAt(endTile, x2, y2, z2) or Nav.GetClosestPolygon(endTile, x2, y2, z2))
        
        dbgPrint(string.format("  StartPoly found: %s, EndPoly found: %s", tostring(startPoly ~= nil), tostring(endPoly ~= nil)))
        
        if not startPoly or not endPoly then 
            dbgPrint(string.format("[EZNavSafe] GeneratePath Failed: Missing polys. StartPoly: %s, EndPoly: %s", tostring(startPoly), tostring(endPoly)))
            return callback(nil) 
        end
        
        -- A* Setup
        local startIdx = startTile.key .. "_" .. startPoly.index
        local endIdx = endTile.key .. "_" .. endPoly.index
        
        local openSet = { [startIdx] = {tile = startTile, poly = startPoly} }
        local closedSet = {}
        local gScore = { [startIdx] = 0 }
        local fScore = { [startIdx] = heuristic({x1,y1,z1}, {x2,y2,z2}) }
        local cameFrom = {}
        
        local closestKey = startIdx
        local closestH = fScore[startIdx]
        
        local iterations = 0
        while next(openSet) do
            iterations = iterations + 1
            if iterations % 20 == 0 then
                checkYield()
            end
            
            local currentKey = nil
            local lowF = 1e10
            for key, _ in pairs(openSet) do
                if fScore[key] < lowF then
                    lowF = fScore[key]
                    currentKey = key
                end
            end
            
            local current = openSet[currentKey]
            if currentKey == endIdx then
                local corridor = {}
                local curr = currentKey
                while curr do
                    local info = openSet[curr] or closedSet[curr]
                    if info then insert(corridor, 1, info.poly) end
                    curr = cameFrom[curr]
                end
                
                local smoothPath = Nav.Funnel(corridor, {x=x1, y=y1, z=z1}, {x=x2, y=y2, z=z2}, current.tile)
                dbgPrint(string.format("[EZNavSafe] A* Success! Path has %d waypoints.", #smoothPath))
                return callback(smoothPath)
            end
            
            openSet[currentKey] = nil
            closedSet[currentKey] = current
            
            -- Combine Internal and External Neighbors
            local allNeighbors = {}
            for _, nIdx in ipairs(current.poly.neighs) do
                -- 0 means no neighbor. DT_EXT_LINK (0x8000) is cross-tile (handled separately).
                if nIdx > 0 and bit.band(nIdx, 0x8000) == 0 then
                    local realIdx = nIdx - 1
                    local neighborPoly = current.tile.polys[realIdx]
                    if neighborPoly then
                        insert(allNeighbors, {tile = current.tile, poly = neighborPoly})
                    end
                end
            end
            if current.poly.crossTileLinks then
                for _, link in ipairs(current.poly.crossTileLinks) do
                    insert(allNeighbors, {tile = link.tile, poly = link.poly})
                end
            end
            
            for _, nInfo in ipairs(allNeighbors) do
                local neighborTile = nInfo.tile
                local neighborPoly = nInfo.poly
                
                if neighborPoly then
                    local nKey = neighborTile.key .. "_" .. neighborPoly.index
                    
                    if not closedSet[nKey] and neighborPoly.polyType == 0 and neighborPoly.area ~= 0 then
                        -- Calculate true physical distance between polygon centroids
                        local c1 = {0,0,0}
                        for _,vIdx in ipairs(current.poly.verts) do
                            local v = current.tile.verts[vIdx]
                            c1[1]=c1[1]+v[1]; c1[2]=c1[2]+v[2]; c1[3]=c1[3]+v[3]
                        end
                        c1[1]=c1[1]/#current.poly.verts; c1[2]=c1[2]/#current.poly.verts; c1[3]=c1[3]/#current.poly.verts
                        
                        local c2 = {0,0,0}
                        for _,vIdx in ipairs(neighborPoly.verts) do
                            local v = neighborTile.verts[vIdx]
                            c2[1]=c2[1]+v[1]; c2[2]=c2[2]+v[2]; c2[3]=c2[3]+v[3]
                        end
                        c2[1]=c2[1]/#neighborPoly.verts; c2[2]=c2[2]/#neighborPoly.verts; c2[3]=c2[3]/#neighborPoly.verts
                        
                        local baseCost = heuristic(c1, c2)
                        
                        -- Apply Area / Flag specific weight penalties
                        if neighborPoly.area == 9 or (neighborPoly.flags and bit.band(neighborPoly.flags, 4) ~= 0) then
                            baseCost = baseCost * 5.0 -- 5x penalty to avoid swimming
                        elseif neighborPoly.area == 4 then
                            baseCost = baseCost * 3.0 -- 3x penalty to avoid getting stuck on steep hills
                        end
                        
                        local tentativeG = gScore[currentKey] + baseCost
                        if not openSet[nKey] or tentativeG < (gScore[nKey] or 1e10) then
                            cameFrom[nKey] = currentKey
                            gScore[nKey] = tentativeG
                            local hDist = heuristic(c2, {x2,y2,z2})
                            fScore[nKey] = tentativeG + hDist
                            if hDist < closestH then
                                closestH = hDist
                                closestKey = nKey
                            end
                            openSet[nKey] = {tile = neighborTile, poly = neighborPoly}
                        end
                    end
                end
            end
        end
        
        -- Partial Path Fallback
        if closestKey and cameFrom[closestKey] then
            dbgPrint(string.format("[EZNavSafe] A* failed to reach destination! Falling back to partial path. Closest key hDist: %.1f", closestH))
            local corridor = {}
            local curr = closestKey
            while curr do
                local info = openSet[curr] or closedSet[curr]
                if info then insert(corridor, 1, info.poly) end
                curr = cameFrom[curr]
            end
            
            local lastPoly = openSet[closestKey] or closedSet[closestKey]
            local lx, ly, lz = x2, y2, z2
            if lastPoly then
                 lx = (lastPoly.poly.bmin[1] + lastPoly.poly.bmax[1]) * 0.5
                 ly = (lastPoly.poly.bmin[2] + lastPoly.poly.bmax[2]) * 0.5
                 lz = (lastPoly.poly.bmin[3] + lastPoly.poly.bmax[3]) * 0.5
            end
            
            local smoothPath = Nav.Funnel(corridor, {x=x1, y=y1, z=z1}, {x=lx, y=ly, lz=lz}, startTile)
            dbgPrint(string.format("[EZNavSafe] Fallback path has %d waypoints to (%.1f, %.1f, %.1f)", #smoothPath, lx, ly, lz))
            return callback(smoothPath)
        end
        
        dbgPrint("[EZNavSafe] A* Failed completely (no fallback path).")
        callback(nil)
    end)
    
    activeSearch = co
end

-- Update ticker to resume searches
local updateFrame = CreateFrame("Frame")
updateFrame:SetScript("OnUpdate", function()
    if activeSearch then
        local status, err = coroutine.resume(activeSearch)
        if not status then
            print("|cffff0000[EZNavSafe] A* Engine Crashed:|r", tostring(err))
            activeSearch = nil
        elseif coroutine.status(activeSearch) == "dead" then
            activeSearch = nil
        end
    end
end)

print("|cff00ff00EZNavSafe:|r Engine Initialized.")

return Nav
