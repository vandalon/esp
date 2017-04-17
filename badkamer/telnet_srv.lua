--
-- setup a telnet server that hooks the sockets input
--
local _M = {}
function _M.setupTelnetServer()
    inUse = false
    function listenFun(sock)
        if inUse then
            sock:send("Already in use.\n")
            sock:close()
            return
        end
        inUse = true

        function s_output(str)
            if(sock ~=nil) then
                sock:send(str)
            end
        end

        node.output(s_output, 0)

        sock:on("receive",function(sock, input)
                node.input(input)
            end)

        sock:on("disconnection",function(sock)
                node.output(nil)
                inUse = false
            end)

        sock:send("Welcome to NodeMCU world.\n> ")
    end

    
    _M.telnetServer = net.createServer(net.TCP, 180) 
    _M.telnetServer:listen(23, listenFun)
end
return _M
