local Visuals = {}
Visuals.__index = Visuals

local function getBoxVertices(pos, mins, maxs)
	if not (pos and mins and maxs) then
		return nil
	end

	local worldMins = pos + mins
	local worldMaxs = pos + maxs

	return {
		Vector3(worldMins.x, worldMins.y, worldMins.z),
		Vector3(worldMins.x, worldMaxs.y, worldMins.z),
		Vector3(worldMaxs.x, worldMaxs.y, worldMins.z),
		Vector3(worldMaxs.x, worldMins.y, worldMins.z),
		Vector3(worldMins.x, worldMins.y, worldMaxs.z),
		Vector3(worldMins.x, worldMaxs.y, worldMaxs.z),
		Vector3(worldMaxs.x, worldMaxs.y, worldMaxs.z),
		Vector3(worldMaxs.x, worldMins.y, worldMaxs.z),
	}
end

local function xyuv(point, u, v)
	return { point[1], point[2], u, v }
end

local function hsvToRgb(hue, saturation, value)
	if saturation == 0 then
		return value, value, value
	end

	local hueSector = math.floor(hue / 60)
	local hueSectorOffset = (hue / 60) - hueSector

	local p = value * (1 - saturation)
	local q = value * (1 - saturation * hueSectorOffset)
	local t = value * (1 - saturation * (1 - hueSectorOffset))

	if hueSector == 0 then
		return value, t, p
	elseif hueSector == 1 then
		return q, value, p
	elseif hueSector == 2 then
		return p, value, t
	elseif hueSector == 3 then
		return p, q, value
	elseif hueSector == 4 then
		return t, p, value
	else
		return value, p, q
	end
end

local function drawQuadFace(texture, a, b, c, d)
	if not (texture and a and b and c and d) then
		return
	end

	local poly = {
		xyuv(a, 0, 0),
		xyuv(b, 1, 0),
		xyuv(c, 1, 1),
		xyuv(d, 0, 1),
	}

	draw.TexturedPolygon(texture, poly, true)
end

local function drawLine(texture, p1, p2, thickness)
	if not (texture and p1 and p2) then
		return
	end

	local dx = p2[1] - p1[1]
	local dy = p2[2] - p1[2]
	local len = math.sqrt(dx * dx + dy * dy)
	if len <= 0 then
		return
	end

	dx = dx / len
	dy = dy / len
	local px = -dy * thickness
	local py = dx * thickness

	local verts = {
		{ p1[1] + px, p1[2] + py, 0, 0 },
		{ p1[1] - px, p1[2] - py, 0, 1 },
		{ p2[1] - px, p2[2] - py, 1, 1 },
		{ p2[1] + px, p2[2] + py, 1, 0 },
	}

	draw.TexturedPolygon(texture, verts, false)
end

local function drawPlayerPath(self)
	local playerPath = self.paths.player_path
	if not playerPath or #playerPath < 2 then
		return
	end

	local last = client.WorldToScreen(playerPath[1])
	if not last then
		return
	end

	for i = 2, #playerPath do
		local current = client.WorldToScreen(playerPath[i])
		if current and last then
			drawLine(self.texture, last, current, self.settings.thickness.player_path)
		end
		last = current
	end
end

local function drawProjPath(self)
	local projPath = self.paths.proj_path
	if not projPath or #projPath < 2 then
		return
	end

	local first = projPath[1]
	local last = first and first.pos and client.WorldToScreen(first.pos)
	if not last then
		return
	end

	for i = 2, #projPath do
		local entry = projPath[i]
		local current = entry and entry.pos and client.WorldToScreen(entry.pos)
		if current and last then
			drawLine(self.texture, last, current, self.settings.thickness.projectile_path)
		end
		last = current
	end
end

local function drawMultipointTarget(self)
	local pos = self.multipoint_target_pos
	if not pos then
		return
	end

	local screen = client.WorldToScreen(pos)
	if not screen then
		return
	end

	local s = self.settings.thickness.multipoint_target
	local verts = {
		{ screen[1] - s, screen[2] - s, 0, 0 },
		{ screen[1] + s, screen[2] - s, 1, 0 },
		{ screen[1] + s, screen[2] + s, 1, 1 },
		{ screen[1] - s, screen[2] + s, 0, 1 },
	}

	draw.TexturedPolygon(self.texture, verts, false)
end

local function isFaceVisible(normal, faceCenter, eyePos)
	if not (normal and faceCenter and eyePos) then
		return true
	end

	local toEye = Vector3(eyePos.x - faceCenter.x, eyePos.y - faceCenter.y, eyePos.z - faceCenter.z)
	local dot = (toEye.x * normal.x) + (toEye.y * normal.y) + (toEye.z * normal.z)
	return dot > 0
end

local function drawPlayerHitbox(self, playerPos)
	if not playerPos then
		return
	end

	local mins = self.target_min_hull
	local maxs = self.target_max_hull
	if not (mins and maxs) then
		return
	end

	local worldMins = playerPos + mins
	local worldMaxs = playerPos + maxs

	local corners = {
		Vector3(worldMins.x, worldMins.y, worldMins.z),
		Vector3(worldMins.x, worldMaxs.y, worldMins.z),
		Vector3(worldMaxs.x, worldMaxs.y, worldMins.z),
		Vector3(worldMaxs.x, worldMins.y, worldMins.z),
		Vector3(worldMins.x, worldMins.y, worldMaxs.z),
		Vector3(worldMins.x, worldMaxs.y, worldMaxs.z),
		Vector3(worldMaxs.x, worldMaxs.y, worldMaxs.z),
		Vector3(worldMaxs.x, worldMins.y, worldMaxs.z),
	}

	local projected = {}
	for i = 1, 8 do
		projected[i] = client.WorldToScreen(corners[i])
	end

	for i = 1, 8 do
		if not projected[i] then
			return
		end
	end

	local edges = {
		{ 1, 2 },
		{ 2, 3 },
		{ 3, 4 },
		{ 4, 1 },
		{ 5, 6 },
		{ 6, 7 },
		{ 7, 8 },
		{ 8, 5 },
		{ 1, 5 },
		{ 2, 6 },
		{ 3, 7 },
		{ 4, 8 },
	}

	local thickness = self.settings.thickness.bounding_box
	for _, edge in ipairs(edges) do
		local a = projected[edge[1]]
		local b = projected[edge[2]]
		if a and b then
			drawLine(self.texture, a, b, thickness)
		end
	end
end

local function drawQuads(self, pos)
	if not (pos and self.target_min_hull and self.target_max_hull and self.eye_pos) then
		return
	end

	local worldMins = pos + self.target_min_hull
	local worldMaxs = pos + self.target_max_hull
	local midX = (worldMins.x + worldMaxs.x) * 0.5
	local midY = (worldMins.y + worldMaxs.y) * 0.5
	local midZ = (worldMins.z + worldMaxs.z) * 0.5

	local vertices = getBoxVertices(pos, self.target_min_hull, self.target_max_hull)
	if not vertices then
		return
	end

	local projected = {}
	for index, vertex in ipairs(vertices) do
		projected[index] = client.WorldToScreen(vertex)
	end

	local faces = {
		{
			indices = { 1, 2, 3, 4 },
			normal = Vector3(0, 0, -1),
			center = Vector3(midX, midY, worldMins.z)
		},
		{
			indices = { 5, 6, 7, 8 },
			normal = Vector3(0, 0, 1),
			center = Vector3(midX, midY, worldMaxs.z)
		},
		{
			indices = { 2, 3, 7, 6 },
			normal = Vector3(0, 1, 0),
			center = Vector3(midX, worldMaxs.y, midZ)
		},
		{
			indices = { 1, 4, 8, 5 },
			normal = Vector3(0, -1, 0),
			center = Vector3(midX, worldMins.y, midZ)
		},
		{
			indices = { 1, 2, 6, 5 },
			normal = Vector3(-1, 0, 0),
			center = Vector3(worldMins.x, midY, midZ)
		},
		{
			indices = { 4, 3, 7, 8 },
			normal = Vector3(1, 0, 0),
			center = Vector3(worldMaxs.x, midY, midZ)
		}
	}

	for _, face in ipairs(faces) do
		if isFaceVisible(face.normal, face.center, self.eye_pos) then
			local idx = face.indices
			local a, b, c, d = projected[idx[1]], projected[idx[2]], projected[idx[3]], projected[idx[4]]
			if a and b and c and d then
				drawQuadFace(self.texture, a, b, c, d)
			end
		end
	end
end

function Visuals.new(settings)
	local instance = setmetatable({}, Visuals)
	instance.settings = settings
	instance.texture = draw.CreateTextureRGBA(string.char(255, 255, 255, 255), 1, 1)
	instance.paths = {
		player_path = {},
		proj_path = {},
	}
	instance.displayed_time = 0
	instance.target_min_hull = Vector3()
	instance.target_max_hull = Vector3()
	instance.eye_pos = nil

	return instance
end

function Visuals:update_paths(playerPath, projPath)
	self.paths.player_path = playerPath or {}
	self.paths.proj_path = projPath or {}
end

function Visuals:set_multipoint_target(pos)
	self.multipoint_target_pos = pos
end

function Visuals:set_target_hull(mins, maxs)
	self.target_min_hull = mins or Vector3()
	self.target_max_hull = maxs or Vector3()
end

function Visuals:set_eye_position(pos)
	self.eye_pos = pos
end

function Visuals:set_displayed_time(time)
	self.displayed_time = time or 0
end

function Visuals:clear()
	self.paths.player_path = {}
	self.paths.proj_path = {}
	self.multipoint_target_pos = nil
	self.eye_pos = nil
end

function Visuals:draw()
	if not self.settings.enabled then
		return
	end

	if not self.displayed_time or self.displayed_time < globals.CurTime() then
		self:clear()
		return
	end

	local settings = self.settings
	local playerPath = self.paths.player_path

	if settings.draw_player_path and playerPath and #playerPath > 0 then
		if settings.colors.player_path >= 360 then
			draw.Color(255, 255, 255, 255)
		else
			local r, g, b = hsvToRgb(settings.colors.player_path, 0.5, 1)
			draw.Color((r * 255) // 1, (g * 255) // 1, (b * 255) // 1, 255)
		end

		drawPlayerPath(self)
	end

	if settings.draw_bounding_box and playerPath and #playerPath > 0 then
		local pos = playerPath[#playerPath]
		if pos then
			if settings.colors.bounding_box >= 360 then
				draw.Color(255, 255, 255, 255)
			else
				local r, g, b = hsvToRgb(settings.colors.bounding_box, 0.5, 1)
				draw.Color((r * 255) // 1, (g * 255) // 1, (b * 255) // 1, 255)
			end

			drawPlayerHitbox(self, pos)
		end
	end

	if settings.draw_proj_path and self.paths.proj_path and #self.paths.proj_path > 0 then
		if settings.colors.projectile_path >= 360 then
			draw.Color(255, 255, 255, 255)
		else
			local r, g, b = hsvToRgb(settings.colors.projectile_path, 0.5, 1)
			draw.Color((r * 255) // 1, (g * 255) // 1, (b * 255) // 1, 255)
		end

		drawProjPath(self)
	end

	if settings.draw_multipoint_target then
		if settings.colors.multipoint_target >= 360 then
			draw.Color(255, 255, 255, 255)
		else
			local r, g, b = hsvToRgb(settings.colors.multipoint_target, 0.5, 1)
			draw.Color((r * 255) // 1, (g * 255) // 1, (b * 255) // 1, 255)
		end

		drawMultipointTarget(self)
	end

	if settings.draw_quads and playerPath and #playerPath > 0 then
		local pos = playerPath[#playerPath]
		if pos then
			if settings.colors.quads >= 360 then
				draw.Color(255, 255, 255, 25)
			else
				local r, g, b = hsvToRgb(settings.colors.quads, 0.5, 1)
				draw.Color((r * 255) // 1, (g * 255) // 1, (b * 255) // 1, 25)
			end

			drawQuads(self, pos)
		end
	end
end

function Visuals:destroy()
	if self.texture then
		draw.DeleteTexture(self.texture)
		self.texture = nil
	end
end

return Visuals
