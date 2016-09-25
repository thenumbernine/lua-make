#!/usr/bin/env lua -lluarocks.require
--[[
lua-make
execute by lua -lmake
reads buildinfo
--]]

require 'ext'

local find = require 'make.find'
local function exec(cmd, must)
	print(cmd)
	if must or must == nil then 
		assert(os.execute(cmd))
	else
		os.execute(cmd)
	end
end

local Env = class()

function Env:preConfig()
	macros = table{
		'PLATFORM_'..platform,
		'BUILD_'..build,
	}
	if build == 'debug' then macros:insert'DEBUG' end
	if build == 'release' then macros:insert'NDEBUG' end
	pthread = false
	include = table{'include'} 
	libpaths = table()
	libs = table()
	dynamicLibs = table()
end

function Env:postConfig() 
end

function Env:mkdir(fn)
	exec('mkdir -p '..fn, false)
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

function Env:buildDist(dist, objs)
	print('building '..dist..' from '..objs:concat' ')	
	self:mkdir(io.getfiledir(dist))
	exec(
		table{linker, linkFlags}
		:append(objs)
		:append(libpaths:map(function(libpath) return linkLibPathFlag..libpath end))
		:append(libs:map(function(lib) return linkLibFlag..lib end))
		:append(dynamicLibs)
		:append{linkOutputFlag, dist}
		:concat' '
	)
end

local GCC = class(Env)

function GCC:preConfig()
	objSuffix = '.o'
	libPrefix = 'lib'
	libSuffix = '.so'
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
	linkOutputFlag = '-o'
	GCC.super.preConfig(self)
end

function GCC:postConfig()
	compileFlags = compileFlags .. ' -std='..cppver
	if distType == 'lib' then
		linkFlags = linkFlags .. ' -shared'
	end
	if pthread then
		compileFlags = compileFlags .. ' -pthread'
		linkFlags = linkFlags .. ' -pthread'
	end
	GCC.super.postConfig(self)
end

local GCCLinux = class(GCC)

function GCCLinux:preConfig()
	platform = 'linux'
	GCCLinux.super.preConfig(self)
end

local MinGW = class(GCC)

function MinGW:preConfig()
	platform = 'mingw'
	MinGW.super.preConfig(self)
end

function MinGW:mkdir(fn)
	exec('C:\\MinGW\\msys\\1.0\\bin\\mkdir.exe -p '..fn, false)
end

local MSVCWindows = class(Env)

function MSVCWindows:preConfig()
	platform = 'msvc'
	objSuffix = '.obj'
	libPrefix = ''
	libSuffix = '.dll'
	compiler = 'cl.exe'
	compileFlags = '/nologo /c /Wall /EHsc'
	if build == 'debug' then
		compileFlags = compileFlags .. ' /Od /GZ /Zi'
	elseif build == 'release' then
		compileFlags = compileFlags .. ' /Og /Ot /Ox'
	end
	compileOutputFlag = '/Fo:'
	compileIncludeFlag = '/I'
	compileMacroFlag = '/D'
	linker = 'lib.exe'
	linkLibPathFlag = ''
	linkLibFlag = ''
	linkOutputFlag = ''
	MSVCWindows.super.preConfig(self)
end

function MSVCWindows:mkdir(fn)
	exec('mkdir "'..fn:gsub('/','\\')..'"', false)
end

local env
if io.readproc('uname'):trim():lower() == 'linux' then
	env = GCCLinux()
else
	--env = MinGW()
	env = MSVCWindows()
end

for _,_build in ipairs{'debug', 'release'} do
	build = _build
	print('building '..build)	
	
	distName = nil
	distType = nil
	depends = table()
	
	cppver = 'c++11'

	env:preConfig()

	assert(loadfile('buildinfo', 'bt', _G))()
	assert(distName)
	assert(distType)

	for _,dependDir in ipairs(depends) do
		local push_distName = distName
		local push_distType = distType
		local push_depends = depends
		local push_macros = macros

		distName = nil
		distType = nil
		depend = nil
		depends = table()

		macros = table{
			'PLATFORM_'..platform,
			'BUILD_'..build,
		}
		if build == 'debug' then macros:insert'DEBUG' end
		if build == 'release' then macros:insert'NDEBUG' end
	
		assert(loadfile(dependDir..'/buildinfo', 'bt', _G))()
		local dependName = distName	
		assert(distType == 'lib' or distType == 'inc')	--otherwise why are we dependent on it?
		include:insert(dependDir..'/include')
		if distType == 'lib' and push_distType == 'app' then
			dynamicLibs:insert(dependDir..'/dist/'..platform..'/'..build..'/'..libPrefix..dependName..libSuffix)
		end
		if depend then depend(dependDir) end
		
		distName = push_distName
		distType = push_distType
		depends = push_depends
		macros = push_macros
	end

	env:postConfig()
	
	-- determine source files
	local srcs = find('src', '%.cpp$')
	if #srcs == 0 then
		print'no input files found'
	else
		local objs = srcs:map(function(f)
			f = f:gsub('^src/', 'obj/')
			f = f:gsub('%.cpp$', objSuffix)
			return f
		end)
		local headers = find('include')	-- TODO find alll include

		for i,obj in ipairs(objs) do
			local src = srcs[i]
			env:buildObj(obj, src)
		end

		local distPrefix = distType == 'lib' and libPrefix or ''
		local distSuffix = distType == 'lib' and libSuffix or ''
		local distdir = 'dist/'..platform..'/'..build
		local dist = distdir..'/'..distPrefix..distName..distSuffix

		env:buildDist(dist, objs)
	end
end

-- explicitly exit so lua -lmake won't open a prompt
os.exit()
