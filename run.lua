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
including = flag set if this bulidinfo is being interpreted from another buildinfo
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

objLogFile = filename to save output of buildObj
distLogFile = filename to save output of buildDist
--]]

local file = require 'ext.file'
local table = require 'ext.table'
local find = require 'make.find'
local exec = require 'make.exec'

-- this either looks at global 'platform' or runs make.detect 
local Env = require 'make.env'
local env = Env()
print("using environment: "..env.name)


-- this is internal to ext, but it is how ext provides the file:attr() wrapper
if not require 'ext.detect_lfs'() then 
	print("can't find lfs -- can't determine last file modification time -- rebuilding all")
end

local function needsUpdate(target, depends)
	if not file(target):exists() then return true end
	
	local targetAttr = file(target):attr()
	if not targetAttr then return true end

	local dependModification
	for _,depend in ipairs(depends) do
		local dependAttr = assert(file(depend):attr())
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
		env:setupBuild(_build)
		
		--[[ build pch
		do
			local headers = env:getHeaders()	-- 'include' folder
			local pchs = headers:map(function(f)
				f = f:gsub('^include/', 'incbin/'..env.platform..'/'..env.build..'/')
				f = f .. '.gch' 
				return f
			end)
			for i,header in ipairs(headers) do
				local pch = assert(pchs[i])
				local dependentHeaders = env:getDependentHeaders(header, pch, true)
				if needsUpdate(header, dependentHeaders) then
					env:buildPCH(pch, header)
				end
			end
		end
		--]]

		-- determine source files
		local srcs = env:getSources()	-- 'src' folder
		if #srcs == 0 then
			print'no input files found'
		else
			local objs = srcs:map(function(f)
				f = f:gsub('^src/', 'obj/'..env.platform..'/'..env.build..'/')
				f = f:gsub('%.cpp$', env.objSuffix)
				return f
			end)

			if not args.distonly then
				for i,obj in ipairs(objs) do
					local src = assert(srcs[i])

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
if #cmds == 0 then cmds = {'debug'} end	-- build just debug by default
for _,cmd in ipairs(cmds) do
	if cmd == 'all' then
		doBuild{buildTypes={'debug', 'release'}}
	elseif cmd == 'debug' or cmd == 'release' then
		doBuild{buildTypes={cmd}}
	elseif cmd == 'clean' then
		env:clean()
	elseif cmd == 'distclean' then	
		env:distclean()
	elseif cmd == 'distonly' then
		doBuild{distonly=true}
	-- TODO 'run' for building a LD_LIBRARY_PATH of all the dependent projects (so you don't have to install and don't have to copy the libs it is dependent on)
	elseif cmd == 'depends' then
		local cmdargs = table(cmds)
		cmdargs:removeObject'depends'
		
		-- TODO set up for each debug/release buildType and recurse into dependencies separately
		-- until then, I'll just gather for one specific build type and recurse through those and reissue all 
		local depends
		do
			tmpenv = Env()
			tmpenv:setupBuild'debug'
			depends = tmpenv.depends
		end
		
		for _,depend in ipairs(depends) do
			-- TODO forward all args, with spaces, etc
			env:exec('cd "'..depend..'" && lmake '..cmdargs:mapi(function(s) return ('%q'):format(s) end):concat' ', true)
		end
	else
		error('unknown command: '..cmd)
	end
end
