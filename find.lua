local file = require 'ext.file'
local table = require 'ext.table'
local os = require 'ext.os'

local function find(dir, pattern)
	if not os.isdir(dir) then return table() end
	return os.rlistdir(dir, function(path, isdir)
		return isdir or not pattern or path:match(pattern)
	end)
end

return find
