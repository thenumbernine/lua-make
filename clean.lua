--shortcut for -lmake.clean
local table = require 'ext.table'
local file = require 'ext.file'
local makefn = package.searchpath('make', package.path):gsub('\\', '/')
local makedir = file(makefn):getdir()
local luabin = arg[table(arg):keys():sort():inf()]
os.execute(luabin..' "'..makedir..'/run.lua" clean')
