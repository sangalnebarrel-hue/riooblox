-- Number, percentage and time formatting for kit screens. Pure: no services.
local Format = {}

local SUFFIXES = { "K", "M", "B", "T", "Qa", "Qi" }
local EPSILON = 1e-6

-- "12.50" -> "12.5", "3.00" -> "3".
local function trimZeros(s: string): string
	if string.find(s, ".", 1, true) then
		s = string.gsub(s, "0+$", "")
		s = string.gsub(s, "%.$", "")
	end
	return s
end

-- Truncates toward zero to `decimals` places. The epsilon absorbs float noise
-- (1.23e6 / 1e6 = 1.2299999 must still show 1.23).
local function truncate(value: number, decimals: number): number
	local m = 10 ^ decimals
	return math.floor(value * m + EPSILON) / m
end

local function special(n: number): string?
	if n ~= n then
		return "—"
	elseif n == math.huge then
		return "∞"
	elseif n == -math.huge then
		return "-∞"
	end
	return nil
end

-- 1234567 -> "1,234,567" (truncated toward zero, like PriceFormat.Number for positive values).
function Format.Number(value: any): string
	local n = tonumber(value)
	if n == nil then
		return "—"
	end
	local bad = special(n)
	if bad then
		return bad
	end
	local digits = string.format("%.0f", math.floor(math.abs(n) + EPSILON))
	local grouped = string.gsub(string.reverse(digits), "(%d%d%d)", "%1,")
	grouped = string.gsub(string.reverse(grouped), "^,", "")
	if n < 0 and grouped ~= "0" then
		return "-" .. grouped
	end
	return grouped
end

-- Compact amount: 999 -> "999", 1234 -> "1.23K", 12345 -> "12.3K", 1.5e6 -> "1.5M", 2e12 -> "2T".
-- Three significant digits, truncated (never shows more than the player has).
-- smallDecimals: decimals kept below 1000 (Short(2.5, 1) -> "2.5"); default 0.
function Format.Short(value: any, smallDecimals: number?): string
	local n = tonumber(value)
	if n == nil then
		return "—"
	end
	local bad = special(n)
	if bad then
		return bad
	end
	local sign = n < 0 and "-" or ""
	local a = math.abs(n)
	if a < 1000 then
		local s
		if smallDecimals and smallDecimals > 0 then
			s = trimZeros(string.format("%." .. math.floor(smallDecimals) .. "f", truncate(a, smallDecimals)))
		else
			s = tostring(math.floor(a + EPSILON))
		end
		if s == "0" then
			return "0"
		end
		return sign .. s
	end
	local index = 0
	while a >= 1000 - EPSILON and index < #SUFFIXES do
		a /= 1000
		index += 1
	end
	local s
	if a >= 1000 then
		s = Format.Number(a)
	elseif a >= 100 then
		s = tostring(math.floor(a + EPSILON))
	elseif a >= 10 then
		s = trimZeros(string.format("%.1f", truncate(a, 1)))
	else
		s = trimZeros(string.format("%.2f", truncate(a, 2)))
	end
	return sign .. s .. SUFFIXES[index]
end

-- Fraction to percent: 0.125 -> "12.5%", 0.5 -> "50%", 0.0025 -> "0.25%", 1.5 -> "150%".
-- opts.Decimals fixes the decimals; opts.Signed adds "+" to positive values.
function Format.Percent(fraction: any, opts: { Decimals: number?, Signed: boolean? }?): string
	local p = (tonumber(fraction) or 0) * 100
	local bad = special(p)
	if bad then
		return bad .. "%"
	end
	local decimals = opts and opts.Decimals
	if decimals == nil then
		local a = math.abs(p)
		decimals = (a == 0 or a >= 100) and 0 or (a < 1 and 2 or 1)
	end
	local s = trimZeros(string.format("%." .. math.max(0, math.floor(decimals :: number)) .. "f", p))
	if s == "-0" then
		s = "0"
	end
	if opts and opts.Signed and (tonumber(s) or 0) > 0 then
		s = "+" .. s
	end
	return s .. "%"
end

-- Multiplier: 1.25 -> "x1.25", 2 -> "x2".
function Format.Mult(value: any): string
	local n = tonumber(value) or 0
	return "x" .. trimZeros(string.format("%.2f", truncate(n, 2)))
end

-- Probability as "1 in N" (U.Odds style): 0.001 -> "1 in 1,000".
function Format.Odds(probability: any): string
	local p = tonumber(probability) or 0
	if p <= 0 then
		return "—"
	end
	return "1 in " .. Format.Number(math.floor(1 / p + 0.5))
end

local UNITS = {
	en = { "d", "h", "m", "s" },
	ru = { "д", "ч", "м", "с" },
}

-- Human duration with the two largest units: "2d 4h", "3h 05m", "12m 05s", "45s".
-- lang: "ru" for Russian unit letters (Kit.Lang()).
function Format.Duration(seconds: any, lang: string?): string
	local u = UNITS[lang == "ru" and "ru" or "en"]
	local n = math.max(0, math.floor((tonumber(seconds) or 0) + EPSILON))
	local d, h, m, s = n // 86400, (n // 3600) % 24, (n // 60) % 60, n % 60
	if d > 0 then
		return d .. u[1] .. " " .. h .. u[2]
	elseif h > 0 then
		return h .. u[2] .. " " .. string.format("%02d", m) .. u[3]
	elseif m > 0 then
		return m .. u[3] .. " " .. string.format("%02d", s) .. u[4]
	end
	return s .. u[4]
end

-- Timer: "04:05", "01:02:03" (same shape as PriceFormat.Clock), "2d 01:02:03" from a day.
function Format.Clock(seconds: any, lang: string?): string
	local n = math.max(0, math.floor((tonumber(seconds) or 0) + EPSILON))
	local d, h, m, s = n // 86400, (n // 3600) % 24, (n // 60) % 60, n % 60
	if d > 0 then
		return d .. UNITS[lang == "ru" and "ru" or "en"][1] .. " " .. string.format("%02d:%02d:%02d", h, m, s)
	elseif h > 0 then
		return string.format("%02d:%02d:%02d", h, m, s)
	end
	return string.format("%02d:%02d", m, s)
end

-- Change from current to next: delta, trend ("up" | "down" | "same") and whether it is an
-- improvement (higherIsBetter defaults to true).
function Format.Delta(current: any, nextValue: any, higherIsBetter: boolean?): (number, string, boolean)
	local a, b = tonumber(current) or 0, tonumber(nextValue) or 0
	local delta = b - a
	if math.abs(delta) < EPSILON then
		return 0, "same", false
	end
	local up = delta > 0
	local better = if higherIsBetter == false then not up else up
	return delta, up and "up" or "down", better
end

-- Resolves a StatRow/chip format name to a function.
-- "short" | "number" | "percent" | "mult" | "duration" | "clock" | function | nil (tostring).
-- lang ("ru" / "en") localizes duration units.
function Format.Resolve(format: any, lang: string?): (any) -> string
	if type(format) == "function" then
		return format
	elseif format == "short" then
		return function(v)
			return Format.Short(v, 1)
		end
	elseif format == "number" then
		return Format.Number
	elseif format == "percent" then
		return function(v)
			return Format.Percent(v)
		end
	elseif format == "mult" then
		return Format.Mult
	elseif format == "duration" then
		return function(v)
			return Format.Duration(v, lang)
		end
	elseif format == "clock" then
		return function(v)
			return Format.Clock(v, lang)
		end
	end
	return function(v)
		return tostring(v)
	end
end

return Format
