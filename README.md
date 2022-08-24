# lua-http2tcp

tcp服务代理，支持将http报文转为特定格式的tcp报文转发。

## 1. 开发该工具的背景

因为公司技术栈原因，应用输出服务类型为tcp协议，但是应用服务的tps性能非常高，在性能测试时候发现jmeter施压性能太低，无法压测出真实的性能，所以在施压工具的选型就需要选择高性能的工具了，综合对比了wrk、ab等，最终选择wrk，wrk使用非阻塞压测模型，性能非常强大，能够用很少的资源发出巨大的压力。但是wrk只能压测HTTP，网上有个个人版本的wrktcp，本人尝试了一下，发现在压力大时候容易出现内存泄露导致崩溃，所以放弃了wrktcp。

在之前学习了解过apisix服务网关，采用openresty技术栈，使用较少的资源轻松实现10几万QPS，继而想通过复用wrk的施压能力和openresty的性能、扩展性，通过openresty接受http报文，然后编写lua插件将其转换为tcp报文对目标系统进行压测，就开发了这个工具。

该工具中关于openresty的request、response和上下文包装等工具方法参考了apisix框架的代码，感谢apisix这么优秀的开源项目，让我从中学习了很多如何使用openresty的技巧。

## 2. 该工具的工作流程

![工具工作流程](https://github.com/mufanh/http2tcp/blob/main/assets/工具工作流程.png)

- 1 HTTP报文格式你可以根据实际需要自己定义，本工具提供了很多方式可以从HTTP报文中提取关键域；

- 2 TCP报文不是标准的协议报文，每个业务系统甚至不同的服务都可以有自己个性化的，所以为了实现工具的通用性，提供了协议的抽象，使用该工具需要自己写编码和解码逻辑；

- 3 响应的报文格式也是自己定义的，在自己的解码器逻辑里面填充HTTP报文响应，本工具也提供了各种方式，支持将TCP关键域解析后的信息填充到HTTP响应的多个位置。

- 4 工具依赖安装。

```txt
luarocks install lua-http2tcp
```

## 3. HTTP报文提取工具

扩展自己的TCP协议的编解码逻辑时候，需要引入该工具的core工具包，方便各种操作，引入方式：

```lua
local core = require("http2tcp.core")
```

另外构造TCP报文的抽象中，传入了`ctx`是上下文，后面进行各种提取HTTP报文关键域是通过`ctx`来获取的。

- 1 HTTP报文GET请求的Request args提取，使用`arg_XXX`用于提取KEY为`XXX`的信息

```lua
ctx.var[arg_XXX]

// 获取所有的args
core.request.get_uri_args(ctx)
```

- 2 HTTP报文GET请求的Request Cookie提取，使用`cookie_XXX`用于提取KEY为`XXX`的信息

```lua
ctx.var[cookie_XXX]

// 暂时不对外使用获取所有cookie的，只能单独KEY获取
```

- 3 HTTP报文的Header中提取，提取规则可以配置为`http_XXX`，其中XXX为Header的KEY

```lua
ctx.var[http_XXX]

// 暂时不对外使用获取所有header的，只能单独KEY获取
```

- 4 HTTP报文的POST Args（key1=value1&key2=value2&...），这种提取方式特定用于form表单提交，因此提取判断了报文的Content-Type为application/x-www-form-urlencoded，提取规则可以配置为`post_arg_XXX`，其中XXX为Post Args的KEY

```lua
ctx.var[post_arg_XXX]

// 获取所有的post_args
core.request.get_post_args(ctx)
```

- 5 还可以提取HTTP BODY报文域，可以作为普通字符串获取，也可以直接获取JSON（本质上面还是获取字符串，然后使用cjson将其转为JSON字符串，若你本身不对json做任何处理，可以直接转成字符串就可以了，若需要对json进行添加字段或者删除字段，则获取json后处理）

```lua
// 获取body字符串
core.request.get_body(max_size, ctx)

// 获取body json对象
core.request.get_body_json(max_size, ctx)
```

PS:max_size可以传nil，表示body无论多大我都获取，或者传具体大小，若报文比这个大，可能会导致或者body失败，多次调用不会有影响问题，在调用get_body或者get_body_json后，我都会缓存body字符串或者body json对象。

## 4. HTTP报文填充工具

扩展自己的TCP协议解码获取信息后，会将该信息转换为HTTP报文响应出去，需要引入该工具的core工具包，方便各种操作，引入方式：

```lua
local core = require("http2tcp.core")
```

- 1 填充HTTP响应BODY，`XXX`为响应报文的内容字符串

```lua
core.response.say(XXX)
```

- 2 填充HTTP报文的Header

```lua
// 参数1：针对Header中存在的KEY，true表示追加，false表示覆盖
// 参数2：填充的KEY
// 参数3：填充的VALUE
core.response.set_header(true/false, KEY, VALUE)

// 相当于set_header(false, KEY, VALUE)
core.response.set_header(KEY, VALUE)
```

- 3 填充HTTP报文的Cookie

```lua
local cookie_record = {
    key = KEY, // cookie的KEY
    path = PATH, // cookie的有效PATH范围
    max_age = MAX_AGE, // cookie的有效期，单位秒
    domain = DOMAIN, // cookie的域名作用域
    secure = true/false, // true表示https才会传递到服务端，http不会，false不限制，都会传递到服务端
    httponly = true/false, // true表示cookie不能被js获取，false表示可以
}

core.response.set_cookie(cookie_record)
```

## 5. TCP报文协议抽象

该处使用公司使用的某种tcp报文协议进行说明，该TCP报文的格式如下：

![示例报文格式](https://github.com/mufanh/http2tcp/blob/main/assets/example-codec.png)

使用该工具，设置HTTP报文，BODY存放JSON字符串，然后转换为TCP报文，为了提升性能，工具处不解析JSON，仅当字符串处理，计算其长度后，拼装前面长度域。

自定义lua插件编写方式详细见[例子](https://github.com/mufanh/lua-http2tcp/blob/main/example/codec/example-codec.lua)。

- 1 构造TCP请求报文

该协议插件包含build_tcp_msg，入参为ctx，返回值有三个部分。第一个返回值true/false，表示是否构造成功，若构造成功，第二个返回值为nil，则第三个返回值是构造的TCP报文字符串；若构造失败，第二个值表示错误码（会作为http响应码返回），第三个表示错误原因，会作为http响应报文体返回。

```lua
function _M.build_tcp_msg(ctx)
    // 获取HTTP报文体字符串
    local request_body = core.request.get_body(nil, ctx)
    if not request_body then
        return false, 400, "empty request body"
    end
    // 获取报文体字符串的长度
    local len = string.len(request_body)
    if len == 0 then
        return false, 400, "request body blank"
    end
    // 前面8位长度域，不足8位补0
    return true, nil, string.format("%08d%s", len, request_body)
end
```

- 2 读取TCP报文响应并构造HTTP响应体

因为TCP报文本身有粘包和分包问题，而且每种TCP协议的报文都不一样，所以没有办法直接获取某个TCP报文然后处理，所以该实现相比较构造报文来说复杂一些，需要传入cosocket对象（cosocket本身的知识是属于openresty最核心的东西，不详细介绍），然后通过cosocket对象对响应进行处理。

```lua
function _M.recieve_tcp_msg(sock)
    // 获取8个字节，若TCP报文没有8个字节，若再超时时间内一直没有获取到，则失败（此处可能超时，也可能服务端断开连接，都会报错）
    // 此处虽然是同步，但是cosocket会挂起协程，然后然cpu继续去做nginx的其他事情，非阻塞，不影响性能
    local len, err = sock:receive(8)
    if not len then
        return false, 500, "recieve msg err, " .. err
    end

    // 将获取的前8个字节转为十进制，若转换失败，那证明报文格式不对，直接报错
    local len = tonumber(len)
    if not len then
        return false, 500, "recieve msg format err, " .. err
    end

    // 根据长度域的长度，获取TCP报文体的内容，若获取不到或者报文长度不足，则一直等待，直到超时
    // 超时则报错，服务端断开连接也报错
    local res_data, err = sock:receive(len)
    if not res_data then
        return false, 500, "recieve msg err, " .. err
    end

    // 将获取的TCP报文体内容作为HTTP报文体内容响应
    core.response.say(res_data)
    return true
end
```

PS：要使用该工具，需要对openresty有一定熟悉，特别是cosocket的原理和使用方式，网上有大量资料，cosocket可以实现各种第三方组件的适配，非常强大，感兴趣的读者可以自行去研究学习。

## 6. 工具使用方式

```nginx
location /example-codec {
   	content_by_lua_block {
            local proxy = require("http2tcp.proxy")
            local codec = require("example.codec.example-codec")
            // 具体要转发的IP、端口、编码解码器（参考上面文档介绍编写）、连接池大小和连接池保活时间、连接超时时间
            // 第4个参数可以不填，就用默认值（pool_size=100,pool_keepalive=2000,connect_timeout=1000,write_timeout=1000,read_timeout=1000)，你想换哪个配置就填哪个配置也可以，不用都配置
            proxy.process("127.0.0.1", 10089, codec, { pool_size = 300, pool_keepalive = 200000, read_timeout = 4000 })
    }
}
```

PS：另外需要注意：配置的连接池是worker级别，比如nginx启动4个worker，配置pool_size=300，那么最大其实是有4*300=1200个连接。

## 7. 协议转换工具性能

本次性能只是协议转换工具+挡板的工具，实际性能应该是高于该性能的，压测过程采用openresty的线性相关性绑定到4C上面执行，4C的CPU利用率大概再80%左右，TPS压测下来可以支持10.8W+，实际性能应该还会高一点。

其中wrk利用线性相关性绑定10，11，12，13核，转换工具占用0，1，2，3核。工具是无状态的，所以理论上来说机器资源足够的情况下，可以达到单机百万TPS。（当然，还可能收到其他资源的影响，特别是带宽等因素）

PS:下面使用的wrk是本人fork wrk改造过后，支持线程亲和性特性的wrk。

```txt
[netpay@netpay-uat-3 performance-http2tcp-demo]$  wrk -t4 -c40 -d120s -a10,11,12,13 --script=/app/netpay/request.lua --latency http://127.0.0.1:60086/example-codec
this thread 7f09f2414700 is running in processor 10
this thread 7f09f2414700 is running in processor 11
this thread 7f09f2414700 is running in processor 12
this thread 7f09f2414700 is running in processor 13
this thread 7f09f1c13700 is running in processor 10
this thread 7f09f1c13700 is running in processor 11
this thread 7f09f1c13700 is running in processor 12
this thread 7f09f1c13700 is running in processor 13
this thread 7f09f1412700 is running in processor 10
this thread 7f09f1412700 is running in processor 11
this thread 7f09f1412700 is running in processor 12
this thread 7f09f1412700 is running in processor 13
Running 2m test @ http://127.0.0.1:60086/example-codec
  4 threads and 40 connections
this thread 7f09f0c11700 is running in processor 10
this thread 7f09f0c11700 is running in processor 11
this thread 7f09f0c11700 is running in processor 12
this thread 7f09f0c11700 is running in processor 13
  Thread Stats   Avg      Stdev     Max   +/- Stdev
    Latency   385.03us  280.93us  21.58ms   98.58%
    Req/Sec    27.19k     1.79k   56.28k    80.07%
  Latency Distribution
     50%  358.00us
     75%  391.00us
     90%  429.00us
     99%    1.29ms
  12989957 requests in 2.00m, 2.99GB read
Requests/sec: 108159.94
Transfer/sec:     25.48MB
```

## 8. demo下载

为了简化该工具的使用，编写了demo工程([下载地址](https://github.com/mufanh/lua-http2tcp/blob/main/assets/http2tcp-test.tar))，详细如下所示。

```txt
./
├── conf
│   ├── mime.types
│   ├── nginx.conf
│   └── vhost
│       └── http2tcp.conf
└── example
    └── codec
        └── example-codec.lua

```

其中：

1）nginx.conf包含方便测试的一个tcp服务挡板，通过stream lua写的一个简单的回声挡板；

2）http2tcp.conf具体包含http转tcp的配置方式；

3）http转tcp需要自定义的协议lua插件编写。

运行该demo建议使用`openresty -p 该工具目录`运行，并且需要您已经安装好了openresty、luarocks，并且需要安装http2tcp的依赖。（依赖安装方式`luarocks install lua-http2tcp`)
