tmr.softwd(120)
local config=require('config')

local telnet=require('telnet_srv')
telnet.setupTelnetServer()

local function startup()
    local main=require('main')
    main.mqtt_connect()
end

wifi.setmode(wifi.STATION)
print('set mode=STATION (mode='..wifi.getmode()..')')
print('MAC: ',wifi.sta.getmac())
print('chip: ',node.chipid())
print('heap: ',node.heap())
wifi.sta.config(config.ssid,config.wifi_psk)
wifi.sta.setip({ip=config.ip,netmask=config.netmask,gateway=config.gateway})
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, function()
    print("Wireless Network connected.")
    if tmr.state(1) then
        print("Canceling restart...")
        tmr.unregister(1)
    end
    print("Waiting 5 seconds before starting main script.")
    tmr.alarm(0,5000,0,startup)
end)
wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, function()
    print("Can not connect, restarting in 10 seconds...")
    tmr.alarm(1, 5000, 0, function() node.restart() end)
    wifi.sta.connect()
end)
