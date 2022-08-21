local class = require 'ext.class'
local table = require 'ext.table'
local file = require 'ext.file'
local io = require 'ext.io'
local os = require 'ext.os'
local string = require 'ext.string'
local find = require 'make.find'
local exec = require 'make.exec'
local template = require 'template'


local Env = class()

function Env:init()
	self.env = self
	self.home = os.getenv'HOME' or os.getenv'USERPROFILE'
end

function Env:fixpath(s) return s end

function Env:resetMacros()
	self.macros = table{
		'PLATFORM_'..self.platform:upper(),
		'BUILD_'..self.build:upper(),
	}
	if self.build == 'debug' then self.macros:insert'DEBUG' end
	if self.build == 'release' then self.macros:insert'NDEBUG' end
end

function Env:preConfig()
	self:resetMacros()

	self.pthread = false
	self.include = table{'include'} 
	self.libpaths = table()
	self.libs = table()
	self.dependLibs = table()
	self.dynamicLibs = table()
end

function Env:postConfig()
	self.macros:insert('DIST_NAME_'..self.distName:upper())
end

function Env:setupBuild(_build)
	self.build = _build
	print('building '..self.build)
	
	self.distName = nil
	self.distType = nil
	self.depends = table()
	
	self.cppver = 'c++17'

	self.self = self
	self:preConfig()
	
	self.cwd = '.'
	local loadenv = setmetatable({}, {
		__index = function(t,k)
			local v = self[k] if v ~= nil then return v end
			local v = _G[k] if v ~= nil then return v end
			return nil
		end,
		__newindex = function(t,k,v)
			self[k] = v
		end,
	})
	
	assert(loadfile('buildinfo', 'bt', loadenv))()
	assert(self.distName)
	assert(self.distType)

	for _,dependDir in ipairs(self.depends) do
		-- TODO make a function for loading depend info
		-- esp so I can derive the depend target from the buildinfo
		self.cwd = dependDir
		local push_distName = self.distName
		local push_distType = self.distType
		local push_depends = self.depends
		-- hmm, I should think this system through more ...
		-- in order to allow include buildinfos to modify state (and include things like macros, search paths, etc)
		-- I shouldn't be pushing/popping them
		-- but instead, check 'including' to see if a variable should be modified ...
		--local push_macros = macros

		self.distName = nil
		self.distType = nil
		self.depends = table()
		self.including = true
		--self:resetMacros()

		assert(loadfile(self.cwd..'/buildinfo', 'bt', loadenv))()
		local dependName = self.distName
--			assert(self.distType == 'lib' or self.distType == 'inc')	--otherwise why are we dependent on it? ... hmm, how about unit tests for applications.
		self.include:insert(self.cwd..'/include')
		if (self.platform == 'linux' and self.distType == 'lib' and push_distType == 'app')
		or (self.platform == 'osx' and self.distType == 'lib')
		or (self.platform == 'msvc' and self.distType ~= 'inc')
		or (self.platform == 'mingw' and self.distType ~= 'inc')
		or (self.platform == 'clang_win' and self.distType ~= 'inc')
		then
			self:addDependLib(dependName, self.cwd)
		end
		
		--macros = push_macros
		self.distName = push_distName
		self.distType = push_distType
		self.depends = push_depends
		self.including = nil
	end

	self:postConfig()
end

function Env:exec(cmd, must)
	return exec(cmd, must, self.platform)
end

function Env:mkdir(fn)
	if os.fileexists(fn) then
		assert(os.isdir(fn), "tried to mkdir on a file that is not a directory")
	else
		os.mkdir(fn, true)
	end
end

function Env:getSources()
	return find('src', '%.cpp$')
end

function Env:addDependLib(dependName, dependDir)
	self.dynamicLibs:insert(dependDir..'/dist/'..self.platform..'/'..self.build..'/'..self.libPrefix..dependName..self.libSuffix)
end

function Env:buildObj(obj, src)
	print('building '..obj..' from '..src)

	self:mkdir(io.getfiledir(obj) or '.')
	self:exec(
		table{
			self.compiler,
			self.compileFlags,
		}:append(self.include:map(function(path) 
			return self.compileIncludeFlag..self:fixpath(path) 
		end)):append(self.macros:map(function(macro) 
			-- how to handle macro values with quotes? 
			-- yes I ran into this on msvc
			-- how do osx/linux handle quotes and spaces in macros?
			-- what is the complete list of characters that need to be escaped?
			if macro:find' ' or macro:find'"' then
				return self.compileMacroFlag..'"'..macro:gsub('"', '\\"')..'"'
			end
			
			return self.compileMacroFlag..macro 
		end)):append{
			self.compileOutputFlag..self:fixpath(obj),
			self:fixpath(src)
		}
		:append{self.objLogFile and ('> '..self.objLogFile..' 2>&1') or nil}
		:concat' '
	)
	local log
	if self.objLogFile then
		log = file[self.objLogFile]
	end
	return true, log
end

function Env:getDistSuffix()
	return self.distType == 'lib' and self.libSuffix or self.appSuffix
end

function Env:buildDist(dist, objs)
	objs = table(objs)
	print('building '..dist..' from '..objs:concat' ')	
	local distdir = io.getfiledir(dist) or '.'
	self:mkdir(distdir)
	self:exec(
		table{self.linker, self.linkFlags}
		:append(objs:map(function(obj) return self:fixpath(obj) end))
		:append(self.libpaths:map(function(libpath) return self:fixpath(self.linkLibPathFlag..libpath) end))
		:append(self.dynamicLibs:map(function(dynlib) return self:fixpath(dynlib) end))
		:append(self.libs:map(function(lib) return self.linkLibFlag..lib end))
		:append{self.linkOutputFlag..self:fixpath(dist)}
		:append{self.distLogFile and ('> '..self.distLogFile..' 2>&1') or nil}
		:concat' ',
		true
	)
	local log
	if self.distLogFile then
		log = file[self.distLogFile]
	end
	return true, log
end

function Env:getDist()
	local distPrefix = self.distType == 'lib' and self.libPrefix or ''
	local distSuffix = self:getDistSuffix(distPrefix)
	local distdir = 'dist/'..self.platform..'/'..self.build
	local dist = distdir..'/'..distPrefix..self.distName..distSuffix
	return dist
end

function Env:getResourcePath(dist)
	return 'dist/'..self.platform..'/'..self.build
end

function Env:clean()
	self:exec'rm -fr obj'
end

function Env:distclean()
	self:exec'rm -fr dist'
end

function Env:getDependentHeaders(src,obj)
	return table()
end

-- abstract subclass for Linux, OSX, MinGW
local GCC = class(Env)
GCC.name = 'gcc'

function GCC:preConfig()
	self.objSuffix = '.o'
	self.libPrefix = 'lib'
	self.libSuffix = '.so'
	self.appSuffix = ''
	self.compiler = 'g++'
	self.compileFlags = '-c -Wall -fPIC'
	if self.build == 'debug' then
		self.compileFlags = self.compileFlags .. ' -O0 -gdwarf-2'
	elseif self.build == 'release' then
		self.compileFlags = self.compileFlags .. ' -O3'
	end
	self.compileIncludeFlag = '-I'
	self.compileMacroFlag = '-D'
	self.compileOutputFlag = '-o '	-- space ... because with msvc there shouldn't be a space
	self.compileGetIncludeFilesFlag = '-MM'	-- use -M to get system files as well
	self.linker = 'g++'
	self.linkLibPathFlag = '-L'
	self.linkLibFlag = '-l'
	self.linkFlags = ''
	self.linkOutputFlag = '-o '
	GCC.super.preConfig(self)
end

function GCC:postConfig()
	self.compileFlags = self.compileFlags .. ' -std='..self.cppver
	-- really this is Linux and MinGW specific
	if self.platform ~= 'osx' then
		if self.distType == 'lib' then
			self.linkFlags = self.linkFlags .. ' -shared'
		end
		if self.pthread then
			self.compileFlags = self.compileFlags .. ' -pthread'
			self.linkFlags = self.linkFlags .. ' -pthread'
		end
		if self.distType == 'app' then
			self.linkFlags = self.linkFlags .. ' -Wl,-rpath=lib'
		end
	end
	GCC.super.postConfig(self)
end

function GCC:getDependentHeaders(src, obj)
	-- copied from buildObject ... so maybe borrow that?
	local cmd = table{
		self.compiler,
		self.compileFlags,
	}:append(self.macros:map(function(macro) 
		
		-- matches Env:buildObj
		if macro:find' ' or macro:find'"' then
			return self.compileMacroFlag..'"'..macro:gsub('"', '\\"')..'"'
		end
		
		return self.compileMacroFlag..macro 
	end)):append(self.include:map(function(path) 
		return self.compileIncludeFlag..self:fixpath(path) 
	end))
	--:append{
	--	self.compileOutputFlag..self:fixpath(obj),
	--	self:fixpath(src)
	--}
	:concat' '
	..' '..self.compileGetIncludeFilesFlag..' '..src

	-- copied from self:exec() ... so maybe borrow that too?
	print('>> '..cmd)
	local results = io.readproc(cmd)
	results = results:gsub('\\', ' '):gsub('%s+', '\n')
	results = string.split(string.trim(results), '\n')
	local objname = select(2, io.getfiledir(obj))
	assert(results[1] == objname..':', results[1]..' should be '..objname)
	results:remove(1)
	assert(results[1] == src, results[1]..' should be '..src)
	results:remove(1)
	return results
end

local function splitPkgConfigArgs(s, prefix)
	s = string.trim(s)
	-- TODO don't just split, what if quotes or backslashes are involved?
	local t = string.split(s, '%s+')
	-- quick hack for escaping spaces in the mean time ...
	for i=#t-1,1,-1 do
		if t[i]:sub(-1) == '\\' then
			t[i] = t[i]:sub(1,-2)..' '..t:remove(i+1)
		end
	end
	if #t == 1 and #t[1] == 0 then t:remove(1) end
	-- idk what I'll do about qoute-wrapped args ...
	if prefix then 
		t = t:mapi(function(fn)
			assert(fn:sub(1,#prefix) == prefix, "hmm, pkg-config argument expected to have prefix "..prefix.." but didn't have it: "..fn)
			return fn:sub(#prefix+1)
		end)
	end
	return t
end

function GCC:addPackages(...)
	-- if I wanted I could parse things out manually and put them in their appropriate variables ...
	-- and maybe there's a benefit to that, for future commands to detect whether a path or file has been included yet ...
	-- but for now, meh:
	-- on second though, looks like these need to be added *after* all other libs, 
	-- so I don't want to just add them here or they'll go *before* ...
	-- so ... split up it is.
	for i=1,select('#', ...) do
		local name = select(i, ...)
		self.include:append(splitPkgConfigArgs(io.readproc('pkg-config --cflags-only-I '..name), '-I'))
		self.compileFlags = self.compileFlags .. ' ' .. string.trim(io.readproc('pkg-config --cflags-only-other '..name))
		
		self.libs:append(splitPkgConfigArgs(io.readproc('pkg-config --libs-only-l '..name), '-l'))
		self.libpaths:append(splitPkgConfigArgs(io.readproc('pkg-config --libs-only-L '..name), '-L'))
		self.linkFlags = self.linkFlags .. ' ' .. string.trim(io.readproc('pkg-config --libs-only-other '..name))
	end
end


local Linux = class(GCC)
Linux.name = 'linux'

function Linux:copyTree(ext, src, dst, must)
	self:exec("rsync -avm --include='"..ext.."' -f 'hide,! */' "..src.." "..dst, must)
end

function Linux:preConfig()
	self.platform = 'linux'		-- TODO make this unique per-environment class
	Linux.super.preConfig(self)
end

function Linux:buildDist(dist, objs)
	local status, log = Linux.super.buildDist(self, dist, objs)
	if not status then return status end
	if self.distType == 'app' then
		-- [[ copy all libs into distdir
		-- don't change rpath
		-- this way the app can be run from dist/linux/$build
		-- but it looks like I'm setting rpath to lib/, so ...
		local distdir = io.getfiledir(dist) or '.'
		local libdir = distdir..'/lib'		-- TODO getLibraryPath ?
		self:mkdir(libdir)
		for _,src in ipairs(self.dependLibs) do
			local _, name = io.getfiledir(src)
			local dst = libdir..'/'..name
			print('copying from '..src..' to '..dst)
			self:exec('cp '..src..' '..dst)
		end
		--]]
		-- [[ copy res/ folder into the dist folder
		if os.fileexists'res' then
			self:exec('cp -R res/* '..self:getResourcePath(dist), true)
			-- TODO
			-- self:copyTree('*', 'res', self:getResourcePath(dist), true)
		end
		--]]
	end
	return status, log
end

function Linux:addDependLib(dependName, dependDir)
	local deplibname = self.libPrefix..dependName..self.libSuffix
	local deplibdir = dependDir..'/dist/'..self.platform..'/'..self.build
	local deplib = deplibdir..'/'..deplibname
	-- [[ using -l and -L
	self.libs:insert(1, dependName)
	self.libpaths:insert(1, deplibdir)
	--]]
	--[[ adding the .so and copying to dist path
	self.dynamicLibs:insert(1, deplib)
	--]]
	self.dependLibs:insert(1, deplib)
end

--[[ if you're using -l -L then the .so path isn't baked into the .exe and you have a few options on how to get the binary to run:
-- 1) modify LD_LIBRARY_PATH every time you run it.  maybe do a 'lmake run'?  but windows and osx don't need this.
-- 2) install your .so's every time you build them
-- 3) cheap hack for now: copy them to the cwd.
function Linux:postBuildDist(env)
	for _,dep in ipairs(self.depends) do
		local srcname = dep..'/dist/linux/release/'.. -- read the target info from the buildinfo from the dep
		self:exec('cp "'..srcname..'" .')
	end
end
TODO don't use this or it will override project-based callbacks
TODO some good way to separate callbacks from class methods.  maybe I should't just use 'env' as the namespace of 'buildinfo'
--]]


local OSX = class(GCC)
OSX.name = 'osx'

-- TODO 
--local OSX = class(GCC, Linux) ?

function OSX:preConfig()
	self.platform = 'osx'
	OSX.super.preConfig(self)
	self.compiler = 'clang++'

	-- TODO verify this
	self.compileGetIncludeFilesFlag = '-H -fsyntax-only -MM'	-- I hear without -H it will search for includes *and* compile
	
	self.linker = 'clang++'
	self.libSuffix = '.dylib'
end

function OSX:postConfig()
	local dist = self:getDist()
	local _, distname = io.getfiledir(dist)
	if self.distType == 'lib' then	
		self.linkFlags = self.linkFlags .. ' -dynamiclib -undefined suppress -flat_namespace -install_name @rpath/'..distname
	end
	if self.distType == 'app' then
		self.linkFlags = self.linkFlags .. ' -Wl,-headerpad_max_install_names'
	end

	-- TODO always use home?  always use /usr/local?
	--  how to let the user specify?
	self.include:insert(self.home..'/include')
	
	if self.build == 'debug' then
		self.compileFlags = self.compileFlags .. ' -mfix-and-continue'
	end
	OSX.super.postConfig(self)
end

function OSX:getDistSuffix(distPrefix)
	return (self.distType == 'app'
		and '.app/Contents/MacOS/'..distPrefix..self.distName
		or '') .. OSX.super.getDistSuffix(self)
end

function OSX:buildDist(dist, objs)
	local status, log = OSX.super.buildDist(self, dist, objs)
	if not status then return status end
	if self.distType == 'app' then
		local distdir, distname = io.getfiledir(dist)
		distdir = distdir or '.'
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
		if os.fileexists'res' then
			self:exec('cp -R res/* '..resDir)
			-- TODO
			-- self:copyTree('*', 'res', resDir)
		end

		-- copy all libs into distdir/lib
		-- and make sure their rpath is correct
		for _,src in ipairs(self.dynamicLibs) do
			local _, name = io.getfiledir(src)
			local dst = resLibDir..'/'..name
			print('copying from '..src..' to '..dst)
			self:exec('cp '..src..' '..dst)
			self:exec('install_name_tool -change '..src..' \\@executable_path/../Resources/lib/'..name..' '..dist)
			self:exec('install_name_tool -change \\@rpath/'..name..' \\@executable_path/../Resources/lib/'..name..' '..dist)
		end
	end
	return status, log
end

function OSX:getResourcePath(dist)
	local distdir = io.getfiledir(dist) or '.'
	return distdir..'/../Resources'
end

function OSX:addDependLib(dependName, dependDir)
	-- same as linux:
	self.dynamicLibs:insert(dependDir..'/dist/'..self.platform..'/'..self.build..'/'..self.libPrefix..dependName..self.libSuffix)
	self.dependLibs:insert(self.dynamicLibs:last())
end


local Windows = class()

function Windows:fixpath(path)
	path = path:gsub('/', '\\')
	if path:find' ' then path = '"'..path..'"' end
	return path
end

function Windows:copyTree(ext, src, dst, must)
	self:exec('xcopy /Y /E "'..src..'\\'..ext..'" "'..dst..'\\"', must)
end

function Windows:copyRes(dist)
	if os.fileexists'res' then
		self:copyTree('*', 'res', self:fixpath(self:getResourcePath(dist)), true)
	end
end

function Windows:postConfig()
	self.include:insert(self.home..'\\include')
end


local MinGW = class(GCC, Windows)
MinGW.name = 'mingw'

function MinGW:preConfig()
	self.platform = 'mingw'
	MinGW.super.preConfig(self)
	self.appSuffix = '.exe'
	self.libPrefix = 'lib'
	self.libSuffix = '-static.a'
	self.compileGetIncludeFilesFlag = nil
end

function MinGW:addDependLib(dependName, dependDir)
	self.dynamicLibs:insert(dependDir..'/dist/'..self.platform..'/'..self.build..'/'..self.libPrefix..dependName..self.libSuffix)
	self.dependLibs:insert(self.dynamicLibs:last())
end

function MinGW:postConfig()
	self.include:insert(self.home..'/include')
	
	self.compileFlags = self.compileFlags .. ' -std='..self.cppver

	Env.postConfig(self)		-- adds DIST_NAME_ macro
	--GCC.postConfig(self)		-- adds link flags and such
	--self.compileFlags = self.compileFlags .. ' -std='..cppver

	if self.distType == 'app' then
		--libs:insert(1, 'mingw32')
		self.libs = table(self.dependLibs):append(self.libs)
	end
	--[=[ I never got static *or* dynamic working with g++.exe due to my leaving one method external of the dll...
	--		so I'm just using ar instead
	if self.distType == 'lib' then
		--self.linkFlags = self.linkFlags .. ' -static -Wl,--out-implib,--enable-auto-import,dist/'..self.platform..'/'..build..'/'..self.libPrefix..self.distName..'.a'
		--self.compileFlags = self.compileFlags .. [[ -Wl,--unresolved-symbols=ignore-in-object-files]]
		--self.compileFlags = self.compileFlags .. [[ -Wl,--unresolved-symbols=ignore-in-shared-libs]]
		--self.compileFlags = self.compileFlags .. [[ -Wl,--warn-unresolved-symbols]]
	end
	--]=]
	if self.pthread then
		self.compileFlags = self.compileFlags .. ' -pthread'
		self.linkFlags = self.linkFlags .. ' -pthread'
	end
	--self.linkFlags = self.linkFlags .. ' -Wl,--whole-archive'
	--self.libs:insert(1, 'mingw32')
end

function MinGW:buildDist(dist, objs)
	if self.distType == 'lib' then
		local distdir = io.getfiledir(dist) or '.'
		self:mkdir(distdir)
		
		self:exec(table{
			'ar rcs',
			dist,
		}:append(objs):concat' ')
		return
	end

	local status, log = MinGW.super.buildDist(self, dist, objs)
	
	if distType == 'app' then
		self:copyRes(dist)
	end

	return status, log
end

function MinGW:addDependLib(dependName, dependDir)
	-- [[ using -l and -L
	--libs:insert(1, dependName..'-static')
	self.libpaths:insert(dependDir..'/dist/'..self.platform..'/'..self.build)
	self.dependLibs:insert(dependName..'-static')
	--]]
	--[[ adding the .so
	self.dynamicLibs:insert(dependDir..'/dist/'..self.platform..'/'..self.build..'/'..self.libPrefix..dependName..self.libSuffix)
	self.dependLibs:insert(self.dynamicLibs:last())
	--]]
end

-- [[
function MinGW:getDependentHeaders(...)
	return Env.getDependentHeaders(self, ...)
end
--]]


local MSVC = class(Env, Windows)
MSVC.name = 'msvc'

-- enable to make static libs, disable to make dlls
-- should I make this a per-project option?
-- should I make both?
-- I'm going to only do static libs with MSVC
-- this is because of their stupid dllimport/export crap
-- which I don't want to mess all my code up for.
MSVC.useStatic = true

function MSVC:preConfig()
	self.platform = 'msvc'
	self.objSuffix = '.obj'
	self.libPrefix = ''
	self.libSuffix = '.dll'
	self.appSuffix = '.exe'
	self.compiler = 'cl.exe'
	self.compileFlags = '/nologo /c /EHsc'
	-- no /Wall, because msvc adds extra crap to Wall
	if self.build == 'debug' then
		self.compileFlags = self.compileFlags .. ' /Od /Zi'
	elseif self.build == 'release' then
		self.compileFlags = self.compileFlags .. ' /O2'
	end
	self.compileOutputFlag = '/Fo'
	self.compileIncludeFlag = '/I'
	self.compileMacroFlag = '/D'
	
	-- right now this isn't set up to even run.  only GCC compilers do dependency checking.  so TODO test this.
	self.compileGetIncludeFilesFlag = '/showIncludes'
	
	self.linker = 'link.exe'
	self.linkLibPathFlag = ''
	self.linkLibFlag = ''
	self.linkFlags = '/nologo'
	self.linkOutputFlag = '/out:'
	MSVC.super.preConfig(self)
	-- sometimes it works, sometimes it doesn't
	--self.macros:insert'_USE_MATH_DEFINES'
end

function MSVC:getSources()
	local srcs = MSVC.super.getSources(self)

--[=[
	-- /force:unresolved requires an entry point
	-- https://stackoverflow.com/questions/24547536/unresolved-external-symbol-displayed-as-an-error-while-forceunresolved-is-used 
	-- https://msdn.microsoft.com/en-gb/library/windows/desktop/ms682596%28v=vs.85%29.aspx  
	if self.distType == 'lib' then
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
	self.compileFlags = self.compileFlags .. ' /std:'..self.cppver
	if self.build == 'debug' then
		self.compileFlags = self.compileFlags .. ' /MD'	-- /MT
	elseif self.build == 'release' then
		self.compileFlags = self.compileFlags .. ' /MDd'	-- /MTd
	end
	if self.build == 'debug' then
		self.linkFlags = self.linkFlags .. ' /debug'
	end

	if self.distType == 'app' then
		self.linkFlags = self.linkFlags .. ' /subsystem:console'
	end
	Env.postConfig(self)
	Windows.postConfig(self)
end

function MSVC:addDependLib(dependName, dependDir)
	-- [[ do this if you want all libs to be staticly linked 
	if self.useStatic then
		self.dynamicLibs:insert(dependDir..'/dist/'..self.platform..'/'..self.build..'/'..dependName..'-static.lib')
	else
		self.dynamicLibs:insert(dependDir..'/dist/'..self.platform..'/'..self.build..'/'..dependName..'.lib')
	end
	--]]
end

function MSVC:buildDist(dist, objs)
	-- technically you can ... but I am avoiding these for now
	assert(#self.libpaths == 0, "can't link to libpaths with windows")
	
	local distdir = io.getfiledir(dist) or '.'
	if self.distType == 'lib' then
		self.linkFlags = self.linkFlags .. ' /dll'
	end

	local distbase = distdir..'\\'..self.distName
	local dllfile = dist 
	local pdbName = distbase..'.pdb'

	local status, log
	if self.distType == 'app' then
		self.linkFlags = self.linkFlags .. ' /pdb:'..self:fixpath(pdbName)

		self:copyRes(dist)

		status, log = MSVC.super.buildDist(self, dist, objs)
	elseif self.distType == 'lib' then
		print('building '..dist..' from '..table.concat(objs, ' '))
		local distdir = io.getfiledir(dist) or '.'
		self:mkdir(distdir)

		-- build the static lib
		if self.useStatic then
			local staticLibFile = distbase..'-static.lib'
			-- static libs don't need all the pieces until they are linked to an .exe
			-- so don't bother with libs, libpaths, dynamicLibs
			self:exec(
				table{
					'lib.exe',
					'/nologo',
					--'/incremental',	-- now gives a warning: unrecognized option
					'/nodefaultlib',
					'/out:'..self:fixpath(staticLibFile),
				}
				:append(objs)
				:append{self.distLogFile and ('> '..self.distLogFile..' 2>&1') or nil}
				:concat' ', 
				true
			)
		
		-- building DLLs.  
		-- Can't do this until I add all the API export/import macros everywhere ...
		else
			self:exec(
				table{
					'link.exe',
					'/nologo',
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
				--:append(self.libpaths:map(function(libpath) return '/libpath:'..libpath end))
				--:append(self.libs:map(function(lib) return lib end))
				:append(self.libs)
				:append(self.dynamicLibs)
				:append(objs)
				:append{self.distLogFile and ('> '..self.distLogFile..' 2>&1') or nil}
				:concat' ',
				true
			)

			-- [[ 
			local defSrcFile = distbase..'.def.txt'
			self:exec(
				table{
					'dumpbin.exe',
					'/nologo /exports',
					dllfile,
					'>',
					defSrcFile
				}
				:append{self.distLogFile and ('>> '..self.distLogFile..' 2>&1') or nil}
				:concat' ', 
				true
			)

			-- TODO use this trick: https://stackoverflow.com/questions/9946322/how-to-generate-an-import-library-lib-file-from-a-dll  
			local deffile = distbase..'.def'
			file[deffile] = table{
				'LIBRARY '..self.distName,
				'EXPORTS',
			}:concat'\n'
			--]]

			local dllLibFile = distbase..'.lib'
			self:exec(
				table{
					'lib.exe',
					'/nologo /nodefaultlib /machine:x64',
					'/def:'..deffile,
					'/out:'..dllLibFile,
				}
				--:append(objs)
				:append{self.distLogFile and ('>> '..self.distLogFile..' 2>&1') or nil}
				:concat' '
			, true)
		end

		if self.distLogFile then
			log = file[self.distLogFile]
		end
	else
		error("unknown distType "..require'ext.tolua'(self.distType))
	end

	if os.fileexists'vc140.pdb' then
		print("you made a pdb you weren't expecting for build "..distdir)
		os.remove'vc140.pdb'
	end

	return true, log
end

function MSVC:clean()
	-- false in case the dir isnt there
	self:exec('rmdir /s /q obj', false)
end

function MSVC:distclean()
	-- false in case the dir isnt there
	self:exec('rmdir /s /q dist', false)
end


--[==[ like gcc
local ClangWindows = class(GCC, Windows)
ClangWindows.name = 'clang_win'

-- don't swap /'s with \'s
--function ClangWindows:fixpath(path) return path end

function ClangWindows:preConfig()
	ClangWindows.super.preConfig(self)
	self.platform = 'clang_win'
	self.compileFlags = '-c -Wall -Xclang -flto-visibility-public-std'	-- -fPIC complains
	self.compiler = 'clang++.exe'
	self.compileGetIncludeFilesFlag = '-H -fsyntax-only -MM'	-- just like OSX ... consider a common root for clang compilers?
	self.linker = 'clang++.exe'
	self.objSuffix = '.o'
	self.appSuffix = '.exe'
	self.libPrefix = ''
	self.libSuffix = '-static.lib'
end

function ClangWindows:addDependLib(dependName, dependDir)
	self.dynamicLibs:insert(dependDir..'/dist/'..self.platform..'/'..self.build..'/'..self.libPrefix..dependName..self.libSuffix)
	self.dependLibs:insert(self.dynamicLibs:last())
end

function ClangWindows:postConfig()
	self.include:insert(self.home..'/include')
	self.compileFlags = self.compileFlags .. ' -std='..self.cppver

	if self.distType == 'lib' then
		self.linkFlags = self.linkFlags .. ' -static'
	end
	if self.distType == 'app' then
		self.libs = table(self.dependLibs):append(self.libs)
	end
	Env.postConfig(self)
end

function ClangWindows:buildDist(dist, objs)
	local distdir = io.getfiledir(dist) or '.'
	if self.distType == 'lib' then
		self.linkFlags = self.linkFlags .. ' /dll'
	end

	local distbase = distdir..'\\'..self.distName
	local dllfile = dist 
	--local pdbName = distbase..'.pdb'

	local status, log
	if self.distType == 'app' then
		--self.linkFlags = self.linkFlags .. ' /pdb:'..self:fixpath(pdbName)

		self:copyRes(dist)

		status, log = ClangWindows.super.buildDist(self, dist, objs)
	elseif self.distType == 'lib' then
		print('building '..dist..' from '..objs:concat' ')
		local distdir = io.getfiledir(dist) or '.'
		self:mkdir(distdir)

-- [=[	-- build the static lib
		local staticLibFile = distbase..'-static.lib'
		-- static libs don't need all the pieces until they are linked to an .exe
		-- so don't bother with libs, libpaths, dynamicLibs
		self:exec(
			table{
				'llvm-lib.exe',
				'/nologo',
				--'/nodefaultlib',	-- llvm-lib can't handle this
				'/out:'..self:fixpath(self.staticLibFile),
			}
			:append(objs)
			:append{self.distLogFile and ('> '..self.distLogFile..' 2>&1') or nil}
			:concat' ',
			true
		)
		status = true
		if self.distLogFile then
			log = file[self.distLogFile]
		end
--]=]
	end
	return status, log
end
--]==]


-- [==[ like msvc
local ClangWindows = class(MSVC)
ClangWindows.name = 'clang_win'

function ClangWindows:preConfig()
	ClangWindows.super.preConfig(self)
	self.platform = 'clang_win'
	self.compiler = 'clang-cl.exe'
end
--]==]


-- here's where `-e "platform='gcc'"` comes into play
local detect = platform or require 'make.detect'()
local env = (table{
	OSX,
	Linux,
	MSVC,
	MinGW,
	ClangWindows,
}:map(function(cl) return cl, cl.name end))[detect]
if detect == 'linux' then
	return Linux
elseif detect == 'msvc' then
	return MSVC
elseif detect == 'mingw' then
	return MinGW
elseif detect == 'clang_win' then
	return ClangWindows
elseif detect == 'osx' then
	return OSX
end

error("unknown environment: "..tostring(detect))
