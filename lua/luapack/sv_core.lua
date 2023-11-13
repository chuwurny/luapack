AddCSLuaFile("sh_core.lua")
AddCSLuaFile("cl_core.lua")
AddCSLuaFile("cl_file.lua")
AddCSLuaFile("cl_directory.lua")
AddCSLuaFile("cl_overrides.lua")
AddCSLuaFile("cl_entities.lua")

if not file.IsDir("luapack", "DATA") then
	file.CreateDir("luapack")
end

include("sh_core.lua")

luapack.Bypass = luapack.Bypass or false
luapack.FileList = luapack.FileList or {}
luapack.FinishedAdding = luapack.FinishedAdding or false

-- for the hook module, no need to include util.lua and all the trash it brings
function IsValid(object)
	return object and object.IsValid and object:IsValid()
end

luapack.require("hook")

luapack.require("luapack_internal")

function luapack.AddCSLuaFile(path)
	luapack.Bypass = true
	AddCSLuaFile(path)
	luapack.Bypass = false
end

luapack.AddCSLuaFile("includes/_init.lua")

function luapack.IsBlacklistedFile(filepath)
	return	filepath == "derma/init.lua" or
			filepath == "skins/default.lua" or
			string.match(filepath, "^([^/]+)/gamemode/cl_init.lua$")
end

function luapack.AddFile(filepath, add_blacklisted_files)
	if luapack.FinishedAdding then
		luapack.DebugMsg("luapack.AddFile called after InitPostEntity was called '%s'\n", filepath)
		return false
	end

	local canon_filepath = luapack.CanonicalizePath(filepath)
	if not file.Exists(canon_filepath, "LUA") then
		luapack.DebugMsg("File doesn't exist (unable to add it to file list) '%s'.\n", canon_filepath)
		return false
	end

	if luapack.IsBlacklistedFile(canon_filepath) then
		luapack.DebugMsg("Adding file through normal AddCSLuaFile '%s'.\n", canon_filepath)

		if add_blacklisted_files then
			luapack.AddCSLuaFile(filepath)
		end

		return false
	end

	for i = 1, #luapack.FileList do
		if luapack.FileList[i] == canon_filepath then
			return true
		end
	end

	table.insert(luapack.FileList, canon_filepath)

	return true
end

hook.Add("AddOrUpdateCSLuaFile", "luapack addcsluafile detour", function(path, reload)
	if not reload and not luapack.Bypass and luapack.AddFile(path) then
		return false
	end
end)

local function ReadFile(filepath)
	local f = file.Open(filepath, "rb", "LUA")
	if f then
		local data = f:Read(f:Size()) or ""
		f:Close()
		return data
	else
		error("ReadFile failed '" .. filepath .. "'")
	end
end

local send = ReadFile("_send.txt")
for line in string.gmatch(send, "([^\r\n]+)\r?\n") do
	if string.sub(line, 1, 1) ~= "#" then
		luapack.AddFile(line, true)
	end
end

local gamemode_priority = nil
local function GetPriority(path1, path2)
	if gamemode_priority == nil then
		gamemode_priority = {}

		local gm = GAMEMODE
		while gm do
			table.insert(gamemode_priority, gm.FolderName)
			gm = gm.BaseClass
		end
	end

	local gm1, rpath1, gm1p = string.match(path1, "^([^/]+)/entities/(.+)$")
	if gm1 == nil then
		return 0
	end

	local gm2, rpath2, gm2p = string.match(path2, "^([^/]+)/entities/(.+)$")
	if gm2 == nil then
		return 0
	end

	if rpath1 ~= rpath2 then
		return 0
	end

	for i = 1, #gamemode_priority do
		if gm1p == nil and gamemode_priority[i] == gm1 then
			gm1p = i
		end

		if gm2p == nil and gamemode_priority[i] == gm2 then
			gm2p = i
		end

		if gm1p ~= nil and gm2p ~= nil then
			break
		end
	end

	if gm1p == nil or gm2p == nil then
		error("OY VEY, WE GOT A BAD GAMEMODE? " .. gm1 .. " - " .. gm2)
	end

	if gm1p > gm2p then
		return 1
	elseif gm1p < gm2p then
		return -1
	end

	error("gamemode 1 priority is the same as gamemode 2 priority? OY VEY! " .. gm1 .. " - " .. gm2 .. " - " .. rpath1 .. " - " .. rpath2)
end

local function CleanFileList(list)
	local listsize = #list
	local i = 1
	while i <= listsize do
		local k = i + 1
		while k <= listsize do
			if list[i] == list[k] then
				print(i, k, list[i], list[k])
			end

			local pri = GetPriority(list[i], list[k])
			if pri == 1 then
				listsize = listsize - 1
				table.remove(list, i)
				i = i - 1
				break
			elseif pri == -1 then
				listsize = listsize - 1
				table.remove(list, k)
			else
				k = k + 1
			end
		end

		i = i + 1
	end
end

local function CleanPath(path)
	--[[local gm, rpath = string.match(path, "^([^/]+)/gamemode/(.+)$")
	if gm ~= nil and rpath ~= nil then
		return rpath
	end]]

	local rpath = string.match(path, "^[^/]+/entities/(.+)$")
	if rpath ~= nil then
		return rpath
	end

	return path
end

local band, brshift, tochar = bit.band, bit.rshift, string.char
local function WriteULong(f, n)
	f:Write(tochar(
		brshift(n, 24),
		band(brshift(n, 16), 0xFF),
		band(brshift(n, 8), 0xFF),
		band(n, 0xFF)
	))
end

hook.Add("InitPostEntity", "luapack resource creation", function()
	hook.Remove("InitPostEntity", "luapack resource creation")

	luapack.LogMsg("Building pack...\n")

	local time = SysTime()

	local luapacktemp = "luapack/temp.dat"

	local f = file.Open(luapacktemp, "wb", "DATA")
	if f == nil then
		error("failed to open '" .. luapacktemp .. "' for writing")
	end

	local hashes = {}

	CleanFileList(luapack.FileList)

	for i = 1, #luapack.FileList do
		local filepath = luapack.FileList[i]
		local data = ReadFile(filepath)
		local datalen = #data
		local crc = tonumber(util.CRC(data))
		filepath = CleanPath(filepath)

		hashes[#hashes + 1] = util.SHA256(data)

		if datalen > 0 then
			data = util.Compress(data)
			datalen = #data
		end

		WriteULong(f, datalen)
		WriteULong(f, crc)
		f:Write(filepath .. "\0")

		if datalen > 0 then
			f:Write(data)
		end
	end

	f:Close()

	table.sort(hashes)
	luapack.CurrentHash = util.SHA256(table.concat(hashes))

	local currentpath = "luapack/" .. luapack.CurrentHash .. ".dat"
	if not file.Exists(currentpath, "DATA") then
		if not luapack.Rename(luapacktemp, currentpath) then
			luapack.DebugMsg("Pack file renaming not successful\n")
		end
	else
		luapack.DebugMsg("Deleting obsolete temporary file\n")
		file.Delete(luapacktemp)
	end

	resource.AddFile("data/" .. currentpath)

	util.AddNetworkString("luapackhash_" .. luapack.CurrentHash)

	luapack.FinishedAdding = true

	luapack.LogMsg("Pack building took %f seconds!\n", SysTime() - time)
end)

luapack.include("includes/_init.lua")
