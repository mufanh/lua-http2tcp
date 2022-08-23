use strict;
use warnings;

use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

plan tests => 1 * (3 * blocks());

repeat_each(1);
no_shuffle();
run_tests();

__DATA__

=== TEST 1: build_tcp_msg
--- config
    location /t {
        content_by_lua_block {
            local codec = require("example.codec.example-codec")
            local core = require("http2tcp.core")

            local function fetch_ctx()
                local ctx = ngx.ctx.route_ctx
                if ctx == nil then
                    ctx = core.tablepool.fetch("route_ctx", 0, 32)
                    ngx.ctx.route_ctx = ctx
                    core.ctx.set_vars_meta(ctx)
                end
                return ctx
            end

            local function release_ctx(ctx)
                core.ctx.release_vars(ctx)
                core.tablepool.release("route_ctx", ctx, true)
            end

            local ctx = fetch_ctx()
            local r, code, data = codec.build_tcp_msg(ctx)
            ngx.say(data)

            release_ctx(ctx)
        }
    }
--- request
POST /t
{"a":1,"b":"huangxinquan"}
--- response_body
00000026{"a":1,"b":"huangxinquan"}
--- no_error_log
[error]