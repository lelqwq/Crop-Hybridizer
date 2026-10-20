-- 原工位单次拔除取种：动作前写记录，只处理本批次，失败不自动重放。
local collect = {}

local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

local function read(reader, ...)
    local value, reason = reader(...)
    assert(not reason, "物品读取失败: " .. tostring(reason))
    return value
end

local function is_seed(stack)
    return stack and type(stack.name) == "string" and stack.name:lower() == "ic2:itemcropseed"
end

local function same_stack(a, b)
    if not a or not b then return a == b end
    for _, key in ipairs({ "name", "size", "damage", "label", "hasTag" }) do
        if a[key] ~= b[key] then return false end
    end
    if not a.crop or not b.crop then return a.crop == b.crop end
    for _, key in ipairs({ "name", "tier", "growth", "gain", "resistance" }) do
        if a.crop[key] ~= b.crop[key] then return false end
    end
    return true
end

local function same_crop(a, b)
    if not a or not b then return false end
    for _, key in ipairs({ "species_id", "growth", "gain", "resistance" }) do
        if a[key] ~= b[key] then return false end
    end
    return true
end

local function same_position(a, b)
    return a.dimension == b.dimension and a.center.x == b.center.x
        and a.center.y == b.center.y and a.center.z == b.center.z
end

function collect.observe(geolyzer, front, fingerprint, candidate)
    local scan, reason = geolyzer.analyze(front, { crop_helper = "site", protocol = 1, candidate = candidate })
    assert(type(scan) == "table", "扫描失败: " .. tostring(reason))
    local reply = scan.crop_helper
    assert(type(reply) == "table" and reply.ok, "工位查询失败: " .. tostring(reply and reply.error))
    assert(reply.protocol == 1 and type(reply.rules_fingerprint) == "string", "工位协议或规则指纹无效")
    assert(not fingerprint or reply.rules_fingerprint == fingerprint, "规则已变化，请重新运行")
    local report = reply.site
    assert(type(report) == "table" and type(report.collection) == "table",
        "取种检查需要服务器 crop_helper 0.3.0")
    assert(type(report.center) == "table" and type(report.left) == "table" and type(report.right) == "table",
        "工位观察不完整")
    assert(({ pass = true, blocked = true, unknown = true })[report.collection.status], "取种状态无效")
    assert(report.ready_for_collection == (report.collection.status == "pass"), "取种状态不一致")
    assert(integer(report.dimension, -2147483648, 2147483647), "缺少维度信息")
    for _, key in ipairs({ "x", "y", "z" }) do
        assert(integer(report.center[key], -2147483648, 2147483647), "缺少工位坐标")
    end
    return report
end

function collect.show(report, write)
    local crop = report.center
    write("中央作物: " .. tostring(crop.species_id or "空"))
    if crop.species_id then
        write(string.format("阶段=%s Gr=%s Ga=%s Re=%s", tostring(crop.size),
            tostring(crop.growth), tostring(crop.gain), tostring(crop.resistance)))
    end
    local check = report.collection
    write("单次取种条件: " .. ({ pass = "通过", blocked = "未通过", unknown = "未知" })[check.status])
    local reasons = {
        no_center_crop = "中央尚无作物，等待杂交结果",
        not_harvestable_yet = "尚未达到该作物的收获阶段",
        vanilla_wheat_seeds_only = "该小麦三围只会产生普通小麦种子",
        reviewed_pick_with_random_seed_drops = "可尝试拔除取种，种子掉落仍有随机性",
    }
    write(reasons[check.detail] or ("原因: " .. tostring(check.detail)))
end

local function check_storage(api)
    local count = api.robot.inventorySize()
    assert(integer(count, 16, 1000), "需要至少16格机器人背包")
    local internal = {}
    for slot = 1, count do
        internal[slot] = read(api.controller.getStackInInternalSlot, slot)
        assert(not is_seed(internal[slot]), "背包已有种子，请先保存，避免混入本批次")
        if slot ~= 1 and slot ~= 15 and slot ~= 16 then
            assert(not internal[slot], "请先腾空背包非功能槽位: " .. slot)
        end
    end
    local top_size = api.controller.getInventorySize(api.up)
    assert(integer(top_size, 2, 100000), "上方需要可读取的种子容器")
    local top, empty = {}, {}
    for slot = 1, top_size do
        top[slot] = read(api.controller.getStackInSlot, api.up, slot)
        if not top[slot] then empty[#empty + 1] = slot end
    end
    assert(#empty >= 2, "上方容器至少需要2个空槽，当前未拔除作物")
    return count, top_size, top, empty
end

function collect.run(api, preview, catalog, expected, journal, observed, options)
    options = options or {}
    assert(catalog.by_id[expected], "未知目标品种 ID")
    local previous = journal.load()
    assert(not previous or previous.phase == "done" or previous.phase == "no_seed",
        "有未完成批次；请查看 status 并人工核对现场、手持物、背包和箱子，不能重复拔除")
    local before = api.observe()
    assert(options.clear or (before.ready_for_collection and before.collection.status == "pass"),
        "中央作物尚未通过取种检查")
    if observed then
        assert(same_position(observed, before) and same_crop(observed.center, before.center)
            and same_crop(observed.left, before.left) and same_crop(observed.right, before.right),
            "等待结束后工位或作物已变化，停止拔除")
    end
    assert(before.center.species_id == expected, "中央品种与指定品种不同，保留现场")
    for _, key in ipairs({ "growth", "gain", "resistance" }) do
        assert(integer(before.center[key], 0, 31), "中央作物三围无效")
    end
    local count, top_size, top, empty = check_storage(api)
    local state = { version = 1, phase = "prepare", crop = before.center, dimension = before.dimension,
        receipts = {}, robot_address = api.address, action = options.clear and "clear" or "collect" }
    journal.save(state)

    -- 用空2号槽暂存原手持物，空手左击；收获完成后恢复，不依赖15号槽的工具类型。
    assert(api.robot.select(2), "选择暂存槽失败")
    assert(api.controller.equip(), "暂存手持物失败，请人工检查装备")
    local parked = read(api.controller.getStackInInternalSlot, 2)
    state.phase, state.parked = "equipped", parked
    local swung, swing_result, swing_reason
    local action_ok, action_error = pcall(function()
        journal.save(state)
        local current = api.observe()
        assert(same_position(before, current) and same_crop(before.center, current.center)
            and (options.clear or current.ready_for_collection),
            "中央作物或位置已变化，停止拔除")
        assert(same_crop(before.left, current.left) and same_crop(before.right, current.right), "亲本已变化，停止拔除")
        assert(api.robot.select(3), "选择掉落起始槽失败")
        state.phase = "swing_pending"
        journal.save(state)
        swung = true
        swing_result, swing_reason = api.robot.swing()
    end)
    assert(same_stack(parked, read(api.controller.getStackInInternalSlot, 2)),
        "装备暂存槽发生变化，请人工恢复手持物")
    assert(api.robot.select(2) and api.controller.equip(), "恢复手持物失败，请人工检查装备")
    assert(not read(api.controller.getStackInInternalSlot, 2), "装备恢复结果异常")
    assert(action_ok, tostring(action_error))
    state.phase, state.parked = "collected", nil
    state.swing_result, state.swing_reason = swing_result, swing_reason
    journal.save(state)
    assert(swung, "尚未执行拔除")
    api.wait()
    local after = api.observe()
    assert(same_position(before, after), "收获后位置改变，停止入库")
    assert(not after.center.species_id, "中央仍有作物，停止且不重试拔除")
    assert(same_crop(before.left, after.left) and same_crop(before.right, after.right), "亲本发生变化，停止入库")

    -- shortcut: 依赖工位独占且地面无旧掉落；多机器人共用时需增加掉落隔离。
    local stock = preview.inventory(catalog, {
        getInventorySize = function() return count end,
        getStackInSlot = function(_, slot) return read(api.controller.getStackInInternalSlot, slot) end,
    }, api.up)
    assert(#stock.unknown == 0, "本批次含未识别种子，全部保留背包中，请完整分析后人工保存")
    local function identify(stack)
        local result = preview.inventory(catalog, {
            getInventorySize = function() return 1 end,
            getStackInSlot = function() return stack end,
        }, api.up)
        return result.batches[1]
    end
    local seeds = 0
    for _, batch in ipairs(stock.batches) do
        assert(same_crop(batch, before.center), "种子身份或三围与本株不符，保留背包中的全部物品")
        seeds = seeds + batch.count
    end
    assert(seeds <= 2, "本批次种子超过已审核掉落上限，请人工核对来源")
    state.seeds = stock.batches
    if seeds == 0 then
        state.phase = "no_seed"
        journal.save(state)
        return state
    end

    local receipt_index = 0
    for _, batch in ipairs(stock.batches) do
        for item = 1, batch.count do
            receipt_index = receipt_index + 1
            local destination = empty[receipt_index]
            assert(not read(api.controller.getStackInSlot, api.up, destination), "预留入库槽被占用，停止")
            local source = read(api.controller.getStackInInternalSlot, batch.slot)
            local source_batch = identify(source)
            assert(source_batch and source_batch.count == batch.count - item + 1
                and same_crop(source_batch, before.center), "源种子槽已变化")
            local source_count = source.size
            assert(api.robot.select(batch.slot), "选择种子槽失败")
            state.phase, state.pending = "deposit_pending", { source = batch.slot, destination = destination,
                count_before = source_count, species_id = batch.species_id }
            journal.save(state)
            -- 不信任返回值；每次只转移1份并核对源槽减少与目标槽增加。
            local ok, reason = pcall(api.controller.dropIntoSlot, api.up, destination, 1)
            local remaining = read(api.controller.getStackInInternalSlot, batch.slot)
            local stored = read(api.controller.getStackInSlot, api.up, destination)
            local received = identify(stored)
            local remaining_batch = remaining and identify(remaining)
            assert((remaining and remaining.size or 0) == source_count - 1
                and (not remaining or (remaining_batch and same_crop(remaining_batch, before.center)))
                and received and received.count == 1 and same_crop(received, before.center),
                "入库未确认，保留记录和剩余物品: " .. tostring(ok and "数量或身份不符" or reason))
            state.receipts[#state.receipts + 1] = { source = batch.slot, destination = destination, count = 1 }
            state.phase, state.pending = "deposit_verified", nil
            journal.save(state)
        end
    end
    for slot = 1, top_size do
        local current = read(api.controller.getStackInSlot, api.up, slot)
        local receipt
        for _, entry in ipairs(state.receipts) do if entry.destination == slot then receipt = entry end end
        if receipt then
            assert(is_seed(current) and current.size == 1 and current.crop
                and current.crop.name == catalog.by_id[expected].name
                and current.crop.growth == before.center.growth and current.crop.gain == before.center.gain
                and current.crop.resistance == before.center.resistance, "已入库种子发生变化，停止确认")
        else
            assert(same_stack(top[slot], current), "上方容器被其他程序改变，停止确认")
        end
    end
    state.phase, state.stored = "done", seeds
    journal.save(state)
    return state
end

function collect.wait_for_target(api, preview, catalog, expected, journal, interval, write)
    assert(catalog.by_id[expected], "未知目标品种 ID")
    assert(type(interval) == "number" and interval >= 0.5 and interval <= 60, "扫描间隔须为0.5至60秒")
    local previous = journal.load()
    assert(not previous or previous.phase == "done" or previous.phase == "no_seed",
        "有未完成批次，请先查看 status 并人工核对，不能自动重试")
    check_storage(api)
    local origin, target, last_message
    while true do
        local report = api.observe()
        origin = origin or report
        assert(same_position(origin, report) and same_crop(origin.left, report.left)
            and same_crop(origin.right, report.right), "等待中工位位置或亲本已变化，已停止")
        if target then
            assert(same_crop(target, report.center), "等待中的目标作物已变化或消失，已停止")
        end
        local crop, check = report.center, report.collection
        local message = tostring(crop.species_id) .. ":" .. tostring(crop.size) .. ":"
            .. tostring(check.status) .. ":" .. tostring(check.detail)
        if message ~= last_message then collect.show(report, write); last_message = message end
        if crop.species_id then
            assert(crop.species_id == expected, "中央出现其他品种: " .. crop.species_id .. "；已保留，请人工处理后重启等待")
            target = target or crop
            if report.ready_for_collection and check.status == "pass" then
                return collect.run(api, preview, catalog, expected, journal, report)
            end
            assert(check.status == "blocked" and check.detail == "not_harvestable_yet",
                "目标作物取种条件未知或不受支持，已保留现场")
        else
            assert(report.status == "pass" and report.ready_for_crossing,
                "空中央工位的杂交条件未全部通过，请先运行 crop_plan.lua check 核对")
        end
        api.sleep(interval)
    end
end

-- 自动循环复用相同的身份和物品核对规则。
collect.same_stack, collect.same_crop, collect.same_position = same_stack, same_crop, same_position
collect.check_storage = check_storage

return collect
