package = "make"
version = "dev-1"
source = {
	url = "git+https://github.com/thenumbernine/lua-make"
}
description = {
	summary = "makefile-equivalent target system",
	detailed = "makefile-equivalent target system",
	homepage = "https://github.com/thenumbernine/lua-make",
	license = "MIT"
}
dependencies = {
	"lua >= 5.1"
}
build = {
	type = "builtin",
	modules = {
		["make.clean"] = "clean.lua",
		["make.detect"] = "detect.lua",
		["make.distclean"] = "distclean.lua",
		["make.env"] = "env.lua",
		["make.exec"] = "exec.lua",
		["make.find"] = "find.lua",
		["make"] = "make.lua",
		["make.run"] = "run.lua",
		["make.targets"] = "targets.lua",
		["make.writechanged"] = "writechanged.lua"
	}
}
