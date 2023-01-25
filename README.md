## Yes, *another* Build System.

[![Donate via Stripe](https://img.shields.io/badge/Donate-Stripe-green.svg)](https://buy.stripe.com/00gbJZ0OdcNs9zi288)<br>
[![Donate via Bitcoin](https://img.shields.io/badge/Donate-Bitcoin-green.svg)](bitcoin:37fsp7qQKU8XoHZGRQvVzQVP8FrEJ73cSJ)<br>

First I made a decent Makefile system.
I got it working on OSX, Linux, MinGW ... all but MSVC.
Then I found myself wanting to build stuff with MSVC ... without making those stupid .vcproj files, or another NMAKE script, or rewriting everything.
Because, if you have to rewrite everything, why use a one-platform tool to do it, like MSVC's stuff?
So I found myself in need of a rewrite.
Hence this simple build system.

It reads files labeled `buildinfo`.
Each buildinfo specifies the distribution name, type, and any dependencies.
They optionally can have a `depends` table that specifies the locations of all other dependent lmake-based projects.
More configuration information for the `buildinfo` can be found in the `run.lua` file.

## Command-Line Usage

If you want shell integration, make this file:

`lmake`:
```
#!/usr/bin/env sh
lua ~/path/to/make/run.lua "$@"
```
or for the windows users: `lmake.bat`:
```
@echo off
lua "C:\path\to\make\run.lua" %*
```
...with maybe an optional `-lluarocks.require` after `lua` depending on how your lua setup is.

and run it with the following arguments:
- `lmake clean` = cleans objects
- `lmake distclean` = cleans executable
- `lmake` = builds default configuration
- `lmake all` = builds debug and release
- `lmake debug` = builds debug
- `lmake release` = builds release
- `lmake distonly` = builds dist from objs only

## Lua Usage:

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
lua platform $PLATFORM make.lua
```

where $PLATFORM can be:
- `osx`
- `linux`
- `clang_win`
- `mingw`
- `msvc`

### As a Lua library:

I'm using this in a few other places:
- [cl-cpu](https://github.com/thenumbernine/cl-cpu-lua)
- [ffi-c](https://github.com/thenumbernine/lua-ffi-c)
- [lua-include](https://github.com/thenumbernine/include-lua)
- soon to be my [CL library](https://github.com/thenumbernine/lua-opencl) as I start to use SPIR-V more and more...
- ...and any other OpenCL project I have made based on that.
