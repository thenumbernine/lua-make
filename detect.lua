local function detect()
	local uname = io.popen'uname':read'*l':lower()
	if uname == 'linux' then
		return 'gcc-linux'
	elseif uname == 'msys_nt-10.0' then
		if io.popen'cl.exe':read'*l' then
			return 'msvc-windows'
		elseif io.popen'gcc.exe --version':read'*l' then
			-- gcc.exe (GCC) 5.3.0
			return 'mingw-windows'
		end
	elseif uname == 'darwin' then
		return 'osx'
	end
end

return detect
