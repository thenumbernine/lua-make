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

local io = require 'ext.io'
local table = require 'ext.table'
local find = require 'make.find'

-- this either looks at global 'platform' or runs make.detect 
local MakeEnv = require 'make.env'
local env = MakeEnv()
print("using environment: "..env.name)


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

	local date = function(...) return os.date('%Y-%m-%d %H:%M:%S', ...) end
	print('target up-to-date: '..target
		..' ('..date(targetAttr.modification)
		..' vs '..date(dependModification)
		..')')
	return false
end

local function doBuild(args)
	args = args or {}
	for _,_build in ipairs(args.buildTypes or {'debug', 'release'}) do
		env.build = _build
		print('building '..env.build)
		
		env.distName = nil
		env.distType = nil
		env.depends = table()
		
		env.cppver = 'c++17'

		env.env = env
		env:preConfig()
		
		env.cwd = '.'
		local loadenv = setmetatable({}, {
			__index = function(t,k)
				local v = env[k] if v ~= nil then return v end
				local v = _G[k] if v ~= nil then return v end
				return nil
			end,
			__newindex = function(t,k,v)
				env[k] = v
			end,
		})
		
		assert(loadfile('buildinfo', 'bt', loadenv))()
		assert(env.distName)
		assert(env.distType)

		for _,dependDir in ipairs(env.depends) do
			env.cwd = dependDir
			local push_distName = env.distName
			local push_distType = env.distType
			local push_depends = env.depends
			-- hmm, I should think this system through more ...
			-- in order to allow include buildinfos to modify state (and include things like macros, search paths, etc)
			-- I shouldn't be pushing/popping them
			-- but instead, check 'including' to see if a variable should be modified ...
			--local push_macros = macros

			env.distName = nil
			env.distType = nil
			env.depends = table()
			env.including = true
			--env:resetMacros()

			assert(loadfile(env.cwd..'/buildinfo', 'bt', loadenv))()
			local dependName = env.distName
			assert(env.distType == 'lib' or env.distType == 'inc')	--otherwise why are we dependent on it?
			env.include:insert(env.cwd..'/include')
			if (env.platform == 'linux' and env.distType == 'lib' and push_distType == 'app')
			or (env.platform == 'osx' and env.distType == 'lib')
			or (env.platform == 'msvc' and env.distType ~= 'inc')
			or (env.platform == 'mingw' and env.distType ~= 'inc')
			or (env.platform == 'clang_win' and env.distType ~= 'inc')
			then
				env:addDependLib(dependName, env.cwd)
			end
			
			--macros = push_macros
			env.distName = push_distName
			env.distType = push_distType
			env.depends = push_depends
			env.including = nil
		end

		env:postConfig()
		
		-- determine source files
		local srcs = env:getSources()
		if #srcs == 0 then
			print'no input files found'
		else
			local objs = srcs:map(function(f)
				f = f:gsub('^src/', 'obj/'..env.platform..'/'..env.build..'/')
				f = f:gsub('%.cpp$', env.objSuffix)
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
			if env.postBuildDist then
				env.postBuildDist(env:getResourcePath(dist))
			end
		end
	end
end

local cmds = {...}
if #cmds == 0 then cmds = {'all'} end
for _,cmd in ipairs(cmds) do
	if cmd == 'all' then
		--doBuild()	-- build debug and release
		doBuild{buildTypes={'release'}}	-- build just release by default
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
