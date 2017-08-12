-- Timers
-- 0 = Free
-- 1 = Online Check
-- 2 = Free
-- 3 = Motion timeout
-- 4 = Uptime publisher
-- 5 = Telnet Idle Timeout
-- 6 = Telnet Server Timeout

local _M={} 
local config = require('config')
local telnet = require('telnet_srv')
local mqttBroker = "192.168.1.12"
local init_state_sub = {}
local deviceID = config.deviceID
local pirPin = config.pirPin
mqtt_connected = 0

-- Pin which the relay is connected to
for i,relayPin in ipairs(config.relayPins) do 
    gpio.mode(relayPin, gpio.OUTPUT)
end

local function valid_pin(pin)
    for i,relayPin in ipairs(config.relayPins) do 
        if pin == relayPin then
            return true
        end
    end
    return false
end

local m = mqtt.Client(string.gsub(wifi.sta.getmac(),':',''), 60)
m:on("connect", function(client)
    mqtt_connected = 1
    print ("connected")
    if tmr.state(1) then tmr.stop(1) end
end)

local function mqtt_pub(item, value, qos, retain)
    m:publish(string.format("home/%s/%s", deviceID, item), value, qos, retain)
end

local function mqtt_update(relayPin,state)
    local topic = string.format("switch/%s/state", relayPin)
    mqtt_pub(topic, gpio.read(relayPin) == 1 and 'ON' or 'OFF', 0, 1)
end

local function pin_states()
    local pin = {}
    for i,relayPin in ipairs(config.relayPins) do
        pin[i] = gpio.read(relayPin)
    end
    return(string.format('Switch States: %s', table.concat(pin, ' ')))
end

local function mqtt_sub(topics)
    if(type(topics) == 'table') then
        m:subscribe(topics,function()
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
    if state == 1 then
        power = "ON"
        if not tmr.state(3) then tmr.alarm(3, 60000, tmr.ALARM_SINGLE, function() switch(relayPin,0) end) end
        print("Enabling Output")
    end
    if state == 0 then
        local power = "OFF"
        print("Disabling Output")
    end
    mqtt_update(relayPin, state)
end

-- On publish message receive event
m:on("message", function(client, topic, data)
    print(string.format("Received: %s: %s", topic , data))
    local pin,rest = string.match(topic,"switch/(%d+)(.*)")
    if rest and #rest > 0 and init_state_sub[pin] == 1 then return end
    local relayPin = tonumber(pin)
    if data == "ON" and valid_pin(relayPin) then
        switch(relayPin, gpio.HIGH)
    elseif data == "OFF" and valid_pin(relayPin) then
        switch(relayPin, gpio.LOW)
    end
    if rest and #rest > 0 then
       mqtt_unsub(topic)
       init_state_sub[pin] = 1
    end
    if data == 'EnableTelnet' and topic == string.format("home/%s/telnet", deviceID) then
        telnet.setupTelnetServer()
    end
    if topic == string.format("home/%s/uptime", deviceID) then tmr.softwd(120) end
    print(pin_states())
end)

local function motionDetect()
    gpio.mode(pirPin, gpio.INT)
    gpio.trig(pirPin, "both", function()
        pirState = gpio.read(pirPin)
        mqtt_pub("motion", pirState , 0, 0)
        if pirState == 1 then 
            switch(4,1)
            if tmr.state(3) then tmr.stop(3) end
        else
            tmr.alarm(3, 60000, tmr.ALARM_SINGLE, function() switch(relayPin,0) end)
        end
    end)
end

function _M.mqtt_connect()
    if mqtt_connected == 1 then 
        print("MQTT already initialized")
        return
    end
    m:connect(mqttBroker, 1883, 0, function()
        mqtt_connected = 1
        print("MQTT connected to:" .. mqttBroker)
        local init_topic = {}
        for i,relayPin in ipairs(config.relayPins) do
            init_topic[string.format("home/%s/switch/%s/state", deviceID, relayPin)] = 0
        end
        init_topic[string.format("home/%s/switch/+",deviceID)] = 0
        init_topic[string.format("home/%s/telnet",deviceID)] = 0
        init_topic[string.format("home/%s/uptime",deviceID)] = 0
        mqtt_sub(init_topic)
        tmr.alarm(4, 60000, tmr.ALARM_AUTO, function() mqtt_pub('uptime', tmr.time(), 0, 0) end)
        motionDetect()
    end,
    function()
        print("Can not connect, restarting in 5 seconds...")
        tmr.alarm(1, 5000, tmr.ALARM_SINGLE, function() node.restart() end)
    end)
end

m:on("offline", function(client)
    mqtt_connected = 0
    print("MQTT offline, reconnecting...")
    tmr.alarm(1,1000, tmr.ALARM_SINGLE, function() _M.mqtt_connect() end)
end)

return _M
