local os = require 'ext.os'	-- make sure os.execute has the right return value api
local function exec(cmd, must, platform)
	print('>> '..cmd)
	if must or must == nil then
		local result, why, errno = os.execute(cmd)
		if not result then
			if not (({
				-- windows platforms are giving me trouble with os.execute on luajit ...
				msvc=1,
				mingw=1,
				clang_win=1,
			})[platform] and why == 'unknown') then
				assert(result, tostring(why)..': '..tostring(errno))
			end
		end
		return result, why, errno
	else
		return os.execute(cmd)
	end
end
return exec
