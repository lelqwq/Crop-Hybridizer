-- 原布局的观察、单次取种与持续自动杂交；只操作中央位，保留左右亲本。
local component = require("component")
local filesystem = require("filesystem")
local serialization = require("serialization")
local sides = require("sides")
local path = filesystem.path(os.getenv("_") or "oc/crop_collect.lua")
local collector = assert(loadfile(filesystem.concat(path, "lib/crop_collect.lua")))()
local preview = assert(loadfile(filesystem.concat(path, "lib/crop_preview.lua")))()
local state_path = filesystem.concat(path, "crop_collect.journal")

local function make_journal(state_path)
    local journal = {}
    function journal.load()
        if not filesystem.exists(state_path) then return nil end
        local file = assert(io.open(state_path, "r"))
        local latest
        for line in file:lines() do
            local state = serialization.unserialize(line)
            if type(state) ~= "table" or state.version ~= 1 or type(state.phase) ~= "string" then
                file:close()
                error("批次记录损坏，请保留文件并人工核对，不能自动重试")
            end
            latest = state
        end
        local closed, close_reason = file:close()
        assert(closed ~= false and not close_reason, "关闭记录失败: " .. tostring(close_reason))
        assert(latest, "批次记录为空，请人工核对上次动作")
        return latest
    end
    function journal.save(state)
        local line = serialization.serialize(state, false)
        assert(not line:find("\n", 1, true), "批次记录必须为单行")
        local file = assert(io.open(state_path, "a"))
        local ok, reason = file:write(line, "\n")
        -- OpenOS 的 close 不返回成功值，且不会传播 flush 失败，必须显式检查写盘。
        local flushed, flush_reason = file:flush()
        local closed, close_reason = file:close()
        assert(ok and flushed and closed ~= false and not close_reason,
            "批次记录写入失败: " .. tostring(reason or flush_reason or close_reason))
    end
    return journal
end
local journal = make_journal(state_path)
local auto_journal = make_journal(filesystem.concat(path, "crop_auto.journal"))

local function get_component(kind)
    local address = component.list(kind)()
    assert(address, "缺少组件: " .. kind)
    return component.proxy(address), address
end

local function status(automatic)
    local state = (automatic and auto_journal or journal).load()
    if not state then print("尚无单次取种记录"); return end
    print("上次批次阶段: " .. state.phase)
    print("作物: " .. tostring(state.target or (state.crop and state.crop.species_id)))
    if automatic then
        print("目标数量: " .. tostring(state.quantity))
        print("上次确认箱内数量: " .. tostring(state.owned or "尚未读取"))
        print("已处理轮数: " .. tostring(state.rounds))
    else print("已核对入库份数: " .. tostring(#(state.receipts or {}))) end
    if state.pending and state.pending.source and state.pending.destination then
        local direction = state.phase == "recycle_pending" and "背包槽" or "上方箱槽"
        print(string.format("待核对: 背包槽 %d -> %s %d", state.pending.source, direction, state.pending.destination))
    end
    if state.phase ~= "done" and state.phase ~= "no_seed" and state.phase ~= "complete" and state.phase ~= "waiting" then
        print("未完成批次会阻止再次拔除，避免重复动作")
        print("请先人工核对现场、手持物、背包和种子箱")
    end
    print("记录文件: " .. (automatic and filesystem.concat(path, "crop_auto.journal") or state_path))
end

local function main(args)
    local command = args[1] or "inspect"
    if command == "status" then status(); return end
    if command == "auto_status" then status(true); return end
    if command ~= "inspect" and command ~= "collect" and command ~= "wait" and command ~= "auto" then
        print("crop_collect.lua inspect")
        print('crop_collect.lua collect "完整品种ID"')
        print('crop_collect.lua wait "完整品种ID" [扫描间隔秒]')
        print('crop_collect.lua auto "完整品种ID" [箱内数量] [间隔秒]')
        print("crop_collect.lua status")
        print("crop_collect.lua auto_status")
        return
    end
    if command ~= "inspect" then assert(type(args[2]) == "string" and args[2] ~= "", "请指定目标的完整品种ID") end
    local interval_arg = args[3]
    if command == "auto" then interval_arg = args[4] end
    local interval = interval_arg == nil and 5 or tonumber(interval_arg)
    local quantity = command == "auto" and (args[3] == nil and 1 or tonumber(args[3])) or nil
    if command == "auto" then
        assert(quantity and quantity == math.floor(quantity) and quantity >= 1 and quantity <= 1000000, "目标数量须为正整数")
    end
    if command == "wait" or command == "auto" then
        assert(interval and interval >= 0.5 and interval <= 60, "扫描间隔须为0.5至60秒")
    end
    local geolyzer = get_component("geolyzer")
    if command == "inspect" then
        collector.show(collector.observe(geolyzer, sides.front), print)
        return
    end
    local controller = get_component("inventory_controller")
    local _, address = get_component("robot")
    local robot = require("robot")
    local catalog, fingerprint = preview.read_catalog(geolyzer, sides.front, function() os.sleep(0) end)
    if command == "auto" then
        print("持续杂交目标: " .. args[2] .. " x" .. quantity)
        print("非目标作物立即清除，掉落物存入上方箱")
        print("自动补架和补给；Ctrl+C停止")
    elseif command == "wait" then
        print("自动等待: " .. args[2])
        print("每" .. tostring(interval) .. "秒扫描，Ctrl+C停止")
        print("目标可取种后自动收集一株并入库")
    else
        print("执行单次中央拔除取种，保留左右亲本")
    end
    if command ~= "auto" then print("种子可能不掉落；本次只拔除中央一株") end
    local api = { robot = robot, controller = controller, address = address, up = sides.up, down = sides.down,
        fingerprint = fingerprint,
        observe = function() return collector.observe(geolyzer, sides.front, fingerprint,
            (command == "wait" or command == "auto") and args[2] or nil) end,
        wait = function() os.sleep(0.2) end,
        sleep = function(seconds) os.sleep(seconds) end,
    }
    local result
    if command == "auto" then
        local auto = assert(loadfile(filesystem.concat(path, "lib/crop_auto.lua")))()
        auto.run(api, collector, preview, catalog, args[2], quantity, interval, journal, auto_journal, print)
        print("自动任务完成；记录: " .. filesystem.concat(path, "crop_auto.journal"))
        return
    elseif command == "wait" then
        result = collector.wait_for_target(api, preview, catalog, args[2], journal, interval, print)
    else
        result = collector.run(api, preview, catalog, args[2], journal)
    end
    if result.phase == "no_seed" then
        print("本次未检测到 IC2 种子袋，不计为成功")
    else
        print("本批次已确认入库: " .. args[2] .. " x" .. tostring(result.stored))
    end
    print("中央位和背包副产物请检查后再开始下一轮")
    print("批次记录: " .. state_path)
end

local ok, reason = pcall(main, { ... })
if not ok then
    io.stderr:write("作物任务停止: " .. tostring(reason) .. "\n")
    io.stderr:write("请用 status 或 auto_status 查看记录；剩余物品保留原位。\n")
end
