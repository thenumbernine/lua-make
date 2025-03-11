## Yes, *another* Build System.

[![Donate via Stripe](https://img.shields.io/badge/Donate-Stripe-green.svg)](https://buy.stripe.com/00gbJZ0OdcNs9zi288)<br>

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

## Reference

### globals defined per-project:
- `distName` = name of the project
- `distType` = type of the project. possible options are:
- - `'app'` for applications / executables.
- - `'lib'` for libraries.
- - `'inc'` for include files (no code / nothing to build, but still used for `buildinfo` dependencies).
- `depends` = table of paths to other `lmake` projects that this is dependent upon.

### globals defined by lua-make that you can override:
- `env` = reference back to the global environment object.
- `home` = home directory.
- `platform` = build platform.
- `build` = `'debug'` or `'release'`.
- `objSuffix` = suffix of object file.  `'.o'` on unix systems, `'.obj'` in M$ systems.
- `libPrefix` = prefix of library files.  `'lib'` on unix systems.
- `libSuffix` = lib suffix. `'.so'`, `'.dylib'`, `'.a'`, `'.lib'`, `'.dll'`, etc.
- `appSuffix` = executable suffix.  empty on unix systems, '.exe' for M$.
- `compiler` = compiler binary name.  `'g++'`, `'clang++'`, `'cl.exe'`, etc...
- `compileFlags` = flags to pass to compiler.
- `compileIncludeFlag` = flag for include directory.
- `compileMacroFlag` = flag for C++ macros.
- `compileOutputFlag` = flag for output filename.
- `compileGetIncludeFilesFlag` = flag for getting include files referenced by this file.
- `including` = flag set if this `buildinfo` is being interpreted from another `buildinfo`.
- `linker` = linker binary name.
- `linkLibPathFlag` = flag for adding library search paths.
- `linkLibFlag` = flag for adding libraries.
- `linkOutputFlag` = flag for specifying the output filename.
- `linkFlags` = extra flags to send to the linker
- `cppver` = C++ version.
- `include` = table of include directories to forward to the C++ compiler.
- `dependLibs` = other luamake projects that the project is dependent upon (for executing recursive buildinfos).
- `libs` = `-l` libraries, be they static or dynamic, automatically detected by the compiler/linker.
- `libpaths` = `-L` search paths for `libs`.
- `dynamicLibs`
- - on linux this contains paths to explicit `.so` files.
- - on osx this is `.dylib` files.
- - on windows this is `.lib` files associated with `.dll` files (as opposed to the `.lib` files that are static libraries ... smh windows).
- `objLogFile` = filename to save output of `Env:buildObj()`.
- `distLogFile` = filename to save output of `Env:buildDist()`.
- `pthread` = set this flag when including pthread.  Maps to `-pthread` in GCC.
- `fileCfgs[filename] = function(fileEnv)` = per-file callback that can be registered to configure the per-file environment, in case any files need vars changed from the global env.

## As a Lua library:

I'm using this in a few other places:
- [cl-cpu](https://github.com/thenumbernine/cl-cpu-lua)
- [ffi-c](https://github.com/thenumbernine/lua-ffi-c)
- [lua-include](https://github.com/thenumbernine/include-lua)
- soon to be my [CL library](https://github.com/thenumbernine/lua-opencl) as I start to use SPIR-V more and more...
- ...and any other OpenCL project I have made based on that.
