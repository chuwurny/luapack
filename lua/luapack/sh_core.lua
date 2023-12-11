luapack = luapack or {
	include = include,
	CompileFile = CompileFile,
	require = require,
	fileFind = file.Find,
	fileExists = file.Exists,
	fileIsDir = file.IsDir
}

if luapack.LogFile ~= nil then
	luapack.LogFile:Close()
	luapack.LogFile = nil
end

luapack.LogFile = file.Open("luapack.txt", "w", "DATA")

luapack.LOG_LEVEL_NONE = 0
luapack.LOG_LEVEL_ONLY_LOG = 1
luapack.LOG_LEVEL_ALL = 2

luapack.LogLevel = CreateConVar(
	"luapack_loglevel",
	"0",
	FCVAR_ARCHIVE,
	"0 - disable all logs. 1 - only log messages. 2 - all messages."
)

function luapack.LogMsg(...)
	local content = string.format(...)

	if luapack.LogLevel:GetInt() >= luapack.LOG_LEVEL_ONLY_LOG then
		Msg(content)
	end

	luapack.LogFile:Write(content)
	luapack.LogFile:Flush()
end

function luapack.DebugMsg(...)
	local content = string.format(...)

	if luapack.LogLevel:GetInt() >= luapack.LOG_LEVEL_ALL then
		Msg(content)
	end

	luapack.LogFile:Write(content)
	luapack.LogFile:Flush()
end

function luapack.CanonicalizePath(path)
	path = string.lower(path)
	path = string.gsub(path, "\\", "/")
	path = string.gsub(path, "/+", "/")

	local t = {}
	for str in string.gmatch(path, "([^/]+)") do
		if str == ".." then
			table.remove(t)
		elseif str ~= "." and str ~= "" then
			table.insert(t, str)
		end
	end

	path = table.concat(t, "/")

	local match = string.match(path, "^lua/(.+)$")
	if match ~= nil then
		return match
	end

	match = string.match(path, "^addons/[^/]+/lua/(.+)$")
	if match ~= nil then
		return match
	end

	if SERVER then
		match = string.match(path, "^gamemodes/([^/]+/entities/.+)$")
		if match ~= nil then
			return match
		end
	else
		match = string.match(path, "^gamemodes/[^/]+/entities/(.+)$")
		if match ~= nil then
			return match
		end
	end

	match = string.match(path, "^gamemodes/([^/]+/gamemode/.+)$")
	if match ~= nil then
		return match
	end

	return path
end
