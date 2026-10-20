--!nolint
-- Export the Russian strings of HALLOWEEN PART II as a Roblox cloud localization table CSV (the format of the uploaded
-- DOGROTS_RU_HALLOWEEN.csv: Key, Example, Source, Context, Game Locations, ru, ru translator type, en-us, ...).
-- The game itself never reads this table (every string is already in a ReplicatedStorage.Localization module or an
-- inline EN/RU pair); the CSV is for translators and for teams that keep the cloud table in sync.
--   * every rows of the base CSV (kept as they are, in their order)
--   * every Exact / UI / Templates / Words / Window entry of the Localization modules added or changed by Part II
--     (Russian plural templates {one, few, many} export their "many" form, Context = template)
--   * inline pairs T("en", "ru") / L("en", "ru") / Kit.T(...) / Shared.L(...) found in the scripts Part II added or changed
-- A source already in the base CSV is not repeated. Rows are sorted by source within each part.
-- usage: lune run tools/export_ru_csv.luau <base.csv> <out.csv> <file list of changed .luau paths>
local fs = require("@lune/fs")
local process = require("@lune/process")
local L = require("../tests/lib/economy_env")

local basePath, outPath, listPath = process.args[1], process.args[2], process.args[3]
assert(basePath and outPath and listPath, "usage: lune run tools/export_ru_csv.luau <base.csv> <out.csv> <changed-files.txt>")

local HEADER = "Key,Example,Source,Context,Game Locations,ru,ru translator type,en-us,en-us translator type,en-gb,en-gb translator type"

local function csvField(s: string): string
	if string.find(s, '[,"\r\n]') then
		return '"' .. string.gsub(s, '"', '""') .. '"'
	end
	return s
end

-- the base CSV's own lines are copied verbatim; their sources are parsed only to skip duplicates
local function parseCsv(text: string): { { string } }
	local rows, row, field, i, n, quoted = {}, {}, {}, 1, #text, false
	while i <= n do
		local c = string.sub(text, i, i)
		if quoted then
			if c == '"' then
				if string.sub(text, i + 1, i + 1) == '"' then
					table.insert(field, '"')
					i += 1
				else
					quoted = false
				end
			else
				table.insert(field, c)
			end
		elseif c == '"' then
			quoted = true
		elseif c == "," then
			table.insert(row, table.concat(field))
			field = {}
		elseif c == "\n" or c == "\r" then
			if c == "\r" and string.sub(text, i + 1, i + 1) == "\n" then
				i += 1
			end
			table.insert(row, table.concat(field))
			field = {}
			table.insert(rows, row)
			row = {}
		else
			table.insert(field, c)
		end
		i += 1
	end
	if #field > 0 or #row > 0 then
		table.insert(row, table.concat(field))
		table.insert(rows, row)
	end
	return rows
end

local baseText = fs.readFile(basePath)
baseText = string.gsub(baseText, "^\239\187\191", "") -- UTF-8 BOM
local baseRows = parseCsv(baseText)
local seen = {}
for i = 2, #baseRows do
	local src = baseRows[i][3]
	if src and src ~= "" then
		seen[src] = true
	end
end

local added: { { src: string, ru: string, ctx: string, from: string } } = {}
local function add(src: any, ru: any, ctx: string, from: string)
	if type(src) ~= "string" or type(ru) ~= "string" or src == "" or ru == "" or src == ru then
		return
	end
	if seen[src] or not string.find(src, "%a") then
		return
	end
	seen[src] = true
	table.insert(added, { src = src, ru = ru, ctx = ctx, from = from })
end

local changed = {}
for line in string.gmatch(fs.readFile(listPath), "[^\r\n]+") do
	table.insert(changed, line)
end

-- 1. Localization modules
local moduleCount = 0
for _, path in ipairs(changed) do
	local name = string.match(path, "^src/ReplicatedStorage/Localization/([%w_]+)%.luau$")
	if name then
		local ok, mod = pcall(L.Require, "ReplicatedStorage.Localization." .. name)
		if ok and type(mod) == "table" then
			moduleCount += 1
			for _, section in ipairs({ "Exact", "UI", "Words", "Window" }) do
				local t = mod[section]
				if type(t) == "table" then
					local keys = {}
					for k in pairs(t) do
						table.insert(keys, k)
					end
					table.sort(keys)
					for _, k in ipairs(keys) do
						add(k, t[k], "", name)
					end
				end
			end
			if type(mod.Templates) == "table" then
				local keys = {}
				for k in pairs(mod.Templates) do
					table.insert(keys, k)
				end
				table.sort(keys)
				for _, k in ipairs(keys) do
					local v = mod.Templates[k]
					add(k, type(v) == "table" and (v[3] or v[#v]) or v, "template", name)
				end
			end
		else
			print("skip Localization." .. name .. ": " .. tostring(mod))
		end
	end
end

-- 2. inline EN/RU pairs in changed scripts: <fn>("english", "русский") with plain double-quoted literals
local inline = 0
local function unescape(s: string): string
	return (string.gsub(s, "\\(.)", { n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\" }))
end
for _, path in ipairs(changed) do
	if string.match(path, "%.luau$") and not string.match(path, "^src/ReplicatedStorage/Localization/") and string.match(path, "^src/") then
		local ok, text = pcall(fs.readFile, path)
		if ok then
			for en, ru in string.gmatch(text, '[%w_%.]*[TL]%(%s*"([^"\n]-)"%s*,%s*"([^"\n]-)"') do
				if string.find(ru, "[\208\209]") then -- Cyrillic lead bytes: the second literal really is Russian
					local before = #added
					add(unescape(en), unescape(ru), string.find(en, "%%[ds]") and "template" or "",
						string.match(path, "([%w_]+)%.[%w%.]*luau$") or path)
					inline += #added - before
				end
			end
		end
	end
end

local out = { HEADER }
for i = 2, #baseRows do
	local r = baseRows[i]
	if #r > 1 then
		local cells = {}
		for j = 1, 11 do
			cells[j] = csvField(r[j] or "")
		end
		table.insert(out, table.concat(cells, ","))
	end
end
table.sort(added, function(a, b)
	if a.from ~= b.from then
		return a.from < b.from
	end
	return a.src < b.src
end)
for _, row in ipairs(added) do
	table.insert(out, table.concat({ "", "", csvField(row.src), row.ctx, csvField("PART II · " .. row.from), csvField(row.ru), "User", "", "", "", "" }, ","))
end
fs.writeFile(outPath, "\239\187\191" .. table.concat(out, "\n") .. "\n")
print(string.format("base rows %d, new rows %d (%d from %d Localization modules, %d inline pairs) -> %s", #baseRows - 1, #added,
	#added - inline, moduleCount, inline, outPath))
