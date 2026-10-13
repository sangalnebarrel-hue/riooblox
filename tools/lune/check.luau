-- Compile-checks every script under a src directory (syntax + Luau parse errors).
--   lune run tools/lune/check.luau src
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local root = process.args[1] or "src"
local count, bad = 0, 0
local function walk(dir)
	for _, name in fs.readDir(dir) do
		local full = dir .. "/" .. name
		if fs.isDir(full) then
			walk(full)
		elseif name:sub(-4) == ".lua" then
			count += 1
			local ok, err = pcall(luau.compile, fs.readFile(full))
			if not ok then
				bad += 1
				print("ERROR " .. full .. "\n  " .. tostring(err))
			end
		end
	end
end
walk(root)
print(string.format("%d scripts, %d errors", count, bad))
if bad > 0 then
	process.exit(1)
end
