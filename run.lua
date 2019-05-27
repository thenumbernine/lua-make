#!/usr/bin/env lua
--[[
lua make.lua [cmd]
reads buildinfo
cmd is: build debug release clean distclean

globals defined per-project:
distName = name of the project
distType = type of the project.  
	possible options are:
		'app' for applications / executables
		'lib' for libraries
		'inc' for include files (no code / nothing to build, but still used for buildinfo dependencies)
depends = list of paths to projects that this is dependent upon

globals defined by lua-make:
home = home directory.
platform = build platform.
build = 'debug' or 'release'.
objSuffix = suffix of object file.  '.o' on unix systems, '.obj' in M$ systems.
libPrefix = prefix of library files.  'lib' on unix systems.
libSuffix = lib suffix. '.so', '.dylib', '.a', '.lib', '.dll', etc.
appSuffix = executable suffix.  empty on unix systems, '.exe' for M$.
compiler = compiler binary name.  g++, clang++, cl.exe, etc...
compileFlags = flags to pass to compiler.
compileIncludeFlag = flag for include directory.
compileMacroFlag = flag for C++ macros.
compileOutputFlag = flag for output filename.
compileGetIncludeFilesFlag = flag for getting include files referenced by this file
linker = linker binary name.
linkLibPathFlag = flag for adding library search paths.
linkLibFlag = flag for adding libraries.
linkOutputFlag = flag for specifying the output filename.
linkFlags = extra flags to send to the linker
pthread = flag for including pthread.
cppver = C++ version.
include = table of include directories to forward to the C++ compiler.
dependLibs = other luamake projects that the project is dependent upon (for executing recursive buildinfos).
libs = -l libraries, be they static or dynamic, automatically detected by the compiler/linker.
libpaths = -L search paths for 'libs'.
dynamicLibs
	on linux this contains paths to explicit .so files
	on osx this is .dylib files
	on windows this is .lib files associated with .dll files (as opposed to the .lib files that are static libraries ... smh windows)
--]]

require 'ext'

home = os.getenv'HOME' or os.getenv'USERPROFILE'
local find = require 'make.find'

-- not 'local' so the buildinfo script can see it (esp for postBuildDist() )
function exec(cmd, must)
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
				assert(result, why, errno)
			end
		end
	else
		os.execute(cmd)
	end
end

local function resetMacros()
	macros = table{
		'PLATFORM_'..platform,
		'BUILD_'..build,
	}
	if build == 'debug' then macros:insert'DEBUG' end
	if build == 'release' then macros:insert'NDEBUG' end
end

local Env = class()

function Env:fixpath(s) return s end

function Env:preConfig()
	resetMacros()

	pthread = false
	include = table{'include'} 
	libpaths = table()
	libs = table()
	dependLibs = table()
	dynamicLibs = table()
end

function Env:mkdirCmd(fn)
	exec('mkdir -p '..fn, false)
end

function Env:mkdir(fn)
	if io.fileexists(fn) then
		assert(io.isdir(fn), "tried to mkdir on a file that is not a directory")
	else
		self:mkdirCmd(fn)
	end
end

function Env:getSources()
	return find('src', '%.cpp$')
end

function Env:addDependLib(dependName, dependDir)
	dynamicLibs:insert(dependDir..'/dist/'..platform..'/'..build..'/'..libPrefix..dependName..libSuffix)
end

function Env:buildObj(obj, src)
	print('building '..obj..' from '..src)
	
-- TODO make Env:postConfig and put this in it 
macros:insert('distName_'..distName)
	
	self:mkdir(io.getfiledir(obj))
	exec(
		table{
			compiler,
			compileFlags,
		}:append(
			include:map(function(path) return compileIncludeFlag..self:fixpath(path) end)
		):append(
			macros:map(function(macro) return compileMacroFlag..macro end)
		):append{
			compileOutputFlag..self:fixpath(obj),
			self:fixpath(src)
		}:concat' '
	)
end

function Env:getDistSuffix()
	return distType == 'lib' and libSuffix or appSuffix
end

function Env:buildDist(dist, objs)	
	print('building '..dist..' from '..objs:concat' ')	
	local distdir = io.getfiledir(dist)
	self:mkdir(distdir)
	exec(
		table{linker, linkFlags}
		:append(objs:map(function(obj) return self:fixpath(obj) end))
		:append(libpaths:map(function(libpath) return self:fixpath(linkLibPathFlag..libpath) end))
		:append(libs:map(function(lib) return linkLibFlag..lib end))
		:append(dynamicLibs:map(function(dynlib) return self:fixpath(dynlib) end))
		:append{linkOutputFlag..self:fixpath(dist)}
		:concat' ', true)
end

function Env:getDist()
	local distPrefix = distType == 'lib' and libPrefix or ''
	local distSuffix = self:getDistSuffix(distPrefix)
	local distdir = 'dist/'..platform..'/'..build
	local dist = distdir..'/'..distPrefix..distName..distSuffix
	return dist
end

function Env:getResourcePath(dist)
	return 'dist/'..platform..'/'..build
end

function Env:clean()
	exec'rm -fr obj'
end

function Env:distclean()
	exec'rm -fr dist'
end

function Env:getDependentHeaders(src)
	return {}
end


local GCC = class(Env)

function GCC:preConfig()
	objSuffix = '.o'
	libPrefix = 'lib'
	libSuffix = '.so'
	appSuffix = ''
	compiler = 'g++'
	compileFlags = '-c -Wall -fPIC'
	if build == 'debug' then
		compileFlags = compileFlags .. ' -O0 -gdwarf-2'
	elseif build == 'release' then
		compileFlags = compileFlags .. ' -O3'
	end
	compileIncludeFlag = '-I'
	compileMacroFlag = '-D'
	compileOutputFlag = '-o '	-- space ... because with msvc there shouldn't be a space
	compileGetIncludeFilesFlag = '-MM'	-- use -M to get system files as well
	linker = 'g++'
	linkLibPathFlag = '-L'
	linkLibFlag = '-l'
	linkFlags = ''
	linkOutputFlag = '-o '
	GCC.super.preConfig(self)
end

function GCC:postConfig()
	compileFlags = compileFlags .. ' -std='..cppver
	-- really this is Linux and MinGW specific
	if platform ~= 'osx' then
		if distType == 'lib' then
			linkFlags = linkFlags .. ' -shared'
		end
		if pthread then
			compileFlags = compileFlags .. ' -pthread'
			linkFlags = linkFlags .. ' -pthread'
		end
		if distType == 'app' then
			linkFlags = linkFlags .. ' -Wl,-rpath=lib'
		end
	end
end

function GCC:getDependentHeaders(src, obj)
	-- copied from buildObject ... so maybe borrow that?
	local cmd = table{
		compiler,
		compileFlags,
	}:append(
		macros:map(function(macro) return compileMacroFlag..macro end)
	):append(
		include:map(function(path) return compileIncludeFlag..self:fixpath(path) end)
	)
	--:append{
	--	compileOutputFlag..self:fixpath(obj),
	--	self:fixpath(src)
	--}
	:concat' '
	..' '..compileGetIncludeFilesFlag..' '..src

	-- copied from exec() ... so maybe borrow that too?
	print('>> '..cmd)
	local results = io.readproc(cmd)
	results = results:gsub('\\', ' '):gsub('%s+', '\n')
	results = results:trim():split'\n'
	local objname = select(2, io.getfiledir(obj))
	assert(results[1] == objname..':', results[1]..' should be '..objname)
	results:remove(1)
	assert(results[1] == src, results[1]..' should be '..src)
	results:remove(1)
	return results
end


local Linux = class(GCC)

function Linux:copyTree(ext, src, dst, must)
	exec("rsync -avm --include='"..ext.."' -f 'hide,! */' "..src.." "..dst, must)
end

function Linux:preConfig()
	platform = 'linux'		-- TODO make this unique per-environment class
	Linux.super.preConfig(self)
end

function Linux:buildDist(dist, objs)
	Linux.super.buildDist(self, dist, objs)

	if distType == 'app' then
		--[[
		-- TODO copy all libs into distdir/lib
		-- and make sure their rpath is correct
		-- or go the windows route and just static link everything
		local distdir = io.getfiledir(dist)
		self:mkdir(distdir..'/lib')
		for _,src in ipairs(dependLibs) do
			local _, name = io.getfiledir(src)
			local dst = 'dist/'..platform..'/'..build..'/lib/'..name
			print('copying from '..src..' to '..dst)
			exec('cp '..src..' '..dst)
		end
		--]]
		-- [[ copy res/ folder into the dist folder
		if io.fileexists'res' then
			exec('cp -R res/* '..self:getResourcePath(dist), true)
			-- TODO
			-- self:copyTree('*', 'res', self:getResourcePath(dist), true)
		end
		--]]
	end
end

function Linux:addDependLib(dependName, dependDir)
	--[[ using -l and -L
	libs:insert(dependName)
	libpaths:insert(dependDir..'/dist/'..platform..'/'..build)
	--]]
	-- [[ adding the .so
	dynamicLibs:insert(1, dependDir..'/dist/'..platform..'/'..build..'/'..libPrefix..dependName..libSuffix)
	--]]
	dependLibs:insert(1, dynamicLibs:last())
end


local OSX = class(GCC)
-- TODO 
--local OSX = class(GCC, Linux) ?

function OSX:preConfig()
	platform = 'osx'
	OSX.super.preConfig(self)
	compiler = 'clang++'

	-- TODO verify this
	compileGetIncludeFilesFlag = '-H -fsyntax-only -MM'	-- I hear without -H it will search for includes *and* compile
	
	linker = 'clang++'
	libSuffix = '.dylib'
end

function OSX:postConfig()

	local dist = self:getDist()
	local _, distname = io.getfiledir(dist)
	if distType == 'lib' then	
		linkFlags = linkFlags .. ' -dynamiclib -undefined suppress -flat_namespace -install_name @rpath/'..distname
	end
	if distType == 'app' then
		linkFlags = linkFlags .. ' -Wl,-headerpad_max_install_names'
	end

	-- TODO always use home?  always use /usr/local?
	--  how to let the user specify?
	include:insert(home..'/include')
	
	if build == 'debug' then
		compileFlags = compileFlags .. ' -mfix-and-continue'
	end
	OSX.super.postConfig(self)
end

function OSX:getDistSuffix(distPrefix)
	return (distType == 'app'
		and '.app/Contents/MacOS/'..distPrefix..distName
		or '') .. OSX.super.getDistSuffix(self)
end

local template = require 'template'
function OSX:buildDist(dist, objs)
	OSX.super.buildDist(self, dist, objs)
	if distType == 'app' then
		local distdir, distname = io.getfiledir(dist)
		file[distdir..'/../PkgInfo'] = 'APPLhect'
		file[distdir..'/../Info.plist'] = template([[
<?='<'..'?'?>xml version="1.0" encoding="UTF-8"<?='?'..'>'?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string><?=distname?></string>
	<key>CFBundleIdentifier</key>
	<string>net.christopheremoore.<?=distname?></string>
	<key>CFBundleVersion</key>
	<string>1.0</string>
	<key>CFBundleIconFile</key>
	<string>Icons</string>

	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleDocumentTypes</key>
	<array/>
	<key>CFBundleExecutable</key>
	<string><?=distname?></string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>1.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleSignature</key>
	<string>hect</string>
	<key>NSMainNibFile</key>
	<string>MainMenu</string>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>

</dict>
</plist>
]], {distname=distname})

		local resDir = distdir..'/../Resources'
		local resLibDir = resDir..'/lib'
		self:mkdir(resLibDir)
	
		-- copy over Resources
		if io.fileexists'res' then
			exec('cp -R res/* '..resDir)
			-- TODO
			-- self:copyTree('*', 'res', resDir)
		end

		-- copy all libs into distdir/lib
		-- and make sure their rpath is correct
		for _,src in ipairs(dynamicLibs) do
			local _, name = io.getfiledir(src)
			local dst = resLibDir..'/'..name
			print('copying from '..src..' to '..dst)
			exec('cp '..src..' '..dst)
			exec('install_name_tool -change '..src..' \\@executable_path/../Resources/lib/'..name..' '..dist)
			exec('install_name_tool -change \\@rpath/'..name..' \\@executable_path/../Resources/lib/'..name..' '..dist)
		end
	end
end

function OSX:getResourcePath(dist)
	local distdir = io.getfiledir(dist)
	return distdir..'/../Resources'
end

function OSX:addDependLib(dependName, dependDir)
	-- same as linux:
	dynamicLibs:insert(dependDir..'/dist/'..platform..'/'..build..'/'..libPrefix..dependName..libSuffix)
	dependLibs:insert(dynamicLibs:last())
end


local Windows = class()

function Windows:fixpath(path)
	path = path:gsub('/', '\\')
	if path:find' ' then path = '"'..path..'"' end
	return path
end

function Windows:copyTree(ext, src, dst, must)
	exec('xcopy /Y /E "'..src..'\\'..ext..'" "'..dst..'\\"', must)
end

function Windows:copyRes(dist)
	if io.fileexists'res' then
		self:copyTree('*', 'res', self:fixpath(self:getResourcePath(dist)), true)
	end
end

function Windows:postConfig()
	include:insert(home..'\\include')
end


local MinGW = class(GCC, Windows)

function MinGW:preConfig()
	platform = 'mingw'
	MinGW.super.preConfig(self)
	appSuffix = '.exe'
	libPrefix = 'lib'
	libSuffix = '-static.a'
	compileGetIncludeFilesFlag = nil
end

function MinGW:addDependLib(dependName, dependDir)
	dynamicLibs:insert(dependDir..'/dist/'..platform..'/'..build..'/'..libPrefix..dependName..libSuffix)
	dependLibs:insert(dynamicLibs:last())
end

function MinGW:postConfig()
	include:insert(home..'/include')
	
	compileFlags = compileFlags .. ' -std='..cppver
	
	--GCC.postConfig(self)		-- adds link flags and such
	--compileFlags = compileFlags .. ' -std='..cppver

	if distType == 'app' then
		--libs:insert(1, 'mingw32')
		libs = table(dependLibs):append(libs)
	end
	--[=[ I never got static *or* dynamic working with g++.exe due to my leaving one method external of the dll...
	--		so I'm just using ar instead
	if distType == 'lib' then
		--linkFlags = linkFlags .. ' -static -Wl,--out-implib,--enable-auto-import,dist/'..platform..'/'..build..'/'..libPrefix..distName..'.a'
		--compileFlags = compileFlags .. [[ -Wl,--unresolved-symbols=ignore-in-object-files]]
		--compileFlags = compileFlags .. [[ -Wl,--unresolved-symbols=ignore-in-shared-libs]]
		--compileFlags = compileFlags .. [[ -Wl,--warn-unresolved-symbols]]
	end
	--]=]
	if pthread then
		compileFlags = compileFlags .. ' -pthread'
		linkFlags = linkFlags .. ' -pthread'
	end
	--linkFlags = linkFlags .. ' -Wl,--whole-archive'
	--libs:insert(1, 'mingw32')
end

function MinGW:buildDist(dist, objs)
	if distType == 'lib' then
		local distdir = io.getfiledir(dist)
		self:mkdir(distdir)
		
		exec(table{
			'ar rcs',
			dist,
		}:append(objs):concat' ')
		return
	end

	MinGW.super.buildDist(self, dist, objs)
	
	if distType == 'app' then
		self:copyRes(dist)
	end
end

function MinGW:addDependLib(dependName, dependDir)
	-- [[ using -l and -L
	--libs:insert(1, dependName..'-static')
	libpaths:insert(dependDir..'/dist/'..platform..'/'..build)
	dependLibs:insert(dependName..'-static')
	--]]
	--[[ adding the .so
	dynamicLibs:insert(dependDir..'/dist/'..platform..'/'..build..'/'..libPrefix..dependName..libSuffix)
	dependLibs:insert(dynamicLibs:last())
	--]]
end

function MinGW:mkdirCmd(fn)
	exec([[mkdir ]]..self:fixpath(fn), false)
end

-- [[
function MinGW:getDependentHeaders(...)
	return Env.getDependentHeaders(self, ...)
end
--]]


local MSVC = class(Env, Windows)

-- enable to make static libs, disable to make dlls
-- should I make this a per-project option?
-- should I make both?
-- I'm going to only do static libs with MSVC
-- this is because of their stupid dllimport/export crap
-- which I don't want to mess all my code up for.
MSVC.useStatic = true

function MSVC:preConfig()
	platform = 'msvc'
	objSuffix = '.obj'
	libPrefix = ''
	libSuffix = '.dll'
	appSuffix = '.exe'
	compiler = 'cl.exe'
	compileFlags = '/nologo /c /EHsc'
	-- no /Wall, because msvc adds extra crap to Wall
	if build == 'debug' then
		compileFlags = compileFlags .. ' /Od /Zi'
	elseif build == 'release' then
		compileFlags = compileFlags .. ' /O2'
	end
	compileOutputFlag = '/Fo'
	compileIncludeFlag = '/I'
	compileMacroFlag = '/D'
	
	-- right now this isn't set up to even run.  only GCC compilers do dependency checking.  so TODO test this.
	compileGetIncludeFilesFlag = '/showIncludes'
	
	linker = 'link.exe'
	linkLibPathFlag = ''
	linkLibFlag = ''
	linkFlags = '/nologo'
	linkOutputFlag = '/out:'
	MSVC.super.preConfig(self)
	-- sometimes it works, sometimes it doesn't
	--macros:insert'_USE_MATH_DEFINES'
end

function MSVC:getSources()
	local srcs = MSVC.super.getSources(self)

--[=[
	-- /force:unresolved requires an entry point
	-- https://stackoverflow.com/questions/24547536/unresolved-external-symbol-displayed-as-an-error-while-forceunresolved-is-used 
	-- https://msdn.microsoft.com/en-gb/library/windows/desktop/ms682596%28v=vs.85%29.aspx  
	if distType == 'lib' then
		-- hmm, now I need a cleanup ...
		local tmp = (os.tmpname()..'.cpp'):gsub('\\','/')
		-- hmm, do i need a .cpp extension?
		print('attempting to write to '..tmp)
		
--file[tmp] =
local f = assert(io.open(tmp, 'w'))
f:write
		[[
#include <windows.h>
BOOL WINAPI DllMain(
    HINSTANCE hinstDLL,
    DWORD fdwReason,
    LPVOID lpReserved
) {
    return TRUE;
}
]]
f:close()

		srcs:insert(tmp)
	end
--]=]

	return srcs
end

function MSVC:postConfig()
	compileFlags = compileFlags .. ' /std:'..cppver
	if build == 'debug' then
		compileFlags = compileFlags .. ' /MD'	-- /MT
	elseif build == 'release' then
		compileFlags = compileFlags .. ' /MDd'	-- /MTd
	end
	if build == 'debug' then
		linkFlags = linkFlags .. ' /debug'
	end

	if distType == 'app' then
		linkFlags = linkFlags .. ' /subsystem:console'
	end

	Windows.postConfig(self)
end

function MSVC:addDependLib(dependName, dependDir)
	-- [[ do this if you want all libs to be staticly linked 
	if self.useStatic then
		dynamicLibs:insert(dependDir..'/dist/'..platform..'/'..build..'/'..dependName..'-static.lib')
	else
		dynamicLibs:insert(dependDir..'/dist/'..platform..'/'..build..'/'..dependName..'.lib')
	end
	--]]
end

function MSVC:mkdirCmd(fn)
	exec('mkdir "'..self:fixpath(fn)..'"', false)
end

function MSVC:buildDist(dist, objs)
	-- technically you can ... but I am avoiding these for now
	assert(#libpaths == 0, "can't link to libpaths with windows")
	
	local distdir = io.getfiledir(dist)
	if distType == 'lib' then
		linkFlags = linkFlags .. ' /dll'
	end

	local distbase = distdir..'\\'..distName
	local dllfile = dist 
	local pdbName = distbase..'.pdb'

	if distType == 'app' then
		linkFlags = linkFlags .. ' /pdb:'..self:fixpath(pdbName)

		self:copyRes(dist)

		MSVC.super.buildDist(self, dist, objs)
	elseif distType == 'lib' then
		print('building '..dist..' from '..objs:concat' ')
		local distdir = io.getfiledir(dist)
		self:mkdir(distdir)

		-- build the static lib
		if self.useStatic then
			local staticLibFile = distbase..'-static.lib'
			-- static libs don't need all the pieces until they are linked to an .exe
			-- so don't bother with libs, libpaths, dynamicLibs
			exec(table{
				'lib.exe',
				'/nologo',
				--'/incremental',	-- now gives a warning: unrecognized option
				'/nodefaultlib',
				'/out:'..self:fixpath(staticLibFile),
			}:append(objs):concat' ', true)
		
		-- building DLLs.  
		-- Can't do this until I add all the API export/import macros everywhere ...
		else
	
			exec(table{
				'link.exe',
				'/dll',
	
--[=[
here's a dilemma...
I don't want to put declspecs everywhere in the code just for windows
so what are my other options?
create a .lib to link against ... but this means having the lib point to a specific dll,
and that means always giving the dll the same name
so my solution: /force:unresolved
but this only works if we have a 'DllMain' function defined ...
--]=]
--'/force:unresolved',
'/incremental',
				
				'/out:'..dllfile,
				--'/pdb:'..self:fixpath(pdbName),
			}
			--:append(libpaths:map(function(libpath) return '/libpath:'..libpath end))
			--:append(libs:map(function(lib) return lib end))
			:append(libs)
			:append(dynamicLibs)
			:append(objs)
			:concat' ', true)

			-- [[ 
			local defSrcFile = distbase..'.def.txt'
			exec(table{
				'dumpbin.exe',
				'/nologo /exports',
				dllfile,
				'>',
				defSrcFile
			}:concat' ', true)

			-- TODO use this trick: https://stackoverflow.com/questions/9946322/how-to-generate-an-import-library-lib-file-from-a-dll  
			local deffile = distbase..'.def'
			file[deffile] = table{
				'LIBRARY '..distName,
				'EXPORTS',
			}:concat'\n'
			--]]

			local dllLibFile = distbase..'.lib'
			exec(table{
					'lib.exe',
					'/nologo /nodefaultlib /machine:x64',
					'/def:'..deffile,
					'/out:'..dllLibFile,
				}
				--:append(objs)
				:concat' '
			, true)
		end
	end

	if io.fileexists'vc140.pdb' then
		print("you made a pdb you weren't expecting for build "..distdir)
		os.remove'vc140.pdb'
	end
end

function MSVC:clean()
	-- false in case the dir isnt there
	exec('rmdir /s /q obj', false)
end

function MSVC:distclean()
	-- false in case the dir isnt there
	exec('rmdir /s /q dist', false)
end


--[==[ like gcc
local ClangWindows = class(GCC, Windows)

-- don't swap /'s with \'s
--function ClangWindows:fixpath(path) return path end

function ClangWindows:mkdirCmd(fn)
	exec('mkdir "'..self:fixpath(fn)..'"', false)
end

function ClangWindows:preConfig()
	ClangWindows.super.preConfig(self)
	platform = 'clang_win'
	compileFlags = '-c -Wall -Xclang -flto-visibility-public-std'	-- -fPIC complains
	compiler = 'clang++.exe'
	compileGetIncludeFilesFlag = '-H -fsyntax-only -MM'	-- just like OSX ... consider a common root for clang compilers?
	linker = 'clang++.exe'
	objSuffix = '.o'
	appSuffix = '.exe'
	libPrefix = ''
	libSuffix = '-static.lib'
end

function ClangWindows:addDependLib(dependName, dependDir)
	dynamicLibs:insert(dependDir..'/dist/'..platform..'/'..build..'/'..libPrefix..dependName..libSuffix)
	dependLibs:insert(dynamicLibs:last())
end

function ClangWindows:postConfig()
	include:insert(home..'/include')
	compileFlags = compileFlags .. ' -std='..cppver

	if distType == 'lib' then
		linkFlags = linkFlags .. ' -static'
	end
	if distType == 'app' then
		libs = table(dependLibs):append(libs)
	end
end

function ClangWindows:buildDist(dist, objs)
	local distdir = io.getfiledir(dist)
	if distType == 'lib' then
		linkFlags = linkFlags .. ' /dll'
	end

	local distbase = distdir..'\\'..distName
	local dllfile = dist 
	--local pdbName = distbase..'.pdb'

	if distType == 'app' then
		--linkFlags = linkFlags .. ' /pdb:'..self:fixpath(pdbName)

		self:copyRes(dist)

		ClangWindows.super.buildDist(self, dist, objs)
	elseif distType == 'lib' then
		print('building '..dist..' from '..objs:concat' ')
		local distdir = io.getfiledir(dist)
		self:mkdir(distdir)

-- [=[	-- build the static lib
		local staticLibFile = distbase..'-static.lib'
		-- static libs don't need all the pieces until they are linked to an .exe
		-- so don't bother with libs, libpaths, dynamicLibs
		exec(table{
			'llvm-lib.exe',
			'/nologo',
			--'/nodefaultlib',	-- llvm-lib can't handle this
			'/out:'..self:fixpath(staticLibFile),
		}:append(objs):concat' ', true)
--]=]
	end
end
--]==]


-- [==[ like msvc
local ClangWindows = class(MSVC)

function ClangWindows:preConfig()
	ClangWindows.super.preConfig(self)
	platform = 'clang_win'
	compiler = 'clang-cl.exe'
end
--]==]


--local env -- make it a global
local detect = platform or require 'make.detect'()
if detect == 'linux' then
	env = Linux()
elseif detect == 'msvc' then
	env = MSVC()
elseif detect == 'mingw' then
	env = MinGW()
elseif detect == 'clang_win' then
	env = ClangWindows()
elseif detect == 'osx' then
	env = OSX()
else
	error("unknown environment: "..detect)
end
print("using environment: "..detect)

local lfs
do
	local found
	found, lfs = pcall(require, 'lfs')
	if not found then 
		print("can't find lfs -- can't determine last file modification time -- rebuilding all")
		lfs = nil 
	end
end

local function needsUpdate(target, depends)
	if not lfs then return true end
	if not io.fileexists(target) then return true end
	
	local targetAttr = lfs.attributes(target)
	if not targetAttr then return true end

	local dependModification
	for _,depend in ipairs(depends) do
		local dependAttr = assert(lfs.attributes(depend))
		if not dependModification then
			dependModification = dependAttr.modification
		else
			if dependAttr.modification > dependModification then
				dependModification = dependAttr.modification
			end
		end
	end
	if not dependModification then
		print('failed to find any dependency modification timestamp -- rebuilding')
		return true
	end
	
	-- if the newest dependency modification time is newer than the target time then rebuild
	if dependModification > targetAttr.modification then
		return true
	end

	local date = os.date:bind'%Y-%m-%d %H:%M:%S'
	print('target up-to-date: '..target
		..' ('..date(targetAttr.modification)
		..' vs '..date(dependModification)
		..')')
	return false
end

local function doBuild(args)
	args = args or {}
	for _,_build in ipairs(args.buildTypes or {'debug', 'release'}) do
		build = _build
		print('building '..build)	
		
		distName = nil
		distType = nil
		depends = table()
		
		cppver = 'c++17'

		env:preConfig()
		
		cwd = '.'
		assert(loadfile('buildinfo', 'bt', _G))()
		assert(distName)
		assert(distType)

		for _,dependDir in ipairs(depends) do
			cwd = dependDir
			local push_distName = distName
			local push_distType = distType
			local push_depends = depends
			-- hmm, I should think this system through more ...
			-- in order to allow include buildinfos to modify state (and include things like macros, search paths, etc)
			-- I shouldn't be pushing/popping them
			-- but instead, check 'including' to see if a variable should be modified ...
			--local push_macros = macros

			distName = nil
			distType = nil
			depends = table()
			including = true
			--resetMacros()

			assert(loadfile(cwd..'/buildinfo', 'bt', _G))()
			local dependName = distName	
			assert(distType == 'lib' or distType == 'inc')	--otherwise why are we dependent on it?
			include:insert(cwd..'/include')
			if (platform == 'linux' and distType == 'lib' and push_distType == 'app')
			or (platform == 'osx' and distType == 'lib')
			or (platform == 'msvc' and distType ~= 'inc')
			or (platform == 'mingw' and distType ~= 'inc')
			or (platform == 'clang_win' and distType ~= 'inc')
			then
				env:addDependLib(dependName, cwd)
			end
			
			--macros = push_macros
			distName = push_distName
			distType = push_distType
			depends = push_depends
			including = nil
		end

		env:postConfig()
		
		-- determine source files
		local srcs = env:getSources()
		if #srcs == 0 then
			print'no input files found'
		else
			local objs = srcs:map(function(f)
				f = f:gsub('^src/', 'obj/'..platform..'/'..build..'/')
				f = f:gsub('%.cpp$', objSuffix)
				return f
			end)
			local headers = find('include')	-- TODO find alll include

			if not args.distonly then
				for i,obj in ipairs(objs) do
					local src = srcs[i]

					-- see if we can search for the include the files that this source file depends on
					local dependentHeaders = env:getDependentHeaders(src, obj)
					
					-- if the source file has been modified since the obj was created
					-- *or* the dependent headers have been modified since the obj was created
					-- *or* the buildinfo has been modified since the obj was created
					-- then rebuild
					-- (otherwise you can skip this build)
					if needsUpdate(obj, table.append({src}, dependentHeaders)) then
						env:buildObj(obj, src)
					end
				end
			end

			local dist = env:getDist()
--[[
print('distSuffix', distSuffix)
print('distdir', distdir)
print('dist', dist)
os.exit()
--]]			
			
			if needsUpdate(dist, objs) then
				env:buildDist(dist, objs)
			end

			-- if postBuildDist is defined then do that too
			if postBuildDist then
				postBuildDist(env:getResourcePath(dist))
			end
		end
	end
end

local cmds = {...}
if #cmds == 0 then cmds = {'all'} end
for _,cmd in ipairs(cmds) do
	if cmd == 'all' then
		doBuild()
	elseif cmd == 'debug' or cmd == 'release' then
		doBuild{buildTypes={cmd}}
	elseif cmd == 'clean' then
		env:clean()
	elseif cmd == 'distclean' then	
		env:distclean()
	elseif cmd == 'distonly' then
		doBuild{distonly=true}
	else
		error('unknown command: '..cmd)
	end
end
