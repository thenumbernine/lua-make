local file = require 'ext.file'
local table = require 'ext.table'

local function find(dir, pattern)
	if not file(dir):isdir() then return table() end
	return file(dir):rdir(function(path, isdir)
		return isdir or not pattern or path:match(pattern)
	end)
end

return find
