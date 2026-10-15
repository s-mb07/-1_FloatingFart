--!strict
--[[
	Convention linter -- run via Lune (`lune run scripts/lint-conventions`).
	Enforces the mechanically-checkable rules from README.md §9:
	  - every .lua file starts with --!strict
	  - at most MAX_PCALL pcall(/xpcall( per file, unless it declares --!derogation: pcall <reason>
	Vendored third-party code (VENDORED_PATHS below, mirrors selene.toml's Packages/**
	exclusion) is skipped entirely -- these files predate this kit and aren't ours to retype.
	Exits non-zero on any violation.
	(Typing, doc comments and English-only are enforced by luau-lsp + selene + code review.)
]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local ROOT = "src"
local MAX_PCALL = 3

-- Vendored, not authored by this project -- see each file's own header.
local VENDORED_PATHS = {
	["src/ReplicatedStorage/Libraries/Signal.lua"] = true,
}

local violations: { string } = {}

local function isVendored(path: string): boolean
	if VENDORED_PATHS[path] then
		return true
	end
	return string.find(path, "/Packages/") ~= nil
end

local function walk(dir: string): ()
	for _, name in fs.readDir(dir) do
		local path = `{dir}/{name}`
		if fs.isDir(path) then
			walk(path)
		elseif string.match(path, "%.lua$") and not isVendored(path) then
			local source = fs.readFile(path)

			-- --!strict must appear near the top.
			if not string.find(string.sub(source, 1, 200), "%-%-!strict") then
				table.insert(violations, `{path}: missing --!strict header`)
			end

			-- pcall budget.
			local count = 0
			for _ in string.gmatch(source, "x?pcall%s*%(") do
				count += 1
			end
			local exempt = string.find(source, "%-%-!derogation:%s*pcall") ~= nil
			if count > MAX_PCALL and not exempt then
				table.insert(
					violations,
					`{path}: {count} pcall (max {MAX_PCALL}) -- add --!derogation: pcall <reason> or refactor`
				)
			end
		end
	end
end

walk(ROOT)

if #violations > 0 then
	print(`Convention check FAILED ({#violations}):`)
	for _, message in violations do
		print("  - " .. message)
	end
	process.exit(1)
end

print("Convention check passed.")
