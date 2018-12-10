--shortcut for -lmake
-- if we did use lua -lmake, then in order to determine where 'make' is, we must search through package.path
local io = require 'ext.io'

local fn = package.searchpath('make', package.path)
fn = fn:gsub('\\', '/')
local dir = io.getfiledir(fn)
dofile(dir..'/run.lua')
os.exit()
