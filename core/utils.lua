local Nn, GWB, utils = ...

GWB.Utils = {}

-- Unwrap retail "secret number" values (UnitHealth, UnitPower, etc.)
-- On Classic these are plain numbers so this is a no-op.
function GWB.Utils.SafeNumber(val)
    if val == nil then return 0 end
    
    local isSecret = false
    -- Try the global or Nn table versions of issecretvalue
    if issecretvalue and issecretvalue(val) then isSecret = true end
    if Nn and Nn.issecretvalue and Nn.issecretvalue(val) then isSecret = true end
    
    local unwrapFn = secretunwrap or (Nn and Nn.secretunwrap)
    
    if isSecret and unwrapFn then
        return unwrapFn(val) or 0
    end
    
    -- If we couldn't confidently determine it's secret but it's not a number, 
    -- try to unwrap it anyway via pcall just in case.
    if type(val) ~= "number" and unwrapFn then
        local ok, unwrapped = pcall(unwrapFn, val)
        if ok and unwrapped ~= nil then
            return unwrapped
        end
    end
    
    -- Fallback for anything else (Classic WoW normal numbers)
    return tonumber(val) or val
end

function GWB.Utils:Distance(x, y, z, xx, yy, zz)
    if not xx or not x then return end 
    if not zz or not z then return end
    return sqrt((x - xx) ^ 2 + (y - yy) ^ 2 + (z - zz) ^ 2)
end

function GWB:GetDistanceBetweenPositions(x, y, z, xx, yy, zz)
    if not xx or not x then return end 
    return sqrt((x - xx) ^ 2 + (y - yy) ^ 2 + (z - zz) ^ 2)
end

function GWB:GetFacing(px, py, tx, ty)
	local px2, py2 -- point north of player
	px2 = px + 15
	py2 = py

	if px == nil or tx == nil then
		return -1
	end

	local a = GWB:GetDistanceBetweenPositions(px2, py2, 0, tx, ty, 0)
	local b = GWB:GetDistanceBetweenPositions(px, py, 0, tx, ty, 0)
	local c = GWB:GetDistanceBetweenPositions(px, py, 0, px2, py2, 0)
	local numerator = (b ^ 2) + (c ^ 2) - (a ^ 2)

	if a == nil or b == nil or c == nil then
		return -1
	end

	local denominator = 2 * b * c
	if denominator == 0 then
		return 
	end
	local angle = math.acos(numerator / denominator)
	if ty < py then
		angle = 2 * math.pi - angle
	end
	return angle
end

function GWB:calculateThirdDot(x1, y1, x2, y2, distance)
	-- Calculate the vector from Dot 1 to Dot 2
	local vector_x = x2 - x1
	local vector_y = y2 - y1

	-- Calculate the magnitude of the vector
	local magnitude = math.sqrt(vector_x^2 + vector_y^2)

	-- Normalize the vector (unit vector)
	local unit_vector_x = vector_x / magnitude
	local unit_vector_y = vector_y / magnitude

	-- Scale the unit vector by the distance (5 units in this case)
	local scaled_vector_x = unit_vector_x * distance
	local scaled_vector_y = unit_vector_y * distance

	-- Calculate the coordinates of the third dot
	local x3 = x1 + scaled_vector_x
	local y3 = y1 + scaled_vector_y

	return x3, y3
end

function GWB.Utils:FacingAdd(f, value)
    local maxval = math.pi * 2
    local newf = f + value
    if newf > maxval then
        newf = maxval - newf
    elseif newf < 0 then
        newf = maxval - (newf*-1)
    end
    return newf
end

local lastUpdate = GetTime()

function GWB:UpdateFacingTarget()
    local tick = GetTime()
    if lastUpdate + 0.5 > tick then
        return
    end
    local px, py, _ = ObjectPosition("player")
    local tx, ty, _ = ObjectPosition("target")
    if px ~= nil and tx ~= nil then
        lastUpdate = tick
        local f = GWB:GetFacing(px, py, tx, ty)
        SetPlayerFacing(f)
    end
end

-- auto update facing for current target
function GWB:AutoTarget()
    if not Objects or not GetFocus then return end
    local os = Objects()
    local old = GetFocus()
    for i=1, #os do
        local o = os[i]
        if ObjectType(o) == 5 then
            Nn.SetFocus(o)
            if focus.alive and focus.enemy and focus.exists and CheckInteractDistance("focus", 1)  then
                Unlock(TargetUnit, "focus")
                --print('setting focus', focus.name)
                Nn.SetFocus(old)
                GWB:UpdateFacingTarget()
                return
            end
        end

    end
    Nn.SetFocus(old)
end

-- find closes object to a given XYZ
-- return [object, distance] (nil, 9999)
function GWB.Utils:GetClosestObject(objects, x, y, z)
	local dist = 5000
	local object = nil

	for i=1, #objects do
		local o = objects[i]
		local ox, oy, oz = ObjectPosition(o)

		local d = 4999.99
		if z == nil then
			d = GWB.Utils:Distance(ox, oy, 0, x, y, 0)
		else
            GWB:Debug("xxx", oz, z)
			d = GWB.Utils:Distance(ox, oy, oz, x, y, z)
		end

		if d < dist then
			dist = d
			object = o
		end
	end

	return object, dist
end

function GWB:SliceFromNearest(target, pointList)
	local function distanceSquared(p1, p2)
		local dx = p1.x - p2.x
		local dy = p1.y - p2.y
		local dz = p1.z - p2.z
		return dx * dx + dy * dy + dz * dz
	end

	local function lerp(a, b, t)
		return {
			x = a.x + (b.x - a.x) * t,
			y = a.y + (b.y - a.y) * t,
			z = a.z + (b.z - a.z) * t
		}
	end

	local nearestIndex = nil
	local nearestT = 0
	local minDistSq = math.huge
	local step = 0.1 -- resolution of sampling along segments

	for i = 1, #pointList - 1 do
		local a = pointList[i]
		local b = pointList[i + 1]

		for t = 0, 1, step do
			local sample = lerp(a, b, t)
			local distSq = distanceSquared(target, sample)

			if distSq <= 25 then -- within 5 units
				-- Always prefer higher index (i), or later t within same segment
				if i > (nearestIndex or -1) or (i == nearestIndex and t > nearestT) then
					nearestIndex = i
					nearestT = t
					minDistSq = distSq
				end
			end
		end
	end

	-- fallback: if no sampled point is within range, just pick closest real point
	if not nearestIndex then
		for i = 1, #pointList do
			local distSq = distanceSquared(target, pointList[i])
			if distSq < minDistSq then
				minDistSq = distSq
				nearestIndex = i
				nearestT = 0
			end
		end
	end

	-- Build the final sliced path from the interpolated point to the end
	local result = {}

	-- Add the interpolated start point
	local startPoint = lerp(pointList[nearestIndex], pointList[nearestIndex + 1] or pointList[nearestIndex], nearestT)
	table.insert(result, startPoint)

	-- Add all remaining points after that segment
	for i = nearestIndex + 1, #pointList do
		table.insert(result, pointList[i])
	end

	-- Optionally: deduplicate close points (like you did before)
	-- You can reuse the distance check grouping if needed

	return result
end
-- Function to get sublist starting from nearest point
function GWB:SliceFromNearest_dot(target, pointList)
	local function distanceSquared(p1, p2)
		local dx = p1.x - p2.x
		local dy = p1.y - p2.y
		local dz = p1.z - p2.z
		return dx * dx + dy * dy + dz * dz
	end

	-- Find highest index within 5 units of target
	local nearestIndex = nil
	for i = 1, #pointList do
		if distanceSquared(target, pointList[i]) <= 6^2 then
			nearestIndex = i
		end
	end

	-- fallback to true nearest if none are within 5 units
	if not nearestIndex then
		local minDistSq = math.huge
		for i, point in ipairs(pointList) do
			local distSq = distanceSquared(target, point)
			if distSq < minDistSq then
				minDistSq = distSq
				nearestIndex = i
			end
		end
	end

	-- Group filter: take only the last point in each group of close points
	local result = {}
	local i = nearestIndex

	while i <= #pointList do
		local groupStart = pointList[i]
		local groupEnd = groupStart
		local j = i + 1

		while j <= #pointList and distanceSquared(pointList[j], groupStart) <= 6^2 do
			groupEnd = pointList[j]
			j = j + 1
		end

		table.insert(result, groupEnd)
		i = j
	end

	return result
end

function GWB:Distance3D(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

function GWB:ClosestPoint(ref, list)
  if not ref or not list or #list == 0 then
    return nil, nil, nil
  end

  local bestObj = nil
  local bestIdx = nil
  local bestDistSq = math.huge

  local rx, ry, rz = ref.x, ref.y, ref.z

  for i = 1, #list do
    local p = list[i]
    if p and p.x and p.y and p.z then
      local dx = p.x - rx
      local dy = p.y - ry
      local dz = p.z - rz
      local d2 = dx*dx + dy*dy + dz*dz

      if d2 < bestDistSq then
        bestDistSq = d2
        bestObj = p
        bestIdx = i
      end
    end
  end

  return bestObj, bestIdx, bestDistSq
end

function GWB:FindNearestPoint(target, pointList)
	local function distanceSquared(p1, p2)
		local dx = p1.x - p2.x
		local dy = p1.y - p2.y
		local dz = p1.z - p2.z
		return dx * dx + dy * dy + dz * dz
	end

    local nearest = nil
    local minDistSq = math.huge

    for _, point in ipairs(pointList) do
        local distSq = distanceSquared(target, point)
        if distSq < minDistSq then
            minDistSq = distSq
            nearest = point
        end
    end

    return nearest
end

function GWB:CleanPath(path)
	local fixedPath = {}
    if type(path[1].x) == "string" then
        for i=1, #path do
            fixedPath[i] = { ['x']=tonumber(path[i].x), ['y']=tonumber(path[i].y), ['z']=tonumber(path[i].z) }
        end
    else
        fixedPath = path
    end
	return fixedPath
end

function GWB:CalcPathLength(path)
    if #path == 0 then
        return 0
    end

    -- fix path if needed
    local fixedPath = GWB:CleanPath(path) -- test?

    -- perform calculation on path
    local cumDist = 0
    for i=1, #fixedPath-1 do
        local p1 = fixedPath[i]
        local p2 = fixedPath[i+1]
        -- TODO; check if xyz's are OK?
        GWB:Debug(p1.z, p2.z)
        cumDist = cumDist + GWB.Utils:Distance(p1.x, p1.y, p1.z, p2.x, p2.y, p2.z)
    end

    return cumDist
end

function GWB:IsRangeSpec()
	local rangedSpecs = {
		[62] = true,  -- Arcane Mage
		[63] = true,  -- Fire Mage
		[64] = true,  -- Frost Mage
		[253] = true, -- Beast Mastery Hunter
		[254] = true, -- Marksmanship Hunter
		[255] = true, -- Survival Hunter (in MoP = ranged)
		[102] = true, -- Balance Druid
		[262] = true, -- Elemental Shaman
		[265] = true, -- Affliction Warlock
		[266] = true, -- Demonology Warlock
		[267] = true, -- Destruction Warlock
		[258] = true, -- Shadow Priest
	}

	local GetSpecialization = _G.GetSpecialization or C_SpecializationInfo.GetSpecialization
	local GetSpecializationInfo = _G.GetSpecializationInfo or C_SpecializationInfo.GetSpecializationInfo

	local specIndex = GetSpecialization()
	local specID = GetSpecializationInfo(specIndex)

	return rangedSpecs[specID]
end

-- is lootable?