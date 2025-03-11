#!/usr/bin/env lua
--[[
lua /path/to/make/run.lua [cmd]
reads buildinfo
cmd is: build debug release clean distclean
--]]
local table = require 'ext.table'
local Targets = require 'make.targets'

local cmds = table{...}
for i=1,#cmds do
	if cmds[i] == 'platform' then
		-- set global for env.lua to pick up on prior to calling 'make.detect'
		platform = cmds[i+1]
		cmds:remove(i+1)
		cmds:remove(i)
	end
end

-- this is internal to ext, but it is how ext provides the path:attr() wrapper
if not require 'ext.detect_lfs'() then
	print("can't find lfs -- can't determine last file modification time -- rebuilding all")
end

-- this either looks at global 'platform' or runs make.detect
local Env = require 'make.env'
print("using environment: "..Env.name)

-- static method
function Env.needsUpdate(target, depends)
	return Targets{
		verbose = true,
	}:needsUpdate{
		dsts = {target},
		srcs = depends,
	}
end


--[[
TODO change this into a file-based rule system
make it modular
then use it in cl/obj/program.lua for compiling code->cl->bin
--]]
local function doBuild(args)
	args = args or {}
	for _,_build in ipairs(args.buildTypes or {'debug', 'release'}) do

		local env = Env()

		env.verbose = true

		-- TODO should I be doing this?  or should I be building a new Env() object for each platform?
		-- but to rebuild env means what env do we use for cmdline cmds below?
		env:setupBuild(_build)

		-- making a separate 'targets' per build-type because
		-- for each 'targets' I'm using a separate env:setupBuild
		-- so things are distinctly separate / state-based
		env.targets.verbose = true

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
				if env.needsUpdate(header, dependentHeaders) then
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
				f = f:gsub('^'..env.srcDir..'/', env:getPathToObj()..'/')
				f = f:gsub('%.cpp$', env.objSuffix)
				return f
			end)

			if not args.distonly then
				for i,obj in ipairs(objs) do
					local src = assert(srcs[i])

					-- see if we can search for the include the files that this source file depends on
					-- TODO this as a rule so we don't have to regenerate them for untouched files
					-- TODO env:getDependentHeaders() uses targets too  ... maybe move it into make/run.lua?
					local dependentHeaders = env:getDependentHeaders(src, obj)

					-- if the source file has been modified since the obj was created
					-- *or* the dependent headers have been modified since the obj was created
					-- *or* the buildinfo has been modified since the obj was created
					-- then rebuild
					-- (otherwise you can skip this build)
					env.targets:add{
						dsts = {obj},
						srcs = table.append({src}, dependentHeaders),

						rule = function(r)
							-- [[ setup env specific for the file here
							-- here and make/env.lua Env:getDependentHeaders()
							local fileEnv = Env(env)
							local f  = env.fileCfgs[src]
							if f then f(fileEnv) end
							--]]

							assert(fileEnv:buildObj(obj, src))
						end,
					}
				end
			end

			local dist = env:getDist()
			env.targets:add{
				dsts = {dist},
				srcs = objs,
				rule = function()
					-- [[ setup env specific for the file here
					-- here and above and make/env.lua Env:getDependentHeaders()
					local fileEnv = Env(env)
					local f  = env.fileCfgs[src]
					if f then f(fileEnv) end
					--]]

					fileEnv:buildDist(dist, objs)
				end,
			}

			env.targets:run(dist)
		end

		-- if postBuildDist is defined then do that too
		if env.postBuildDist then
			env.postBuildDist(env:getResourcePath())
		end
	end
end

if #cmds == 0 then cmds = {'debug'} end	-- build just debug by default
for _,cmd in ipairs(cmds) do
	if cmd == 'all' then
		doBuild{buildTypes={'debug', 'release'}}
	elseif cmd == 'debug' or cmd == 'release' then
		doBuild{buildTypes={cmd}}
	elseif cmd == 'clean' then
		local env = Env()
		env:clean()
	elseif cmd == 'distclean' then
		local env = Env()
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
			local tmpenv = Env()
			tmpenv:setupBuild'debug'
			depends = tmpenv.depends
		end

		for _,depend in ipairs(depends) do
			-- TODO forward all args, with spaces, etc
			local env = Env()
			env:exec('cd "'..depend..'" && lmake '..cmdargs:mapi(function(s) return ('%q'):format(s) end):concat' ', true)
		end
	else
		error('unknown command: '..cmd)
	end
end
