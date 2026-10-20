-- 项目根目录运行；白名单组件禁止移动、丢弃或改动左右亲本。
local collector = assert(loadfile("oc/lib/crop_collect.lua"))()
local preview = assert(loadfile("oc/lib/crop_preview.lua"))()
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local id = "gregtech:Brown Mushrooms"
local catalog = preview.catalog({ { species_id = id, owner = "gregtech", name = "Brown Mushrooms", tier = 1,
    stats = { 0, 2, 0, 0, 2 }, attributes = { "Food", "Mushroom" }, max_size = 3 } })
local function seed(count, growth)
    return { name = "ic2:itemcropseed", size = count or 1, damage = 143,
        crop = { name = "Brown Mushrooms", growth = growth or 5, gain = 6, resistance = 1 } }
end
local function fixture(mode)
    local internal = { [1] = { name = "IC2:itemCrop", size = 64 },
        [15] = { name = "gregtech:tool", size = 1 }, [16] = { name = "IC2:weedEx", size = 1 } }
    local top = { [1] = seed() }
    local hand = { name = "original:tool", size = 1 }
    local selected, swings, transfers, scans = 1, 0, 0, 0
    local center = { species_id = id, growth = 5, gain = 6, resistance = 1, size = 3, x = 1, y = 64, z = 2 }
    local parent = { species_id = "IC2:wheat", growth = 5, gain = 5, resistance = 1 }
    local report = { center = center, left = copy(parent), right = copy(parent), dimension = 0,
        ready_for_collection = true, collection = { status = "pass", detail = "reviewed_pick_with_random_seed_drops" },
        checks = {
            { name = "parents_match", status = "pass" }, { name = "extra_neighbor_3", status = "pass" },
            { name = "extra_neighbor_4", status = "pass" }, { name = "candidate_weight", status = "pass" },
            { name = "center_crop_sticks", status = "pass" },
        } }
    if mode == "immature" then report.ready_for_collection = false; report.collection.status = "blocked" end
    if mode == "unknown" then report.ready_for_collection = false; report.collection.status = "unknown" end
    if mode == "full" then for slot = 2, 5 do top[slot] = seed() end end
    if mode == "old_seed" then internal[3] = seed() end
    local records = {}
    local journal = {
        load = function() return copy(records[#records]) end,
        save = function(state)
            if mode == "disk_full" and state.phase == "prepare" then error("disk full") end
            records[#records + 1] = copy(state)
        end,
    }
    local function forbidden(_, key) error("禁止的机器人或物品操作: " .. key) end
    local api = { up = 1, address = "robot-1", wait = function() end }
    api.robot = setmetatable({
        inventorySize = function() return 16 end,
        select = function(slot) selected = slot; return true end,
        swing = function()
            assert(hand == nil and selected == 3, "只能空手取种，从3号槽收集")
            swings = swings + 1
            assert(swings == 1, "不能重试拔除")
            center.species_id, center.growth, center.gain, center.resistance = nil, nil, nil, nil
            report.ready_for_collection, report.collection.status = false, "blocked"
            if mode ~= "zero" then
                internal[3] = seed()
                if mode == "wrong_seed" then internal[3].crop.name = "Other" end
                if mode == "wrong_stats" then internal[3].crop.growth = 9 end
                if mode ~= "one" then internal[4] = seed() end
            end
            internal[5] = { name = "minecraft:brown_mushroom", size = 2 }
            if mode == "swing_error" then error("interrupted after click") end
            return true, "block"
        end,
    }, { __index = forbidden })
    api.controller = setmetatable({
        getInventorySize = function(side) assert(side == 1); return 5 end,
        getStackInInternalSlot = function(slot) return copy(internal[slot]) end,
        getStackInSlot = function(side, slot) assert(side == 1); return copy(top[slot]) end,
        equip = function()
            assert(selected == 2)
            hand, internal[2] = internal[2], hand
            return true
        end,
        dropIntoSlot = function(side, destination, amount)
            assert(side == 1 and amount == 1 and not top[destination], "只向上方空槽定点存1份")
            transfers = transfers + 1
            if mode == "blocked_drop" then return false end
            local source = internal[selected]
            top[destination] = copy(source)
            top[destination].size = 1
            source.size = source.size - 1
            if source.size == 0 then internal[selected] = nil end
            if mode == "wrong_destination" then top[destination].crop.growth = 10 end
            if mode == "crash_transfer" then error("interrupted after transfer") end
            return mode ~= "false_return"
        end,
    }, { __index = forbidden })
    api.observe = function()
        scans = scans + 1
        local current = copy(report)
        if mode == "changed" and scans == 2 then current.center.growth = 7 end
        if mode == "moved" and scans == 3 then current.center.x = 100 end
        return current
    end
    return api, journal, function() return swings, transfers, internal, top, hand, records end
end

for _, mode in ipairs({ "normal", "one", "false_return", "crash_transfer" }) do
    local api, journal, result = fixture(mode)
    local state = collector.run(api, preview, catalog, id, journal)
    local swings, transfers, internal, top, hand = result()
    local wanted = mode == "one" and 1 or 2
    assert(state.phase == "done" and state.stored == wanted and #state.receipts == wanted)
    assert(swings == 1 and transfers == wanted and hand.name == "original:tool")
    assert(internal[1].size == 64 and internal[15].name == "gregtech:tool" and internal[16].size == 1)
    assert(internal[5].name == "minecraft:brown_mushroom", "副产物必须保留")
    assert(top[1].size == 1 and top[2].crop.growth == 5, "原有种子不能计为本批次成功")
end
for _, mode in ipairs({ "immature", "unknown", "full", "old_seed", "disk_full" }) do
    local api, journal, result = fixture(mode)
    assert(not pcall(collector.run, api, preview, catalog, id, journal), mode)
    local swings, transfers, _, _, hand = result()
    assert(swings == 0 and transfers == 0 and hand.name == "original:tool", mode)
end
for _, mode in ipairs({ "changed", "moved", "wrong_seed", "wrong_stats", "blocked_drop", "wrong_destination", "swing_error" }) do
    local api, journal, result = fixture(mode)
    assert(not pcall(collector.run, api, preview, catalog, id, journal), mode)
    local swings, transfers, internal, _, hand, records = result()
    assert(swings <= 1 and hand.name == "original:tool", mode)
    if mode == "changed" then assert(swings == 0) end
    if mode == "blocked_drop" then assert(internal[3] and records[#records].phase == "deposit_pending") end
    assert(not pcall(collector.run, api, preview, catalog, id, journal), "未完成记录必须阻止重复动作")
    local later_swings, later_transfers = result()
    assert(later_swings == swings and later_transfers == transfers)
end
do
    local api, journal, result = fixture("zero")
    local state = collector.run(api, preview, catalog, id, journal)
    local swings, transfers = result()
    assert(state.phase == "no_seed" and not state.stored and swings == 1 and transfers == 0)
end
do
    local api, journal, result = fixture("normal")
    local observed = api.observe()
    observed.center.growth = 9
    assert(not pcall(collector.run, api, preview, catalog, id, journal, observed))
    local swings, transfers = result()
    assert(swings == 0 and transfers == 0, "等待结束与取种开始之间也必须重新确认身份")
end
do
    local reply = { ok = true, protocol = 1, rules_fingerprint = "rules", site = {} }
    local requested_candidate
    local geolyzer = { analyze = function(_, options)
        assert(options.crop_helper == "site" and not options.x)
        requested_candidate = options.candidate
        return { crop_helper = reply }
    end }
    assert(not pcall(collector.observe, geolyzer, 3), "旧服务端不能误报取种就绪")
    local api = fixture("normal")
    reply.site = api.observe()
    assert(collector.observe(geolyzer, 3, "rules").ready_for_collection)
    assert(collector.observe(geolyzer, 3, "rules", id).ready_for_collection and requested_candidate == id,
        "等待空架时必须核对指定候选的条件和正权重")
    assert(not pcall(collector.observe, geolyzer, 3, "other"))
    reply.site.collection.status = "unknown"
    assert(not pcall(collector.observe, geolyzer, 3), "未知不能就绪")
end
-- 命令行入口：相对库路径、实际读写记录流程、status 与损坏记录阻断。
do
    local api, _, result = fixture("normal")
    local lines, serialized, output, errors = {}, {}, {}, {}
    local exists, serial, flush_fails = false, 0, false
    local auto_lines, auto_exists = {}, false
    local original_print, original_open, original_stderr = print, io.open, io.stderr
    local original_getenv, original_sleep = os.getenv, os.sleep
    package.loaded.component = {
        list = function(kind) return function() return kind end end,
        proxy = function(kind)
            if kind == "geolyzer" then return { analyze = function(_, options)
                if options.crop_helper == "site" then
                    return { crop_helper = { ok = true, protocol = 1, rules_fingerprint = "rules", site = api.observe() } }
                end
                assert(options.crop_helper == "catalog")
                return { crop_helper = { ok = true, protocol = 1, rules_fingerprint = "rules",
                    crops = catalog.crops, total = 1 } }
            end } end
            if kind == "inventory_controller" then return api.controller end
            if kind == "robot" then return api.robot end
            error("unknown component")
        end,
    }
    package.loaded.robot, package.loaded.sides = api.robot, { front = 3, up = 1, down = 0 }
    package.loaded.filesystem = {
        path = function(value) return value:match("^(.*)/") end,
        concat = function(a, b) return a .. "/" .. b end,
        exists = function(path) if path == "oc/crop_auto.journal" then return auto_exists end; return exists end,
    }
    package.loaded.serialization = {
        serialize = function(state, pretty)
            assert(pretty == false)
            serial = serial + 1
            local token = "state" .. serial
            serialized[token] = copy(state)
            return token
        end,
        unserialize = function(line) return copy(serialized[line]) end,
    }
    io.open = function(path, mode)
        assert(path == "oc/crop_collect.journal" or path == "oc/crop_auto.journal")
        local automatic = path == "oc/crop_auto.journal"
        local contents = automatic and auto_lines or lines
        local file, offset = {}, 0
        file.close = function() return nil end -- OpenOS 文件系统关闭成功不返回值。
        file.flush = function() if flush_fails then return nil, "disk full" end; return file end
        file.write = function(_, value, newline)
            assert(mode == "a" and newline == "\n")
            if automatic then auto_exists = true else exists = true end
            contents[#contents + 1] = value
            return file
        end
        file.lines = function()
            assert(mode == "r")
            return function() offset = offset + 1; return contents[offset] end
        end
        return file
    end
    os.getenv = function(key) if key == "_" then return "oc/crop_collect.lua" end; return original_getenv(key) end
    os.sleep = function() end
    print = function(line) output[#output + 1] = line end
    io.stderr = { write = function(_, text) errors[#errors + 1] = text end }
    local function cli(...) assert(loadfile("oc/crop_collect.lua"))(...) end
    cli("collect", id)
    assert(#errors == 0 and table.concat(output, "\n"):find("本批次已确认入库:", 1, true))
    output = {}
    cli("status")
    assert(table.concat(output, "\n"):find("上次批次阶段: done", 1, true))
    cli("inspect")
    assert(table.concat(output, "\n"):find("中央作物: 空", 1, true))
    local previous_api = api
    api = fixture("normal")
    package.loaded.robot = api.robot
    lines, errors, output, exists = {}, {}, {}, false
    cli("wait", id, "2")
    assert(#errors == 0 and table.concat(output, "\n"):find("每2秒扫描", 1, true))
    assert(table.concat(output, "\n"):find("本批次已确认入库:", 1, true))
    cli("wait", id, "0")
    assert(table.concat(errors, "\n"):find("扫描间隔须为0.5至60秒", 1, true))
    api = fixture("normal")
    package.loaded.robot = api.robot
    lines, errors, output, exists = {}, {}, {}, false
    cli("auto", id, "1")
    assert(#errors == 0 and table.concat(output, "\n"):find("自动任务完成", 1, true), table.concat(errors, "\n"))
    cli("auto_status")
    assert(table.concat(output, "\n"):find("上次批次阶段: complete", 1, true))
    assert(table.concat(output, "\n"):find("上次确认箱内数量: 1", 1, true))
    cli("auto", id, "0")
    assert(table.concat(errors, "\n"):find("目标数量须为正整数", 1, true))
    api = previous_api
    package.loaded.robot = api.robot
    lines, exists = { "broken" }, true
    cli("collect", id)
    assert(table.concat(errors, "\n"):find("批次记录损坏", 1, true))
    local swings, transfers = result()
    assert(swings == 1 and transfers == 2, "记录损坏时不能重试物品或取种动作")
    lines, errors = {}, {}
    cli("status")
    assert(table.concat(errors, "\n"):find("批次记录为空", 1, true))
    api = fixture("normal")
    package.loaded.robot = api.robot
    lines, errors, exists, flush_fails = {}, {}, false, true
    cli("collect", id)
    assert(table.concat(errors, "\n"):find("批次记录写入失败", 1, true))
    assert(api.observe().center.species_id == id, "显式flush失败时必须停止，不能拔除作物")
    print, io.open, io.stderr = original_print, original_open, original_stderr
    os.getenv, os.sleep = original_getenv, original_sleep
end
print("crop_collect_test: passed (one batch, identity, storage receipts, zero drops, fail-stop journal)")
