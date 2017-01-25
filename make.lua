--shortcut for -lmake
if os.getenv'HOME' then
	dofile(os.getenv'HOME'..'/Projects/lua/make/run.lua')
	os.exit()
end
if os.getenv'USERPROFILE' then
	dofile(os.getenv'USERPROFILE'..[[\Projects\lua\make\run.lua]])
	os.exit()
end
