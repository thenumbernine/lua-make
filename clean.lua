--shortcut for -lmake
local table = require 'ext.table'
local luabin = arg[table(arg):keys():sort():inf()]
if os.getenv'HOME' then
	os.execute(luabin..' '..os.getenv'HOME'..'/Projects/lua/make/run.lua clean distclean')
elseif os.getenv'USERPROFILE' then
	os.execute(luabin..' '..os.getenv'USERPROFILE'..[[\Projects\lua\make\run.lua clean distclean]])
else
	error "couldn't deduce platform"
end
os.exit()
