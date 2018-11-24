--- 模块功能：串口功能测试(非TASK版，串口帧有自定义的结构)
-- @author openLuat
-- @module uart.testUart
-- @license MIT
-- @copyright openLuat
-- @release 2018.03.27

module(...,package.seeall)

require"utils"
require"pm"
require "testHttp"
require"pins"
--[[
功能定义：
uart按照帧结构接收外围设备的输入，收到正确的指令后，回复ASCII字符串

帧结构如下：
帧头：1字节，0x01表示扫描指令，0x02表示控制GPIO命令，0x03表示控制端口命令
帧体：字节不固定，跟帧头有关
帧尾：1字节，固定为0xC0

收到的指令帧头为0x01时，回复"CMD_SCANNER\r\n"给外围设备；例如接收到0x01 0xC0两个字节，就回复"CMD_SCANNER\r\n"
收到的指令帧头为0x02时，回复"CMD_GPIO\r\n"给外围设备；例如接收到0x02 0xC0两个字节，就回复"CMD_GPIO\r\n"
收到的指令帧头为0x03时，回复"CMD_PORT\r\n"给外围设备；例如接收到0x03 0xC0两个字节，就回复"CMD_PORT\r\n"
收到的指令帧头为其余数据时，回复"CMD_ERROR\r\n"给外围设备；例如接收到0x04 0xC0两个字节，就回复"CMD_ERROR\r\n"
]]


--串口ID,1对应uart1
--如果要修改为uart2，把UART_ID赋值为2即可
local UART_ID = 1
--帧头类型以及帧尾
local CMD_QUITY,CMD_STATUS = 4,0x0c
--串口读到的数据缓冲区
local rdbuf = ""

local setGpio29Fnc = pins.setup(pio.P0_29,0)
--local setGpio33Fnc = pins.setup(pio.P0_33,0)


--[[
函数名：parse
功能  ：按照帧结构解析处理一条完整的帧数据
参数  ：
        data：所有未处理的数据
返回值：第一个返回值是一条完整帧报文的处理结果，第二个返回值是未处理的数据
]]
local function parse(data)
	local FrameCtx = {}
	local Temp,i=0,1
    if not data then return end       
    local Head = string.find(data,string.char(0xAA))			--识别数据帧头	
    if not Head then return false,"" end						--如果没有数据头，清空缓冲区
    local cmdtyp = string.byte(data,2)							--命令类型
	--log.info("cmdtyp",cmdtyp,type(cmdtyp))	
	if cmdtyp > string.len(data) then return false,data end 	--字符串长度不全，字符串无处理返回
	
	if cmdtyp == CMD_QUITY then	--查询
        
		local body = string.sub(data,1,4)						--取本帧的所有数据
		while i<=4 do											--分解数据
			FrameCtx[i] = string.byte(data,i)
			i = i + 1
		end
		Temp = (FrameCtx[1] + FrameCtx[2] + FrameCtx[3])%256	--计算校验
		log.info("uart1task",body:toHex(" "),cmdtyp)			--打印本帧的数据
		if Temp == FrameCtx[4] then								--校验正确
			if FrameCtx[3] == 0xa2 then	
				--if mqttTask.GprsNetRdy == true then				--MQTT连接上云服务器
					uart.write(UART_ID,0xaa,0x04,0xb5,0x63)
				--else
				--	uart.write(UART_ID,0xaa,0x04,0xb4,0x62)
				--end
			end
			
		else
			log.info("uart1task","Sum Check is wrong!\r\n");
		end
		return true,string.sub(data,Head+4,-1) 
		
    elseif cmdtyp == CMD_STATUS then							--收到MCU的状态信息
		local body = string.sub(data,1,12)						--取本帧的所有数据
		log.info("uart1task",body:toHex(" "),cmdtyp)			--打印本帧的数据
		while i<=12 do											--分解数据
			FrameCtx[i] = string.byte(data,i)
			if i > 2 and i <= 11 then							--计算校验
				Temp = Temp + FrameCtx[i]
			end
			i = i + 1
		end
		--log.info("sum is",Temp%256)
		if (Temp%256) == FrameCtx[12] then						--校验正确
			--复杂了^~^
			--mqttOutMsg:FilterRst()--滤网复位发送
			write("CMD_STATUS")
		else
			log.info("uart1task","Sum Check is wrong!\r\n");
		end			
		return true,string.sub(data,Head+12,-1) --返回本帧后续的数据返回
    else
        write("CMD_ERROR")		
		return true,""   
	end    
end

--[[
函数名：proc
功能  ：处理从串口读到的数据
参数  ：
        data：当前一次从串口读到的数据
返回值：无
]]
local function proc(data)
    if not data or string.len(data) == 0 then return end
    --追加到缓冲区
    rdbuf = rdbuf..data    
    
    local result,unproc
    unproc = rdbuf
    --根据帧结构循环解析未处理过的数据
    while true do
        result,unproc = parse(unproc)
        if not unproc or unproc == "" or not result then
            break
        end
    end

    rdbuf = unproc or ""
end

--[[
函数名：read
功能  ：读取串口接收到的数据
参数  ：无
返回值：无
]]
local function read()
    local data = ""
    --底层core中，串口收到数据时：
    --如果接收缓冲区为空，则会以中断方式通知Lua脚本收到了新数据；
    --如果接收缓冲器不为空，则不会通知Lua脚本
    --所以Lua脚本中收到中断读串口数据时，每次都要把接收缓冲区中的数据全部读出，这样才能保证底层core中的新数据中断上来，此read函数中的while语句中就保证了这一点
    while true do        
        data = uart.read(UART_ID,"*l",0) --
        if not data or string.len(data) == 0 then break end
        --打开下面的打印会耗时
        --log.info("Uart.read hex",data:toHex(" "))--打印收到的数据，并且以间加空格的形式打印出来,数据包长此处会断
        proc(data)
    end
end

--[[
函数名：write
功能  ：通过串口发送数据
参数  ：
        s：要发送的数据
返回值：无
]]
local level = 0
function write(s)
    log.info("Uart.write",s)
    level = level==0 and 1 or 0
    setGpio29Fnc(level)
	--setGpio33Fnc(level)
    log.info("testGpioSingle.setGpio29Fnc",level)
    log.info("testGpioSingle.setGpio33Fnc",level)
    uart.write(UART_ID,s.."\r\n")
end

local function writeOk()
    log.info("Uart.writeOk")
end

function SendCmd(s)
	local i=1
	local OpendCmd = {0xf1,0xf1,0x01,0x02,0,0,0,0x7e};
	--local test1 = string.match(s,"p:on t:(%d+)")--取出只有数值部分数据
	--log.info("test1",test1)
	local opentime = tonumber(s);			--将字符串转换成数值，这个函数找了好久才找到,tonumber太爽了
	--log.info("opentime",type(opentime),opentime)
	OpendCmd[5] = opentime/256	--索引从1开始的程序
	OpendCmd[6] = opentime%256
	OpendCmd[7] = (OpendCmd[3]+OpendCmd[4] + OpendCmd[5] + OpendCmd[6])%256--一定要取余，不能像C语言一样可以8位自动取低位
	while true do
		uart.write(UART_ID,OpendCmd[i])	--输出到串口
		i = i+1;
		if i>8 then
		break
		end
	end
end

--保持系统处于唤醒状态，此处只是为了测试需要，所以此模块没有地方调用pm.sleep("testUart")休眠，不会进入低功耗休眠状态
--在开发“要求功耗低”的项目时，一定要想办法保证pm.wake("testUart")后，在不需要串口时调用pm.sleep("testUart")
pm.wake("Uart")
--注册串口的数据接收函数，串口收到数据后，会以中断方式，调用read接口读取数据
uart.on(UART_ID,"receive",read)
--注册串口的数据发送通知函数
uart.on(UART_ID,"sent",writeOk)
--配置并且打开串口
uart.setup(UART_ID,9600,8,uart.PAR_NONE,uart.STOP_1)
--如果需要打开“串口发送数据完成后，通过异步消息通知”的功能，则使用下面的这行setup，注释掉上面的一行setup
--uart.setup(UART_ID,115200,8,uart.PAR_NONE,uart.STOP_1,nil,1)
