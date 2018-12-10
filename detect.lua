local function detect()
	local h = io.popen'uname'
	local uname = (h:read'*l' or ''):lower()
	if uname == 'linux' then
		return 'linux'
	elseif uname:sub(1,5) == 'mingw'
	or uname:sub(1,4) == 'msys' 
	or uname == ''
	then
		if io.popen'clang-cl.exe --version':read'*a' then
			-- CLang
			return 'clang_win'
		elseif io.popen'gcc.exe --version':read'*a' then
			-- GCC
			return 'mingw'
		elseif io.popen'cl.exe':read'*l' then
			-- MSVC
			return 'msvc'
		end
	elseif uname == 'darwin' then
		return 'osx'
	end
end

return detect
