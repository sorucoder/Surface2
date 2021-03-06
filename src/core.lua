local surf = { }
surface.surf = surf

local table_concat, math_floor, math_atan2 = table.concat, math.floor, math.atan2

local _cc_color_to_hex, _cc_hex_to_color = { }, { }
for i = 0, 15 do
	_cc_color_to_hex[2 ^ i] = string.format("%01x", i)
	_cc_hex_to_color[string.format("%01x", i)] = 2 ^ i
end

local _chars = { }
for i = 0, 255 do
	_chars[i] = string.char(i)
end
local _numstr = { }
for i = 0, 1023 do
	_numstr[i] = tostring(i)
end

local _eprc, _esin, _ecos = 20, { }, { }
for i = 0, _eprc - 1 do
	_esin[i + 1] = (1 - math.sin(i / _eprc * math.pi * 2)) / 2
	_ecos[i + 1] = (1 + math.cos(i / _eprc * math.pi * 2)) / 2
end

local _steps, _palette, _rgbpal, _palr, _palg, _palb = 16

local function calcStack(stack, width, height)
	local ox, oy, cx, cy, cwidth, cheight = 0, 0, 0, 0, width, height
	for i = 1, #stack do
		ox = ox + stack[i].ox
		oy = oy + stack[i].oy
		cx = cx + stack[i].x
		cy = cy + stack[i].y
		cwidth = stack[i].width
		cheight = stack[i].height
	end
	return ox, oy, cx, cy, cwidth, cheight
end

local function clipRect(x, y, width, height, cx, cy, cwidth, cheight)
	if x < cx then
		width = width + x - cx
		x = cx
	end
	if y < cy then
		height = height + y - cy
		y = cy
	end
	if x + width > cx + cwidth then
		width = cwidth + cx - x
	end
	if y + height > cy + cheight then
		height = cheight + cy - y
	end
	return x, y, width, height
end



function surface.create(width, height, b, t, c)
	local surface = setmetatable({ }, {__index = surface.surf})
	surface.width = width
	surface.height = height
	surface.buffer = { }
	surface.overwrite = false
	surface.stack = { }
	surface.ox, surface.oy, surface.cx, surface.cy, surface.cwidth, surface.cheight = calcStack(surface.stack, width, height)
	-- force array indeces instead of hashed indices

	local buffer = surface.buffer
	for i = 1, width * height * 3, 3 do
		buffer[i] = b or false
		buffer[i + 1] = t or false
		buffer[i + 2] = c or false
	end
	buffer[width * height * 3 + 1] = false
	if not b then
		for i = 1, width * height * 3, 3 do
			buffer[i] = b
		end
	end
	if not t then
		for i = 2, width * height * 3, 3 do
			buffer[i] = t
		end
	end
	if not c then
		for i = 3, width * height * 3, 3 do
			buffer[i] = c
		end
	end

	return surface
end

function surface.getPlatformOutput(output)
	output = output or (term or gpu or (love and love.graphics) or io)

	if output.blit and output.setCursorPos then
		return "cc", output, output.getSize()
	elseif output.write and output.setCursorPos and output.setTextColor and output.setBackgroundColor then
		return "cc-old", output, output.getSize()
	elseif output.blitPixels then
		return "riko-4", output, 320, 200
	elseif output.points and output.setColor then
		return "love2d", output, output.getWidth(), output.getHeight()
	elseif output.drawPixel then
		return "redirection", output, 64, 64
	elseif output.setForeground and output.setBackground and output.set then
		return "oc", output, output.getResolution()
	elseif output.write then
		return "ansi", output, (os.getenv and (os.getenv("COLUMNS"))) or 80, (os.getenv and (os.getenv("LINES"))) or 43
	else
		error("unsupported platform/output object")
	end
end

function surf:output(output, x, y, sx, sy, swidth, sheight)
	local platform, output, owidth, oheight = surface.getPlatformOutput(output)

	x = x or 0
	y = y or 0
	sx = sx or 0
	sy = sy or 0
	swidth = swidth or self.width
	sheight = sheight or self.height
	sx, sy, swidth, sheight = clipRect(sx, sy, swidth, sheight, 0, 0, self.width, self.height)

	local buffer = self.buffer
	local bwidth = self.width
	local xoffset, yoffset, idx

	if platform == "cc" then
		-- CC
		local str, text, back = { }, { }, { }
		for j = 0, sheight - 1 do
			yoffset = (j + sy) * bwidth + sx
			for i = 0, swidth - 1 do
				xoffset = (yoffset + i) * 3
				idx = i + 1
				str[idx] = buffer[xoffset + 3] or " "
				text[idx] = _cc_color_to_hex[buffer[xoffset + 2] or 1]
				back[idx] = _cc_color_to_hex[buffer[xoffset + 1] or 32768]
			end
			output.setCursorPos(x + 1, y + j + 1)
			output.blit(table_concat(str), table_concat(text), table_concat(back))
		end

	elseif platform == "cc-old" then
		-- CC pre-1.76
		local str, b, t, pb, pt = { }
		for j = 0, sheight - 1 do
			output.setCursorPos(x + 1, y + j + 1)
			yoffset = (j + sy) * bwidth + sx
			for i = 0, swidth - 1 do
				xoffset = (yoffset + i) * 3
				pb = buffer[xoffset + 1] or 32768
				pt = buffer[xoffset + 2] or 1
				if pb ~= b then
					if #str ~= 0 then
						output.write(table_concat(str))
						str = { }
					end
					b = pb
					output.setBackgroundColor(b)
				end
				if pt ~= t then
					if #str ~= 0 then
						output.write(table_concat(str))
						str = { }
					end
					t = pt
					output.setTextColor(t)
				end
				str[#str + 1] = buffer[xoffset + 3] or " "
			end
			output.write(table_concat(str))
			str = { }
		end

	elseif platform == "riko-4" then
		-- Riko 4
		local pixels = { }
		for j = 0, sheight - 1 do
			yoffset = (j + sy) * bwidth + sx
			for i = 0, swidth - 1 do
				pixels[j * swidth + i + 1] = buffer[(yoffset + i) * 3 + 1] or 0
			end
		end
		output.blitPixels(x, y, swidth, sheight, pixels)

	elseif platform == "love2d" then
		-- Love2D
		local pos, r, g, b, pr, pg, pb = { }
		for j = 0, sheight - 1 do
			yoffset = (j + sy) * bwidth + sx
			for i = 0, swidth - 1 do
				xoffset = (yoffset + i) * 3
				pr = buffer[xoffset + 1]
				pg = buffer[xoffset + 2]
				pb = buffer[xoffset + 3]
				if pr ~= r or pg ~= g or pb ~= b then
					if #pos ~= 0 then
						output.setColor((r or 0) * 255, (g or 0) * 255, (b or 0) * 255, (r or g or b) and 255 or 0)
						output.points(pos)
					end
					r, g, b = pr, pg, pb
					pos = { }
				end
				pos[#pos + 1] = i + x + 1
				pos[#pos + 1] = j + y + 1
			end
		end
		output.setColor((r or 0) * 255, (g or 0) * 255, (b or 0) * 255, (r or g or b) and 255 or 0)
		output.points(pos)

	elseif platform == "redirection" then
		-- Redirection arcade (gpu)
		-- todo: add image:write support for extra performance
		local px = output.drawPixel
		for j = 0, sheight - 1 do
			for i = 0, swidth - 1 do
				px(x + i, y + j, buffer[((j + sy) * bwidth + (i + sx)) * 3 + 1] or 0)
			end
		end

	elseif platform == "oc" then
		-- OpenComputers
		local str, lx, b, t, pb, pt = { }
		for j = 0, sheight - 1 do
			lx = x
			yoffset = (j + sy) * bwidth + sx
			for i = 0, swidth - 1 do
				xoffset = (yoffset + i) * 3
				pb = buffer[xoffset + 1] or 0x000000
				pt = buffer[xoffset + 2] or 0xFFFFFF
				if pb ~= b then
					if #str ~= 0 then
						output.set(lx + 1, j + y + 1, table_concat(str))
						lx = i + x
						str = { }
					end
					b = pb
					output.setBackground(b)
				end
				if pt ~= t then
					if #str ~= 0 then
						output.set(lx + 1, j + y + 1, table_concat(str))
						lx = i + x
						str = { }
					end
					t = pt
					output.setForeground(t)
				end
				str[#str + 1] = buffer[xoffset + 3] or " "
			end
			output.set(lx + 1, j + y + 1, table_concat(str))
			str = { }
		end

	elseif platform == "ansi" then
		-- ANSI terminal
		local str, b, t, pb, pt = { }
		for j = 0, sheight - 1 do
			str[#str + 1] = "\x1b[".._numstr[y + j + 1]..";".._numstr[x + 1].."H"
			yoffset = (j + sy) * bwidth + sx
			for i = 0, swidth - 1 do
				xoffset = (yoffset + i) * 3
				pb = buffer[xoffset + 1] or 0
				pt = buffer[xoffset + 2] or 7
				if pb ~= b then
					b = pb
					if b < 8 then
						str[#str + 1] = "\x1b[".._numstr[40 + b].."m"
					elseif b < 16 then
						str[#str + 1] = "\x1b[".._numstr[92 + b].."m"
					elseif b < 232 then
						str[#str + 1] = "\x1b[48;2;".._numstr[math_floor((b - 16) / 36 * 85 / 2)]..";".._numstr[math_floor((b - 16) / 6 % 6 * 85 / 2)]..";".._numstr[math_floor((b - 16) % 6 * 85 / 2)].."m"
					else
						local gr = _numstr[b * 10 - 2312]
						str[#str + 1] = "\x1b[48;2;"..gr..";"..gr..";"..gr.."m"
					end
				end
				if pt ~= t then
					t = pt
					if t < 8 then
						str[#str + 1] = "\x1b[".._numstr[30 + t].."m"
					elseif t < 16 then
						str[#str + 1] = "\x1b[".._numstr[82 + t].."m"
					elseif t < 232 then
						str[#str + 1] = "\x1b[38;2;".._numstr[math_floor((t - 16) / 36 * 85 / 2)]..";".._numstr[math_floor((t - 16) / 6 % 6 * 85 / 2)]..";".._numstr[math_floor((t - 16) % 6 * 85 / 2)].."m"
					else
						local gr = _numstr[t * 10 - 2312]
						str[#str + 1] = "\x1b[38;2;"..gr..";"..gr..";"..gr.."m"
					end
				end
				str[#str + 1] = buffer[xoffset + 3] or " "
			end
		end
		output.write(table_concat(str))
	end
end

function surf:push(x, y, width, height, nooffset)
	x, y = x + self.ox, y + self.oy

	local ox, oy = nooffset and self.ox or x, nooffset and self.oy or y
	x, y, width, height = clipRect(x, y, width, height, self.cx, self.cy, self.cwidth, self.cheight)
	self.stack[#self.stack + 1] = {ox = ox - self.ox, oy = oy - self.oy, x = x - self.cx, y = y - self.cy, width = width, height = height}

	self.ox, self.oy, self.cx, self.cy, self.cwidth, self.cheight = calcStack(self.stack, self.width, self.height)
end

function surf:pop()
	if #self.stack == 0 then
		error("no stencil to pop")
	end
	self.stack[#self.stack] = nil
	self.ox, self.oy, self.cx, self.cy, self.cwidth, self.cheight = calcStack(self.stack, self.width, self.height)
end

function surf:copy()
	local surface = setmetatable({ }, {__index = surface.surf})

	for k, v in pairs(self) do
		surface[k] = v
	end

	surface.buffer = { }
	for i = 1, self.width * self.height * 3 + 1 do
		surface.buffer[i] = false
	end
	for i = 1, self.width * self.height * 3 do
		surface.buffer[i] = self.buffer[i]
	end

	surface.stack = { }
	for i = 1, #self.stack do
		surface.stack[i] = self.stack[i]
	end

	return surface
end

function surf:resize(width, height, b, t, c)
	local newbuffer = { }
	for y = 0, height - 1 do
		for x = 0, width - 1 do
			if (x >= 0 and x < self.width) and (y >= 0 and y < self.height) then
				newbuffer[3 * (y * width + x) + 1] = self.buffer[3 * (y * self.width + x) + 1]
				newbuffer[3 * (y * width + x) + 2] = self.buffer[3 * (y * self.width + x) + 2]
				newbuffer[3 * (y * width + x) + 3] = self.buffer[3 * (y * self.width + x) + 3]
			else
				if b or self.overwrite then
					newbuffer[3 * (y * width + x) + 1] = b
				end
				if t or self.overwrite then
					newbuffer[3 * (y * width + x) + 2] = t
				end
				if c or self.overwrite then
					newbuffer[3 * (y * width + x) + 3] = c
				end
			end
		end
	end
	newbuffer[3 * width * height + 1] = false

	self.buffer = newbuffer
	self.width, self.cwidth = width, width
	self.height, self.cheight = height, height
end

function surf:clear(b, t, c)
	local xoffset, yoffset

	for j = 0, self.cheight - 1 do
		yoffset = (j + self.cy) * self.width + self.cx
		for i = 0, self.cwidth - 1 do
			xoffset = (yoffset + i) * 3
			self.buffer[xoffset + 1] = b
			self.buffer[xoffset + 2] = t
			self.buffer[xoffset + 3] = c
		end
	end
end

function surf:drawPixel(x, y, b, t, c)
	x, y = x + self.ox, y + self.oy

	local idx
	if x >= self.cx and x < self.cx + self.cwidth and y >= self.cy and y < self.cy + self.cheight then
		idx = (y * self.width + x) * 3
		if b or self.overwrite then
			self.buffer[idx + 1] = b
		end
		if t or self.overwrite then
			self.buffer[idx + 2] = t
		end
		if c or self.overwrite then
			self.buffer[idx + 3] = c
		end
	end
end

function surf:drawString(str, x, y, b, t)
	x, y = x + self.ox, y + self.oy

	local sx = x
	local insidey = y >= self.cy and y < self.cy + self.cheight
	local idx
	local lowerxlim = self.cx
	local upperxlim = self.cx + self.cwidth
	local writeb = b or self.overwrite
	local writet = t or self.overwrite

	for i = 1, #str do
		local c = str:sub(i, i)
		if c == "\n" then
			x = sx
			y = y + 1
			if insidey then
				if y >= self.cy + self.cheight then
					return
				end
			else
				insidey = y >= self.cy
			end
		else
			idx = (y * self.width + x) * 3
			if x >= lowerxlim and x < upperxlim and insidey then
				if writeb then
					self.buffer[idx + 1] = b
				end
				if writet then
					self.buffer[idx + 2] = t
				end
				self.buffer[idx + 3] = c
			end
			x = x + 1
		end
	end
end
