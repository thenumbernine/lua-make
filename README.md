[![paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=KYWUWS86GSFGL)

Yes, this is yet *another* build system.

First I made a decent Makefile system.
I got it working on OSX, Linux, MinGW ... all but MSVC.
Then I found myself wanting to build stuff with MSVC ... without making those stupid .vcproj files, or another NMAKE script, or rewriting everything.
Because, if you have to rewrite everything, why use a shitty one-platform shit-tool to do it, like MSVC's stuff?
So I found myself in need of a rewrite.
Hence this simple build system.

It reads files labeled 'buildinfo'
Each buildinfo specifies the distribution name, type, and any dependencies.
They optionally can have a depend() function that sets up any other dependencies needed for projects that depend on them.

usage:

if you're lazy:
```
	lua -lmake
```
	
and to clean ...
```
	lua -lmake.clean
```

if you want to do more than one thing at once...
```
	lua /path/to/lua/make/run.lua clean distclean all
```


if you want a custom platform:
```
	lua -e "platform='$PLATFORM'" make.lua
```

where $PLATFORM can be:
-	`osx`
-	`linux`
-	`clang_win`
-	`mingw`
-	`msvc`

or if you want a bit better shell access to run this, make this file:
lmake:
```
	#!/usr/bin/env sh
	lua ~/path/to/make/run.lua "$@"
```

and run it with the following arguments:
-	`lmake clean` = cleans objects
-	`lmake distclean` = cleans executable
-	`lmake` = builds default configuration
-	`lmake all` = builds debug and release
-	`lmake debug` = builds debug
-	`lmake release` = builds release
-	`lmake distonly` = builds dist from objs only

Alright I want to use this in other scripts,
The specific Make subclass needs to be selected by the OS.
The compile cpp to obj and obj to app commands need to be callable from outside.
