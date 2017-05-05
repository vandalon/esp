-- Timers
-- 0 = Free
-- 1 = Online Check
-- 2 = Free
-- 3 = Free
-- 4 = Free
-- 5 = Telnet Idle Timeout
-- 6 = Telnet Server Timeout

local _M={} 
local config = require('config')
local telnet = require('telnet_srv')
local mqttBroker = "192.168.1.12"
local init_state_sub = {}
local deviceID = config.deviceID

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
    mqtt_pub(topic, gpio.read(relayPin) == 1 and 'OFF' or 'ON', 0, 1)
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

-- On publish message receive event
m:on("message", function(client, topic, data)
    print(string.format("Received: %s: %s", topic , data))
    if data == 'EnableTelnet' and topic == string.format("home/%s/telnet", deviceID) then
        telnet.setupTelnetServer()
    end
    if topic == string.format("home/%s/uptime", deviceID) then tmr.softwd(120) end
end)
 
function _M.mqtt_connect()
    m:connect(mqttBroker, 1883, 0, function()
        print("MQTT connected to:" .. mqttBroker)
        local init_topic = {}
        init_topic[string.format("home/%s/telnet",deviceID)] = 0
        init_topic[string.format("home/%s/uptime",deviceID)] = 0
        mqtt_sub(init_topic)
        tmr.alarm(2, 60000, tmr.ALARM_AUTO, function() mqtt_pub('uptime', tmr.time(), 0, 0) end)
    end,
    function()
        print("Can not connect, restarting in 10 seconds...")
        tmr.alarm(1, 10000, 0, function() node.restart() end)
    end)
end

return _M
