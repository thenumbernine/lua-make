local path = require 'ext.path'
local table = require 'ext.table'

local function find(dir, pattern)
	dir = path(dir)
	if not dir:isdir() then return table() end
	local fs = table()
	for f in dir:rdir(function(pathstr, isdir)
		return isdir or not pattern or pathstr:match(pattern)
	end) do
		fs:insert(f.path)
	end
	return fs
end

return find
