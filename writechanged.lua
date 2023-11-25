local path = require 'ext.path'
local exec = require 'make.exec'

-- only write if the contents have changed, as to not update the write date
local function writeChanged(filename, data, diff)
	local srcpath = path(filename)
	local srcdata = srcpath:read()
	if srcdata ~= data then
		if diff then 
			-- if you want to diff what's been changed ...
			local tmppath = path(os.tmpname())
			tmppath:write(data)
			exec('diff '..srcpath:escape()..' '..tmppath:escape(), false)
			tmppath:remove()
		end
		assert(srcpath:write(data))
	end
end

return writeChanged
