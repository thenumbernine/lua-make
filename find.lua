local path = require 'ext.path'
local table = require 'ext.table'

local function find(dir, pattern)
	if not path(dir):isdir() then return table() end
	return path(dir):rdir(function(pathstr, isdir)
		return isdir or not pattern or pathstr:match(pattern)
	end)
end

return find
