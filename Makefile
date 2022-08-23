OPENRESTY_INSTALL_DIR ?= /usr/local/openresty

.PHONY: all test install

all: ;

luacheck:
	luacheck http2tcp/**
	@echo ""

luareleng:
	util/lua-releng
	@echo ""

test: luareleng luacheck
	prove -I../test-nginx/lib -r -s t/
