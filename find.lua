local lfs = require 'lfs'
local table = require 'ext.table'

local function rfind(dir, pattern, results)
	for f in lfs.dir(dir) do
		if f ~= '.' and f ~= '..' then
			local path = dir..'/'..f
			local attr = lfs.attributes(path)
			if attr.mode == 'file' then
				if not pattern or path:match(pattern) then
					results:insert(path)
				end
			elseif attr.mode == 'directory' then
				rfind(path, pattern, results)
			end
		end
	end
end

local function find(dir, pattern)
	local results = table()
	local attr = lfs.attributes(dir)
	if attr and attr.mode == 'directory' then
		rfind(dir, pattern, results)
	end
	return results
end

return find
