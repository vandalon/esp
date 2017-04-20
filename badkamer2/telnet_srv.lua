--
-- setup a telnet server that hooks the sockets input
--
local _M = {}
local telnetServer = net.createServer(net.TCP, 10)

function _M.setupTelnetServer()
    local inUse = false
    local telnetSocket

    local function stopTelnetServer()
        if telnetServer:getaddr() then
            print('Disabling telnet server')
            telnetServer:close()
            tmr.stop(6)
        end
    end

    local function listenTelnet(sock)
        if inUse then
            sock:send("Already in use.\n")
            sock:close()
            return
        end
        inUse = true

        local function s_output(str)
            if sock:getaddr() and sock ~= nil then sock:send(str) end
        end

        local function disconnect(sock)
            if sock:getaddr() then sock:close() end
            node.output(nil)
            inUse = false
            tmr.unregister(5)
            stopTelnetServer()
        end

        node.output(s_output, 1)

	sock:on("connection",function(sock)
            tmr.alarm(5,120000,0,function() disconnect(sock) end)
        end)

        sock:on("receive",function(sock, input)
            tmr.stop(5)
            tmr.start(5)
            node.input(input)
        end)

        sock:on("disconnection",function(sock) disconnect(sock) end)

        sock:send("Welcome to NodeMCU world.\n> ")
        telnetSocket = sock
    end

    if telnetServer:getaddr() then print('Telnet server already running')
    elseif telnetSocket then
        if telnetSocket:getaddr() then print('Telnet connection still open') end
    else
        print('Enabling telnet server')
        telnetServer:listen(23, listenTelnet)
        tmr.alarm(6,60000,0,stopTelnetServer)
    end
end


return _M
