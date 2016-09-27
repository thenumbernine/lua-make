local table = require 'ext.table'
local io = require 'ext.io'

local function rfind(dir, pattern, results)
	for f in file[dir]() do
		local path = dir..'/'..f
		if io.isdir(path) then
			rfind(path, pattern, results)
		else
			if not pattern or path:match(pattern) then
				results:insert(path)
			end
		end
	end
end

local function find(dir, pattern)
	local results = table()
	if io.isdir(dir) then
		rfind(dir, pattern, results)
	end
	return results
end

return find
