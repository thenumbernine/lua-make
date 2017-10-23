--shortcut for -lmake
if os.getenv'HOME' then
	os.execute('lua '..os.getenv'HOME'..'/Projects/lua/make/run.lua clean distclean')
elseif os.getenv'USERPROFILE' then
	os.execute('lua '..os.getenv'USERPROFILE'..[[\Projects\lua\make\run.lua clean distclean]])
else
	error "couldn't deduce platform"
end
os.exit()
