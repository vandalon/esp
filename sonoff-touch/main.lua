local _M={} 
local config = require('config')
local telnet = require('telnet_srv')
local mqttBroker = "192.168.0.15"
local init_state_sub = {}
local deviceID = config.deviceID
local relayPin = 6
local wifiLed = 7
local button = 3
local touch = nil
local lastTouch = nil

local m = mqtt.Client(string.gsub(wifi.sta.getmac(),':',''), 60)
m:on("offline", function(client)
    print("MQTT offline, restarting in 10 seconds.")
    gpio.write(wifiLed, gpio.HIGH)
    local restartTimer = tmr.create()
    tmr.alarm(restartTimer, 10000, 0, function()
        node.restart();
    end)
end)
 
local function mqtt_pub(item, value, qos, retain)
    m:publish(string.format("home/%s/%s", deviceID, item), value, qos, retain)
end

local function mqtt_update(relayPin,state)
    local topic = string.format("switch/%s/state", relayPin)
    mqtt_pub(topic, gpio.read(relayPin) == 1 and 'OFF' or 'ON', 0, 1)
end

local function pin_states()
    local state = gpio.read(relayPin)
    return(string.format('Switch States %s', state))
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

-- On publish message receive event
local blinkingLed = tmr.create()
m:on("message", function(client, topic, data)
    print(string.format("Received: %s: %s", topic , data))
    if topic == string.format("home/%s/switch", deviceID) then
       if data == 'ON' then gpio.write(relayPin, gpio.HIGH)
       else gpio.write(relayPin, gpio.LOW) end
    end
    if topic == "home/badkamer/switch/7/state"  then
        if data == "ON" then
            tmr.alarm(blinkingLed, 250, tmr.ALARM_AUTO, function()
                if gpio.read(wifiLed) == gpio.LOW then gpio.write(wifiLed, gpio.HIGH)
                else gpio.write(wifiLed, gpio.LOW) end
            end)
        else
            tmr.stop(blinkingLed)
            gpio.write(wifiLed, gpio.LOW)
        end
    end
    if data == 'EnableTelnet' and topic == string.format("home/%s/telnet", deviceID) then
        telnet.setupTelnetServer()
    end
    if topic == string.format("home/%s/uptime", deviceID) then tmr.softwd(120) end
end)

local shortTouchTimeout = tmr.create()
local longTouchTimeout = tmr.create()
local buttonResetTimeout = tmr.create()
local function buttonReset()
    tmr.alarm(buttonResetTimeout, 500, 0, function()
        mqtt_pub('state', 'none', 0, 0)
    end)
end

local function buttonDetect()
    gpio.mode(button, gpio.INT)
    gpio.trig(button, "both", function()
        if gpio.read(button) == 0 then 
            gpio.write(wifiLed, gpio.HIGH)
            gpio.write(relayPin, gpio.HIGH)
            touch = 'short'
            local touchDelta = 0
            if lastTouch and tmr.now() < 300000 then touchDelta = tmr.now() - lastTouch + 2147483648
            elseif lastTouch then touchDelta = tmr.now() - lastTouch end
            if touchDelta > 150000 and touchDelta < 300000 then
                touch = 'double'
                mqtt_pub('state', touch , 0, 0)
		buttonReset()
            else
                tmr.alarm(longTouchTimeout, 1000, 0, function()
                    touch = 'long'
                    mqtt_pub('state', touch , 0, 0)
                    gpio.write(relayPin, gpio.LOW)
                    gpio.write(wifiLed, gpio.LOW)
		    buttonReset()
                end)
            end
            lastTouch = tmr.now()
        end
        if gpio.read(button) == 1 then
            tmr.alarm(shortTouchTimeout, 300, 0, function() 
                if touch == 'short' then
                    mqtt_pub('state', touch , 0, 0)
		    buttonReset()
                end
            end)
            tmr.stop(longTouchTimeout)
            gpio.write(wifiLed, gpio.LOW)
            gpio.write(relayPin, gpio.LOW)
        end
    end)
end 

function _M.mqtt_connect()
    m:connect(mqttBroker, 1883, 0, function()
        gpio.write(wifiLed, gpio.LOW)
        print("MQTT connected to: " .. mqttBroker)
        local init_topic = {}
        init_topic[string.format("home/%s/switch",deviceID)] = 0
        init_topic["home/badkamer/switch/7/state"] = 0
        init_topic[string.format("home/%s/telnet",deviceID)] = 0
        init_topic[string.format("home/%s/uptime",deviceID)] = 0
        mqtt_sub(init_topic)
        local uptimeTimer = tmr.create()
        tmr.alarm(uptimeTimer, 60000, tmr.ALARM_AUTO, function() mqtt_pub('uptime', tmr.time(), 0, 0) end)
        buttonDetect()
    end,
    function()
        print("Can not connect, restarting in 10 seconds...")
        local restartTimer = tmr.create()
        tmr.alarm(restartTimer, 10000, 0, function() node.restart() end)
    end)
end

return _M
