--shortcut for -lmake
-- if we did use lua -lmake, then in order to determine where 'make' is, we must search through package.path
local path = require 'ext.path'
local fn = package.searchpath('make', package.path)
fn = fn:gsub('\\', '/')
local dir = path(fn):getdir()
dofile(dir..'/run.lua')
os.exit()
