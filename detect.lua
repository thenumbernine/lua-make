local function detect()
	local h = io.popen'uname'
	local uname = (h:read'a' or ''):split'\n'[1]:lower()
	if uname == 'linux' then
		-- TODO clang_linux vs gcc_linux ?
		return 'linux'
	elseif uname == 'darwin' then
		-- TODO clang_osx vs gcc_osx?
		return 'osx'
	else
		if io.popen'clang-cl.exe --version':read'a' then
			-- CLang
			return 'clang_win'
		elseif io.popen'gcc.exe --version':read'a' then
			-- GCC
			return 'mingw'	-- TODO rename to gcc_win? distinguish between mingw_gcc, cygwin_gcc, djgpp_gcc, etc?
		elseif io.popen'cl.exe':read'a' then
			-- MSVC
			return 'msvc'
		end
	end
end

return detect
