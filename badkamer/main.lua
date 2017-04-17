-- Timers
-- 0 = Free
-- 1 = Online Check
-- 2 = DHT
-- 3 = Afzuiging
-- 4 = Free
-- 5 = Free
-- 6 = One shot telnet server on boot

local _M={} 
local config = require('config')
local telnet=require('telnet_srv')
local mqttBroker = "192.168.1.12"
local init_state_sub = {}
local five_min_hum = {}
local deviceID = config.deviceID

-- Pin which the relay is connected to
-- 6 = wc licht, 7 = Afzuiging, 5 = Leeg, 0 = Nachtlamp
local relayPins = { 6,7,5,0 }
local suctionPin = 7
for i,relayPin in ipairs(relayPins) do 
    gpio.mode(relayPin, gpio.OUTPUT)
    gpio.write(relayPin, gpio.HIGH)
end


local function valid_pin(pin)
    for i,relayPin in ipairs(relayPins) do 
        if pin == relayPin then
            return true
        end
    end
    return false
end

local m = mqtt.Client(string.gsub(wifi.sta.getmac(),':',''), 60)
m:on("connect", function(client) print ("connected") end)
m:on("offline", function(client)
    print("MQTT offline, restarting in 10 seconds.")
    tmr.alarm(1, 10000, 0, function()
        node.restart();
    end)
end)
 
local function mqtt_pub(item, value, qos, retain)
    m:publish(string.format("home/%s/%s", deviceID, item), value, qos, retain)
end

local function mqtt_update(relayPin,state)
    local topic = string.format("switch/%s/state", relayPin)
    if gpio.read(relayPin) == 1 then
        mqtt_pub(topic,"OFF",0,1)
    else
        mqtt_pub(topic,"ON",0,1)
    end
end

local function pin_states()
    local pin = {}
    for i,relayPin in ipairs(relayPins) do
        pin[i] = gpio.read(relayPin)
    end
    return(string.format('Switch States: %s %s %s %s', pin[1], pin[2], pin[3], pin[4]))
end

local function mqtt_sub(topic)
    if(type(topic) == 'table') then
        m:subscribe(topic,function()
            print("MQTT initial topics subscribed.")
        end)
    else
        error("'topic' should be an array-style table.")
    end
end

local function mqtt_unsub(topic)
    print(string.format("MQTT Unsubscribing to %s", topic))
    m:unsubscribe(topic)
end

local function switch(relayPin, state)
    gpio.write(relayPin, state)
    local power
    if state == 0 then
        power = "ON"
        print("Enabling Output")
    end
    if state == 1 then
        local power = "OFF"
        print("Disabling Output")
    end
    mqtt_update(relayPin, state)
end

-- On publish message receive event
m:on("message", function(client, topic, data)
    print(string.format("Received: %s: %s", topic , data))
    local pin,rest = string.match(topic,"switch/(%d+)(.*)")
    if (rest and #rest > 0 and init_state_sub[pin] == 1) then return end
    local relayPin = tonumber(pin)
    if (data == "ON" and valid_pin(relayPin)) then
        switch(relayPin, gpio.LOW)
        if relayPin == suctionPin then
            print("Setting 1 hour timer for suction")
	    tmr.alarm(3,3600000, tmr.ALARM_SINGLE, function() switch(suctionPin, gpio.HIGH) end)
        end
    elseif (data == "OFF" and valid_pin(relayPin)) then
        switch(relayPin, gpio.HIGH)
    end
    if rest and #rest > 0 then
       mqtt_unsub(topic)
       init_state_sub[pin] = 1
    end
    if data == 'EnableTelnet' and topic == string.format("home/%s/telnet", deviceID) and telnetState() == false then
        print('Enabling telnet server')
        telnet.setupTelnetServer()
        tmr.alarm(6,300000,0,function() telnet.telnetServer:close() end)
    end
    if data == 'DisableTelnet' and topic == string.format("home/%s/telnet", deviceID) and telnetState() then
        print('Disabling telnet server')
        telnet.telnetServer:close()
        tmr.stop(6)
    end
    print(pin_states())
end)
 
local function telnetState()
    if telnet.telnetServer and telnet.telnetServer:getaddr() then 
        return true
    else
        return false
    end
end

local stop_hum
local check_hum
local prev_hum
local function update_dht()
    local _, temp, hum = dht.read(4)
    table.insert(five_min_hum, hum)
    local avg_hum = 0
    for i,v in pairs(five_min_hum) do
        avg_hum = avg_hum + v / #five_min_hum
    end
    mqtt_pub('avgHum', avg_hum, 0, 0)
    if prev_hum and stop_hum == nil and hum - prev_hum > 10 then
        stop_hum = prev_hum + 5
        switch(suctionPin,gpio.LOW)
    end
    if stop_hum and avg_hum > stop_hum then check_hum = 1 end
    if stop_hum and check_hum and avg_hum <= stop_hum then
        switch(suctionPin,gpio.HIGH)
        tmr.stop(3)
        stop_hum = nil
        check_hum = nil
    end
    if five_min_hum[5] then
        table.remove(five_min_hum,1)
    end
    prev_hum = hum
    local telnet
    if telnetState() then telnet = 'Enabled' else telnet = 'Disabled' end
    mqtt_pub('temp', temp, 0, 0)
    mqtt_pub('humidity', hum, 0, 0)
    mqtt_pub('Telnet', telnet, 0, 0)
    mqtt_pub('Uptime', tmr.time(), 0, 0)
    mqtt_pub('MemFree', node.heap(), 0, 0)
    if stop_hum then mqtt_pub('StopHum', stop_hum, 0, 0) end
    if prev_hum then mqtt_pub('PrevHum', prev_hum, 0, 0) end
end

function _M.mqtt_connect()
    m:connect(mqttBroker, 1883, 0, function()
        print("MQTT connected to:" .. mqttBroker)
        local init_topic = {}
        for i,relayPin in ipairs(relayPins) do
            init_topic[string.format("home/%s/switch/%s/state", deviceID, relayPin)] = 0
        end
        init_topic[string.format("home/%s/switch/+",deviceID)] = 0
        init_topic[string.format("home/%s/telnet",deviceID)] = 0
        mqtt_sub(init_topic)
        update_dht()
    end,
    function()
        print("Can not connect restarting in 10 seconds...")
        tmr.alarm(1, 10000, 0, function() node.restart() end)
    end)
    tmr.alarm(2,60000, tmr.ALARM_AUTO, update_dht)
end

return _M