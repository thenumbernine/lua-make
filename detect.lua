local function detect()
	local uname = io.popen'uname':read'*l':lower()
	if uname == 'linux' then
		return 'linux'
	elseif uname:sub(1,5) == 'mingw'
	or uname:sub(1,4) == 'msys' 
	then
		if io.popen'cl.exe':read'*l' then
			-- MSVC
			return 'msvc'
		elseif io.popen'gcc.exe --version':read'*l' then
			-- GCC
			return 'mingw'
		elseif io.popen'clang.exe':read'*l' then
			-- CLang
			return 'clang_win'
		end
	elseif uname == 'darwin' then
		return 'osx'
	end
end

return detect
