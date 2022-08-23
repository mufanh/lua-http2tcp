package = "lua-http2tcp"
version = "0.0.1-2"
supported_platforms = {"linux", "macosx"}

source = {
    url = "git://github.com/mufanh/lua-http2tcp",
    branch = "main",
    tag = "v0.0.1-2",
}

description = {
    summary = "tcp服务代理，支持将http报文转为特定格式的tcp报文转发.",
    homepage = "https://github.com/mufanh/lua-http2tcp",
    license = "Apache License 2.0",
    maintainer = "mufanh <mufan.huang@qq.com>"
}

dependencies = {
    "api7-lua-tinyyaml = 0.4.2",
    "lua-resty-ngxvar = 0.5.2",
    "luafilesystem = 1.7.0-2",
}

build = {
    type = "make",
    build_variables = {
        CFLAGS="$(CFLAGS)",
        LIBFLAG="$(LIBFLAG)",
        LUA_LIBDIR="$(LUA_LIBDIR)",
        LUA_BINDIR="$(LUA_BINDIR)",
        LUA_INCDIR="$(LUA_INCDIR)",
        LUA="$(LUA)",
    },
    install_variables = {
        INST_PREFIX="$(PREFIX)",
        INST_BINDIR="$(BINDIR)",
        INST_LIBDIR="$(LIBDIR)",
        INST_LUADIR="$(LUADIR)",
        INST_CONFDIR="$(CONFDIR)",
    },
}
