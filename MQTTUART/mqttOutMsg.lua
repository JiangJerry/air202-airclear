--- 模块功能：MQTT客户端数据发送处理
-- @author openLuat
-- @module mqtt.mqttOutMsg
-- @license MIT
-- @copyright openLuat
-- @release 2018.03.28
require "uart1Task"
require "uart2Task"

module(...,package.seeall)

--数据发送的消息队列
local msgQuene = {}

local function insertMsg(topic,payload,qos,user)
    table.insert(msgQuene,{t=topic,p=payload,q=qos,user=user})
end

local function PubHeartPerMinCb(result)
    log.info("mqttOutMsg.PubHeartPerMinCb",result,"notify","id:"..misc.getImei().." status:0")--打印心跳信息发送结果
    if result then sys.timerStart(PubHeartPerMin,55000) end	--如果发送正确，重启下一次心跳数据
end

function PubHeartPerMin()
    insertMsg("notify","id:"..misc.getImei().." status:0",1,{cb=PubHeartPerMinCb})--每分钟心跳
end
function FilterRstCb(result)
    log.info("mqttOutMsg.FilterRst",result,"notify","id:"..misc.getImei().." reset:1")--打印心跳信息发送结果
end
function FilterRst()
	insertMsg("notify","id:"..misc.getImei().." reset:1",1,{cb=FilterRstCb})
end	
	
--- 初始化“MQTT客户端数据发送”
-- @return 无
-- @usage mqttOutMsg.init()
function init()
    PubHeartPerMin()
end

--- 去初始化“MQTT客户端数据发送”
-- @return 无
-- @usage mqttOutMsg.unInit()
function unInit()
    sys.timerStop(PubHeartPerMin)
    while #msgQuene>0 do
        local outMsg = table.remove(msgQuene,1)
        if outMsg.user and outMsg.user.cb then outMsg.user.cb(false,outMsg.user.para) end
    end
end

--- MQTT客户端是否有数据等待发送
-- @return 有数据等待发送返回true，否则返回false
-- @usage mqttOutMsg.waitForSend()
function waitForSend()
    return #msgQuene > 0
end

--- MQTT客户端数据发送处理
-- @param mqttClient，MQTT客户端对象
-- @return 处理成功返回true，处理出错返回false
-- @usage mqttOutMsg.proc(mqttClient)
function proc(mqttClient)
    while #msgQuene>0 do
        local outMsg = table.remove(msgQuene,1)
        local result = mqttClient:publish(outMsg.t,outMsg.p,outMsg.q)
        if outMsg.user and outMsg.user.cb then outMsg.user.cb(result,outMsg.user.para) end
        if not result then return end
    end
    return true
end
