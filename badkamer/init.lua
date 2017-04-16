local config=require('config')
wifi.setmode(wifi.STATION)
print('set mode=STATION (mode='..wifi.getmode()..')')
print('MAC: ',wifi.sta.getmac())
print('chip: ',node.chipid())
print('heap: ',node.heap())
wifi.sta.config(config.ssid,config.wifi_psk)
wifi.sta.setip({ip=config.ip,netmask=config.netmask,gateway=config.gateway})

function dir()
    for k,v in pairs(file.list()) do 
       print(k .. " Size: " .. v)
    end
end

local telnet=require('telnet_srv')
telnet.setupTelnetServer()

function startup()
    local main=require('main')
    main.mqtt_connect()
end


wifi.sta.eventMonReg(wifi.STA_WRONGPWD, function() node.restart() end)
wifi.sta.eventMonReg(wifi.STA_APNOTFOUND, function() node.restart() end)
wifi.sta.eventMonReg(wifi.STA_FAIL, function() node.restart() end)
wifi.sta.eventMonReg(wifi.STA_GOTIP, function()
    print("Network connected.")
    print("Waiting 5 seconds before starting main script.")
    tmr.alarm(5,5000,0,startup)
    tmr.alarm(6,25000,0,function() telnetServer:close() end)
end)
wifi.sta.eventMonStart()
wifi.sta.connect()
