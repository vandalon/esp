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
wifi.eventmon.register(wifi.eventmon.STA_DISCONNECTED, function() node.restart() end)
wifi.eventmon.register(wifi.eventmon.STA_GOT_IP, function()
    print("Network connected.")
    print("Waiting 5 seconds before starting main script.")
    tmr.alarm(0,5000,0,startup)
end)
wifi.sta.connect()
