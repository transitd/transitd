--- @module bit128
local bit128 = {}

local bit32 = require("bit32")

function bit128.band(a,b)
	local result = {}
	for i=1,4 do
		result[i] = bit32.band(a[i],b[i])
	end
	return result
end

function bit128.bor(a,b)
	local result = {}
	for i=1,4 do
		result[i] = bit32.bor(a[i],b[i])
	end
	return result
end

function bit128.bnot(a)
	local result = {}
	for i=1,4 do
		result[i] = bit32.bnot(a[i])
	end
	return result
end

function bit128.lshift(a, disp)
	local result = {}
	local shiftcells =  math.floor(disp / 32)
	local shiftleftover = disp - shiftcells * 32
	local shiftleftover_width = 32 - shiftleftover
	for i=1,4 do
		local cell = 0;
		local celli = i+shiftcells
		if celli <= 4 then
			cell = bit32.bor(cell, bit32.lshift(bit32.extract(a[celli], shiftleftover, shiftleftover_width), shiftleftover))
		end
		if celli+1 <= 4 and shiftleftover > 0 then
			cell = bit32.bor(cell, bit32.extract(a[celli], 0, shiftleftover))
		end
		result[i] = cell
	end
	return result
end

return bit128
