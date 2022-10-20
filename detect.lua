local string = require 'ext.string'
local function detect()
	local h = io.popen'uname'
	local uname = string.split(h:read'a' or '', '\n')[1]:lower()
	if uname == 'linux' then
		-- TODO clang_linux vs gcc_linux ?
		return 'linux'
	elseif uname == 'darwin' then
		-- TODO clang_osx vs gcc_osx?
		return 'osx'
	else
		-- cl.exe has no version flag (I think), but outputs the version as default.
		-- However it does so to stderr, which will get piped to nul.
		-- However however it at least prints out its warning to stdout: "usage: cl ..."  hmm... seems it has mixed up the use of stdout and stderr...
		if #io.popen'cl.exe 2> nul':read'a' > 0 then
			-- MSVC
			return 'msvc'
		-- Windows always returns a string, it's just an empty string for .exe's that don't exist.
		-- is this the same behavior on linux/osx?
		-- Also, windows always prints an error message when the process doesn't exist .. to stderr.
		-- Piping stderr to nul eliminates this.
		-- But it will also eliminate the output of a legitimate process.
		elseif #io.popen'clang-cl.exe --version 2> nul':read'a' > 0 then
			-- CLang
			return 'clang_win'
		elseif #io.popen'gcc.exe --version 2> nul':read'a' > 0 then
			-- GCC
			return 'mingw'	-- TODO rename to gcc_win? distinguish between mingw_gcc, cygwin_gcc, djgpp_gcc, etc?
		end
	end
end

return detect
