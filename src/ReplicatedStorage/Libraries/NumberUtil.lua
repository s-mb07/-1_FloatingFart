--!strict
--[[
	@module NumberUtil
	@description Utility for formatting large numbers (K, M, B, T, Qa, etc.).
	Uses a "decreasing" decimal display for a premium look:
	- x < 10  -> 2 decimals (e.g. 1.25M)
	- x < 100 -> 1 decimal  (e.g. 12.5M)
	- x >= 100 -> 0 decimals (e.g. 125M)
]]

local NumberUtil = {}

type SuffixEntry = { value: number, suffix: string }

local SUFFIXES: { SuffixEntry } = {
	{ value = 10^33, suffix = "Dc" }, -- Decillion
	{ value = 10^30, suffix = "No" }, -- Nonillion
	{ value = 10^27, suffix = "Oc" }, -- Octillion
	{ value = 10^24, suffix = "Sp" }, -- Septillion
	{ value = 10^21, suffix = "Sx" }, -- Sextillion
	{ value = 10^18, suffix = "Qi" }, -- Quintillion
	{ value = 10^15, suffix = "Qa" }, -- Quadrillion
	{ value = 10^12, suffix = "T" },  -- Trillion
	{ value = 10^9,  suffix = "B" },  -- Billion
	{ value = 10^6,  suffix = "M" },  -- Million
	{ value = 10^3,  suffix = "K" },  -- Thousand
}

--- Formats a number with commas (e.g. 125000 -> 125,000)
local function formatCommas(n: number): string
	local s = tostring(math.floor(n))
	return s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
end

--- Formats a number with suffixes and decreasing dynamic precision
--- @param n number The number to format
--- @return string The formatted number
function NumberUtil.Format(n: number): string
	n = math.floor(n)

	-- Only abbreviate from 10,000,000 (10M) upward
	if n < 10000000 then
		return formatCommas(n)
	end

	for _, data in ipairs(SUFFIXES) do
		local val = data.value
		local suffix = data.suffix

		-- Skip suffixes below a million (K)
		if val < 1000000 then continue end

		if n >= val then
			local raw = n / val
			local precision = 0

			if raw < 10 then
				precision = 2
			elseif raw < 100 then
				precision = 1
			end

			-- Floor to the requested precision
			local factor = 10 ^ precision
			local result = math.floor(raw * factor) / factor

			-- Cleaning up unnecessary .0
			if result % 1 == 0 then
				return string.format("%d%s", result, suffix)
			else
				return string.format("%." .. precision .. "f%s", result, suffix)
			end
		end
	end
	
	return formatCommas(n)
end

--- Like Format, but abbreviates from 1,000 (K) instead of 10,000,000 -- for
--- space-constrained UI (e.g. Skill Tree node prices) where even "20,000"
--- doesn't fit in the label.
function NumberUtil.FormatCompact(n: number): string
	n = math.floor(n)
	if n < 1000 then
		return tostring(n)
	end

	for _, data in ipairs(SUFFIXES) do
		if n >= data.value then
			local raw = n / data.value
			local precision = raw < 10 and 2 or (raw < 100 and 1 or 0)
			local factor = 10 ^ precision
			local result = math.floor(raw * factor) / factor

			if result % 1 == 0 then
				return string.format("%d%s", result, data.suffix)
			end
			return string.format("%." .. precision .. "f%s", result, data.suffix)
		end
	end

	return tostring(n)
end

--- FormatCompact without trailing zeros: 1200 -> "1.2K", 6500 -> "6.5K", 5000 -> "5K".
function NumberUtil.FormatShort(n: number): string
	local text = NumberUtil.FormatCompact(n)
	return (text:gsub("(%.%d-)0+(%a+)$", "%1%2"):gsub("%.(%a+)$", "%1"))
end

return NumberUtil
