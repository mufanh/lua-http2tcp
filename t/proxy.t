use strict;
use warnings;

use lib 'lib';
use Test::Nginx::Socket::Lua;

plan tests => 1 * (2 * blocks());

repeat_each(1);
no_shuffle();

our $main_config = <<_EOC_;
    stream {
        server {
            listen 10087;
            content_by_lua_block {
                local sock = ngx.req.socket()
                local len_str, err = sock:receive(8)
                ngx.log(ngx.INFO, "request len:", len_str)

                local len = tonumber(len_str)
                local json_str, err = sock:receive(len)
                ngx.log(ngx.INFO, "json:", json_str)

                local bytes = sock:send(len_str..json_str)
                ngx.log(ngx.INFO, "write bytes:", bytes)
            }
        }
    }
_EOC_

our $server_config = <<_EOC_;
    location /example-codec/failure {
        content_by_lua_block {
            local proxy = require("http2tcp.proxy")
            local codec = require("example.codec.example-codec")
            proxy.process("127.0.0.1", 8000, codec)
        }
    }

    location /example-codec/success {
        content_by_lua_block {
            local proxy = require("http2tcp.proxy")
            local codec = require("example.codec.example-codec")
            proxy.process("127.0.0.1", 10087, codec)
        }
    }
_EOC_

our $http_config = <<_EOC_;
_EOC_

add_block_preprocessor(sub {
    my ($block) = @_;
    $block->set_value("main_config", $main_config);
    $block->set_value("http_config", $http_config);
    $block->set_value("config", $server_config);
});

run_tests();

__DATA__

=== TEST 1: connection refused
--- request
POST /example-codec/failure
{"msgType": "queryMerchant","mid": "898000000001"}
--- error_code: 500
--- response_body
failed to connect, connection refused
--- SKIP

=== TEST 2: echoes
--- request
POST /example-codec/success
{"msgType": "queryMerchant","mid": "898000000001"}
--- error_code: 200
--- response_body
{"msgType": "queryMerchant","mid": "898000000001"}