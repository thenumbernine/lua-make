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

for _,build in ipairs{'debug', 'release'} do

	distName = nil
	distType = nil
	depends = table()

	platform = 'linux'
	macros = table{
		'PLATFORM_'..platform,
		'BUILD_'..build,
	}
	if build == 'debug' then macros:insert'DEBUG' end
	if build == 'release' then macros:insert'NDEBUG' end
	
	objSuffix = '.o'
	libPrefix = 'lib'
	libSuffix = '.so'
	
	compiler = 'g++'
	cppver = 'c++11'
	compileFlags = '-c -Wall -fPIC'

	if build == 'debug' then
		compileFlags = compileFlags .. ' -O0 -gdwarf-2'
	elseif build == 'release' then
		compileFlags = compileFlags .. ' -O3'
	end
	compileOutputFlag = '-o'
	
	pthread = false
	
	include = table{'include'} 

	assert(loadfile('buildinfo', 'bt', _G))()
	assert(distName)
	assert(distType)

	compileFlags = compileFlags .. ' -std='..cppver

	linker = 'g++'
	linkFlags = distType == 'lib' and '-shared' or ''
	linkOutputFlag = '-o'

	if pthread and platform == 'linux' then
		compileFlags = compileFlags .. ' -pthread'
		linkFlags = linkFlags .. ' -pthread'
	end

	libpaths = table()
	libs = table()
	dynamicLibs = table()

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
	
	-- determine source files
	local srcs = find('src', '%.cpp$')
	local objs = srcs:map(function(f)
		f = f:gsub('^src/', 'obj/')
		f = f:gsub('%.cpp$', objSuffix)
		return f
	end)
	local headers = find('include')	-- TODO find alll include

--[[
for _,dep in ipairs(env.depends) do
	local depenv = loadConfig(dep)
	depenv.include(depenv, env)
end
	--]]

	for i,obj in ipairs(objs) do
		local src = srcs[i]
		exec('mkdir -p '..io.getfiledir(obj), false)
		exec(
			table{
				compiler,
				compileFlags,
			}:append(
				include:map(function(path) return '-I'..path end)
			):append(
				macros:map(function(macro) return '-D'..macro end)
			):append{
				compileOutputFlag, 
				obj,
				src
			}:concat' '
		)
	end

	local distPrefix = distType == 'lib' and libPrefix or ''
	local distSuffix = distType == 'lib' and libSuffix or ''
	local distdir = 'dist/'..platform..'/'..build
	local dist = distdir..'/'..distPrefix..distName..distSuffix

	exec('mkdir -p '..io.getfiledir(dist), false)
	exec(
		table{linker, linkFlags}
		:append(objs)
		:append(libpaths:map(function(libpath) return '-L'..libpath end))
		:append(libs:map(function(lib) return '-l'..lib end))
		:append(dynamicLibs)
		:append{linkOutputFlag, dist}
		:concat' '
	)
end

-- explicitly exit so lua -lmake won't open a prompt
os.exit()
