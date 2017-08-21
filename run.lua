#!/usr/bin/env lua
--[[
lua make.lua [cmd]
reads buildinfo
cmd is: build debug release clean distclean
--]]

require 'ext'

local find = require 'make.find'

-- not 'local' so the buildinfo script can see it (esp for postBuildDist() )
function exec(cmd, must)
	print('>> '..cmd)
	if must or must == nil then 
		assert(os.execute(cmd))
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

function Env:preConfig()
	resetMacros()

	pthread = false
	include = table{'include'} 
	libpaths = table()
	libs = table()
	dependLibs = table()
	dynamicLibs = table()
end

function Env:postConfig() 
end

function Env:mkdir(fn)
	exec('mkdir -p '..fn, false)
end

function Env:addDependLib(dependName, dependDir)
	dynamicLibs:insert(dependDir..'/dist/'..platform..'/'..build..'/'..libPrefix..dependName..libSuffix)
end

function Env:buildObj(obj, src)
	print('building '..obj..' from '..src)
	self:mkdir(io.getfiledir(obj))
	exec(
		table{
			compiler,
			compileFlags,
		}:append(
			include:map(function(path) return compileIncludeFlag..path end)
		):append(
			macros:map(function(macro) return compileMacroFlag..macro end)
		):append{
			compileOutputFlag, 
			obj,
			src
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
		:append(objs)
		:append(libpaths:map(function(libpath) return linkLibPathFlag..libpath end))
		:append(libs:map(function(lib) return linkLibFlag..lib end))
		:append(dynamicLibs)
		:append{linkOutputFlag..dist}
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
	compileOutputFlag = '-o'
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
	GCC.super.postConfig(self)
end

local Linux = class(GCC)

function Linux:preConfig()
	platform = 'linux'
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
	dynamicLibs:insert(dependDir..'/dist/'..platform..'/'..build..'/'..libPrefix..dependName..libSuffix)
	--]]
	dependLibs:insert(dynamicLibs:last())
end

local OSX = class(GCC)

function OSX:preConfig()
	platform = 'osx'
	OSX.super.preConfig(self)
	compiler = 'clang++'
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
	include:insert(os.getenv'HOME'..'/include')
	
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

local MinGW = class(GCC)

function MinGW:preConfig()
	platform = 'mingw'
	MinGW.super.preConfig(self)
end

function MinGW:mkdir(fn)
	exec('C:\\MinGW\\msys\\1.0\\bin\\mkdir.exe -p '..fn, false)
end

local MSVC = class(Env)

-- enable to make static libs, disable to make dlls
-- should I make this a per-project option?
-- should I make both?
-- I'm going to only do static libs with MSVC
-- this is because of their stupid dllimport/export crap
-- which I don't want to mess all my code up for.
MSVC.makeStatic = true

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
		compileFlags = compileFlags .. ' /Ot /Ox'
	end
	compileOutputFlag = '/Fo:'
	compileIncludeFlag = '/I'
	compileMacroFlag = '/D'
	linker = 'link.exe'
	linkLibPathFlag = ''
	linkLibFlag = ''
	linkFlags = '/nologo'
	linkOutputFlag = '/out:'
	MSVC.super.preConfig(self)
	-- sometimes it works, sometimes it doesn't
	--macros:insert'_USE_MATH_DEFINES'
end

function MSVC:postConfig()
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
	
	MSVC.super.postConfig(self)
end

function MSVC:addDependLib(dependName, dependDir)
	-- [[ do this if you want all libs to be staticly linked 
	if self.makeStatic then
		dynamicLibs:insert(dependDir..'/dist/'..platform..'/'..build..'/'..dependName..'-static.lib')
	else
		dynamicLibs:insert(dependDir..'/dist/'..platform..'/'..build..'/'..dependName..'.lib')
	end
	--]]
end

function MSVC:mkdir(fn)
	exec('mkdir "'..fn:gsub('/','\\')..'"', false)
end

function MSVC:buildDist(dist, objs)
	-- technically you can ... but I am avoiding these for now
	assert(#libpaths == 0, "can't link to libpaths with windows")
	
	local distdir = io.getfiledir(dist)
	if distType == 'lib' then
		linkFlags = linkFlags .. ' /dll'
	end

	local distbase = distdir..'/'..distName
	local dllfile = dist 

	if distType == 'app' then
		MSVC.super.buildDist(self, dist, objs)
	elseif distType == 'lib' then
		print('building '..dist..' from '..objs:concat' ')
		local distdir = io.getfiledir(dist)
		self:mkdir(distdir)

		if self.makeStatic then	-- [=[	-- build the static lib
			local staticLibFile = distbase..'-static.lib'
			-- static libs don't need all the pieces until they are linked to an .exe
			-- so don't bother with libs, libpaths, dynamicLibs
			exec(table{
				'lib.exe',
				'/nologo /nodefaultlib',
				'/out:'..staticLibFile,
			}:append(objs):concat' ', true)
		else --]=]
		-- [=[ building DLLs:
			exec(table{
				'link.exe',
				'/dll',
				'/out:'..dllfile,
			}
			--:append(libpaths:map(function(libpath) return '/libpath:'..libpath end))
			--:append(libs:map(function(lib) return lib end))
			:append(libs)
--			:append(dynamicLibs)
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
--			:append(objs)
			:concat' '
			, true)
		end --]=]
	end

	if io.fileexists'vc140.pdb' then
		exec('del vc140.pdb', false)
	end
end


local env
local detect = require 'make.detect'()
if detect == 'gcc-linux' then
	env = Linux()
elseif detect == 'msvc-windows' then
	env = MSVC()
elseif detect == 'mingw-windows' then
	env = MinGW()
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
	
	for _,depend in ipairs(depends) do
		local dependAttr = assert(lfs.attributes(depend))
		if targetAttr.change < dependAttr.change then
			return true
		end
	end
	
	print('target up-to-date: '..target)
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
		
		cppver = 'c++11'

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
		local srcs = find('src', '%.cpp$')
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
					
					-- if the source file has been modified since the obj was created
					-- *or* the dependent headers have been modified since the obj was created
					-- *or* the buildinfo has been modified since the obj was created
					-- then rebuild
					-- (otherwise you can skip this build)
					if needsUpdate(obj, {src}) then
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
			env:buildDist(dist, objs)
	
			-- if postBuildDist is defined then do that too
			if postBuildDist then
				postBuildDist(env:getResourcePath(dist))
			end
		end
	end
end

local function clean()
	exec('rm -fr obj')
end

local function distclean()
	exec('rm -fr dist')
end

local cmds = {...}
if #cmds == 0 then cmds = {'all'} end
for _,cmd in ipairs(cmds) do
	if cmd == 'all' then
		doBuild()
	elseif cmd == 'debug' or cmd == 'release' then
		doBuild{buildTypes={cmd}}
	elseif cmd == 'clean' then
		clean()
	elseif cmd == 'distclean' then	
		distclean()
	elseif cmd == 'distonly' then
		doBuild{distonly=true}
	else
		error('unknown command: '..cmd)
	end
end
