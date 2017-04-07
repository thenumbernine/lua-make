--shortcut for -lmake
if os.getenv'HOME' then
	dofile(os.getenv'HOME'..'/Projects/lua/make/run.lua')
elseif os.getenv'USERPROFILE' then
	dofile(os.getenv'USERPROFILE'..[[\Projects\lua\make\run.lua]])
else
	error "couldn't deduce platform"
end
os.exit()
