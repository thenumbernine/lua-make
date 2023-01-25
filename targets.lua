--[[
make-target system
like gnu-make, scons, and everyone else uses

you know, this is completely uncoupled from make.run (which is going to use this to do the building)
 and from make.env (which holds the per-platform per-compiler env settings)
so much that i am tempted to put it into its own project ...

but then again, so far the only projects that will use it, will be using it in conjunction with compilers,
so it might be helpful to keep make.env nearby

ex:

targets = Targets()
targets:add{
	dsts = {'a.out'},
	srcs = {'a.cpp'},
	rule = function()
	-- or maybe string-only optional for just a shell command?
	-- tho stuff like -M for getting the include graph would be useful to do as a function
	-- or I could do the -M thing as a file dependency too ...
	end,
}
targets:run('dst1', 'dst2', ...)	-- should this be by some extra .name field, or should it be by .dsts? matching one .dsts?  matching all? how would that work.

--]]
local class = require 'ext.class'
local table = require 'ext.table'
local file = require 'ext.file'

local Targets = class()

--[[
args:
	dsts
	srcs
	rule
--]]
function Targets:add(args)
	assert(args.dsts)
	assert(args.rule)
	table.insert(self, args)
end

-- hmm, merge env.needsUpdate into this?
-- expects indexed tables. rule.srcs, rule.dsts
function Targets:needsUpdate(rule)
	local dstModTime
	for _,dst in ipairs(rule.dsts) do
		if not file(dst):exists() then return true end
		
		local dstAttr = file(dst):attr()
		-- if any dsts can't be attr'd then I guess it's gotta be rebuilt
		if not dstAttr then
			if self.verbose then
				print(' *** found a dest with no stats -- rebuilding')
			end
			return true
		end
		if not dstModTime then
			dstModTime = dstAttr.modification
		else
			if dstAttr.modification < dstModTime then
				dstModTime = dstAttr.modification
			end
		end
	end
	-- if any were nil then we alreayd returned true
	-- so if this condition si hit then that means we have an empty dsts
	if not dstModTime then error("hmm, seems you have no dsts") end

	local srcModTime
	if #rule.srcs == 0 then
		error("no inputs to target")
	end
	for _,src in ipairs(rule.srcs) do
		local srcAttr = assert(file(src):attr())
		if not srcModTime then
			srcModTime = srcAttr.modification
		else
			if srcAttr.modification > srcModTime then
				srcModTime = srcAttr.modification
			end
		end
	end
	if not srcModTime then
		if self.verbose then
			print(' *** failed to find any source modification timestamp -- rebuilding')
		end
		return true
	end

	if srcModTime >= dstModTime then return true end
	
	if self.verbose then
		local date = function(...) return os.date('%Y-%m-%d %H:%M:%S', ...) end
		print(' *** target up-to-date: '..table.concat(rule.dsts, ', ')..' ('..date(dstModTime)..' vs '..date(srcModTime)..')')
	end
	return false
end

function Targets:ruleIndex(dst)
	for j,r in ipairs(self) do
		if table.find(r.dsts, dst) then
			-- TODO return multiple indexes?
			return j
		end
	end
end

function Targets:run(...)
	local sofar = {}
	local indexes = {}
	for i=1,select('#', ...) do
		local dst = select(i, ...)
		local index = self:ruleIndex(dst)
		if index then
			indexes[index] = true
		else
			error("failed to find in any rule target "..dst)
		end
	end
	indexes = table.keys(indexes):sort()
	for _,i in ipairs(indexes) do
		local r = assert(self[i])
		
		-- make sure the source files are all built
		for _,src in ipairs(r.srcs) do
			-- if 'src' might need to be built too ...
			if self:ruleIndex(src) then
				-- make sure it is up to date also ...
				-- TODO keep track of src's and only check them once per :run(dst) ...
				self:run(src)
				-- if it's still not there then error
				if not file(src):exists() then
					error("couldn't build dependency "..src)
				end
			end
		end
		
		if self:needsUpdate(r) then
			r:rule()
			for _,dst in ipairs(r.dsts) do
				sofar[dst] = true
			end
		end
	end
end

return Targets
