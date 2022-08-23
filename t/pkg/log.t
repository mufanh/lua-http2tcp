use strict;
use warnings;

use lib 'lib';
use Test::Nginx::Socket::Lua;
use Cwd qw(cwd);

plan tests => 2 * (3 * (blocks() + 5));

repeat_each(2);
no_shuffle();
run_tests();

__DATA__

=== TEST 1: error log
--- config
    location /t {
        content_by_lua_block {
            local core = require("http2tcp.core")
            core.log.error("error log")
            core.log.warn("warn log")
            core.log.notice("notice log")
            core.log.info("info log")
            ngx.say("done")
        }
    }
--- log_level: error
--- request
GET /t
--- error_log
error log
--- no_error_log
warn log
notice log
info log



=== TEST 2: warn log
--- config
    location /t {
        content_by_lua_block {
            local core = require("http2tcp.core")
            core.log.error("error log")
            core.log.warn("warn log")
            core.log.notice("notice log")
            core.log.info("info log")
            core.log.debug("debug log")
            ngx.say("done")
        }
    }
--- log_level: warn
--- request
GET /t
--- error_log
error log
warn log
--- no_error_log
notice log
info log
debug log



=== TEST 3: notice log
--- config
    location /t {
        content_by_lua_block {
            local core = require("http2tcp.core")
            core.log.error("error log")
            core.log.warn("warn log")
            core.log.notice("notice log")
            core.log.info("info log")
            core.log.debug("debug log")
            ngx.say("done")
        }
    }
--- log_level: notice
--- request
GET /t
--- error_log
error log
warn log
notice log
--- no_error_log
info log
debug log



=== TEST 4: info log
--- config
    location /t {
        content_by_lua_block {
            local core = require("http2tcp.core")
            core.log.error("error log")
            core.log.warn("warn log")
            core.log.notice("notice log")
            core.log.info("info log")
            core.log.debug("debug log")
            ngx.say("done")
        }
    }
--- log_level: info
--- request
GET /t
--- error_log
error log
warn log
notice log
info log
--- no_error_log
debug log



=== TEST 5: debug log
--- config
    location /t {
        content_by_lua_block {
            local core = require("http2tcp.core")
            core.log.error("error log")
            core.log.warn("warn log")
            core.log.notice("notice log")
            core.log.info("info log")
            core.log.debug("debug log")
            ngx.say("done")
        }
    }
--- log_level: debug
--- request
GET /t
--- error_log
error log
warn log
notice log
info log
debug log



=== TEST 6: print error log with prefix
--- config
    location /t {
        content_by_lua_block {
            local log_prefix = require("http2tcp.core").log.new("prefix: ")
            log_prefix.error("error log")
            log_prefix.warn("warn log")
            log_prefix.notice("notice log")
            log_prefix.info("info log")
            ngx.say("done")
        }
    }
--- log_level: error
--- request
GET /t
--- error_log eval
qr/[error].+prefix: error log/
--- no_error_log
[qr/[warn].+warn log/, qr/[notice].+notice log/, qr/[info].+info log/]



=== TEST 7: print both prefixed error logs and normal logs
--- config
    location /t {
        content_by_lua_block {
            local core = require("http2tcp.core")
            local log_prefix = core.log.new("prefix: ")
            core.log.error("raw error log")
            core.log.warn("raw warn log")
            core.log.notice("raw notice log")
            core.log.info("raw info log")

            log_prefix.error("error log")
            log_prefix.warn("warn log")
            log_prefix.notice("notice log")
            log_prefix.info("info log")
            ngx.say("done")
        }
    }
--- log_level: error
--- request
GET /t
--- error_log eval
[qr/[error].+raw error log/, qr/[error].+prefix: error log/]
--- no_error_log
[qr/[warn].+warn log/, qr/[notice].+notice log/, qr/[info].+info log/]