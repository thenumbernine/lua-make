--shortcut for -lmake.clean
local table = require 'ext.table'
local io = require 'ext.io'
local makefn = package.searchpath('make', package.path):gsub('\\', '/')
local makedir = io.getfiledir(makefn)
local luabin = arg[table(arg):keys():sort():inf()]
os.execute(luabin..' "'..makedir..'/run.lua" clean')
os.exit()
