--shortcut for -lmake.clean
local table = require 'ext.table'
local path = require 'ext.path'
local makefn = package.searchpath('make', package.path):gsub('\\', '/')
local makedir = path(makefn):getdir()
local luabin = arg[table(arg):keys():sort():inf()]
os.execute(luabin..' "'..makedir..'/run.lua" clean')
