local auto = assert(loadfile("oc/lib/crop_auto.lua"))()
local collector = assert(loadfile("oc/lib/crop_collect.lua"))()
local preview = assert(loadfile("oc/lib/crop_preview.lua"))()
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local target = "gregtech:Brown Mushrooms"
local catalog = preview.catalog({
    { species_id = target, owner = "gregtech", name = "Brown Mushrooms", tier = 1,
        stats = { 0, 2, 0, 0, 2 }, attributes = { "Food" }, max_size = 3 },
    { species_id = "IC2:wheat", owner = "IC2", name = "wheat", tier = 1,
        stats = { 0, 0, 0, 0, 2 }, attributes = { "Food" }, max_size = 7 },
})
local function bag(name)
    return { name = "ic2:itemcropseed", size = 1, crop = { name = name or "Brown Mushrooms", growth = 5, gain = 6, resistance = 1 } }
end
local function fixture(mode)
    local internal = { [15] = { name = "test:pick", size = 1 }, [16] = { name = "IC2:weedEx", size = 1 } }
    local top, lower = {}, { [1] = { name = "IC2:blockCrop", size = 40 } }
    local hand, selected = { name = "test:original_tool", size = 1 }, 1
    local rack, crop, stage = "double", nil, 0
    local swings, places, upgrades, sleeps, supply_calls = 0, 0, 0, 0, 0
    local generation = 0
    local records, batches, output = {}, {}, {}
    if mode == "no_supply" then lower = {} end
    if mode == "full" then for slot = 1, 32 do top[slot] = bag() end end
    if mode == "owned" then top[1], top[2] = bag(), bag() end
    if mode == "missing_rack" then rack = "missing" end
    if mode == "place_fail" or mode == "partial_supply" then rack = "missing" end
    if mode == "partial_supply" then lower[1].size = 1 end
    local function store(records)
        return {
            load = function() return copy(records[#records]) end,
            save = function(state)
                if mode == "disk_full" then error("disk full") end
                records[#records + 1] = copy(state)
            end,
        }
    end
    local journal, batch_journal = store(records), store(batches)
    local api = { address = "robot-1", fingerprint = "rules", up = 1, down = 0, wait = function() end }
    local function check(name, status, detail) return { name = name, status = status, detail = detail } end
    local function forbidden(_, key) error("禁止的操作: " .. key) end
    api.observe = function()
        local center = { x = 1, y = 64, z = 2 }
        if rack ~= "missing" then center.size = stage end
        if crop then
            center.species_id, center.growth, center.gain, center.resistance = crop, 5, 6, 1
        end
        local parent = { species_id = "IC2:wheat", growth = 5, gain = 6, resistance = 1 }
        local ready = crop == target and stage >= 3
        local report = { center = center, left = copy(parent), right = copy(parent), dimension = 0,
            ready_for_collection = ready, collection = { status = ready and "pass" or "blocked",
                detail = crop and (ready and "reviewed_pick_with_random_seed_drops" or "not_harvestable_yet") or "no_center_crop" },
            ready_for_crossing = not crop and rack == "double", status = not crop and rack == "double" and "pass" or "blocked",
            checks = {
                check("parents_match", "pass"), check("extra_neighbor_3", "pass"), check("extra_neighbor_4", "pass"),
                check("candidate_weight", "pass"),
                check("center_crop_sticks", rack == "missing" and "blocked" or "pass", rack == "missing" and "crop_sticks_missing" or "present"),
            } }
        if rack ~= "missing" then report.checks[#report.checks + 1] = check("cross_sticks", rack == "double" and "pass" or "blocked") end
        if mode == "changed_parent" and swings > 0 then report.left.growth = 9 end
        return report
    end
    api.sleep = function(seconds)
        assert(seconds == 5)
        sleeps = sleeps + 1
        assert(sleeps < 30, "循环未取得进展")
        if mode == "cancel" then error("interrupted") end
        if not crop and rack == "double" then
            generation = generation + 1
            crop = generation == 1 and "IC2:wheat" or target
            stage = 1
        elseif crop == target then stage = stage + 1 end
    end
    api.robot = setmetatable({
        inventorySize = function() return 16 end,
        select = function(slot) selected = slot; return true end,
        swing = function()
            assert(not hand and selected == 3 and crop, "只能空手对中央已有作物执行一次拔除")
            swings = swings + 1
            local current = crop
            crop, rack, stage = nil, mode == "break_rack" and "missing" or "single", 0
            if current == target and generation ~= 2 then
                internal[3], internal[4] = bag(), bag()
                if mode == "unknown_seed" then internal[3].crop = nil end
            elseif current ~= target then
                internal[3] = bag("wheat") -- 即使非目标有掉种子，也必须保留。
            end
            internal[5] = { name = "minecraft:wheat", size = 2 }
            if mode == "break_rack" then internal[6] = { name = "IC2:blockCrop", size = 2 } end
            return true
        end,
        place = function()
            assert(selected == 1 and rack == "missing" and internal[1])
            if mode == "place_fail" then return false end
            places = places + 1
            internal[1].size = internal[1].size - 1
            if internal[1].size == 0 then internal[1] = nil end
            rack = "single"
            return true
        end,
        use = function()
            assert(selected == 1 and rack == "single" and hand and hand.name == "IC2:blockCrop")
            if mode == "use_fail" then return false end
            upgrades = upgrades + 1
            hand.size = hand.size - 1
            if hand.size == 0 then hand = nil end
            rack = "double"
            return true
        end,
        transferTo = function(destination, amount)
            assert(destination == 1 and selected == 6 and internal[6])
            internal[1] = internal[1] or { name = "IC2:blockCrop", size = 0 }
            internal[1].size, internal[6].size = internal[1].size + amount, internal[6].size - amount
            if internal[6].size == 0 then internal[6] = nil end
            return true
        end,
    }, { __index = forbidden })
    api.controller = setmetatable({
        getInventorySize = function(side) assert(side == 0 or side == 1); return side == 1 and 32 or 2 end,
        getStackInInternalSlot = function(slot) return copy(internal[slot]) end,
        getStackInSlot = function(side, slot) assert(side == 0 or side == 1); return copy((side == 1 and top or lower)[slot]) end,
        equip = function() assert(selected == 1 or selected == 2); hand, internal[selected] = internal[selected], hand; return true end,
        suckFromSlot = function(side, slot, amount)
            assert(side == 0 and selected == 1 and lower[slot])
            supply_calls = supply_calls + 1
            internal[1] = internal[1] or { name = "IC2:blockCrop", size = 0 }
            internal[1].size, lower[slot].size = internal[1].size + amount, lower[slot].size - amount
            if lower[slot].size == 0 then lower[slot] = nil end
            return true
        end,
        dropIntoSlot = function(side, slot, amount)
            assert(side == 1 and not top[slot] and internal[selected], "只向上方预留空槽存放")
            if mode == "partial_output" and internal[selected].name == "minecraft:wheat" then return false end
            top[slot] = copy(internal[selected]); top[slot].size = amount
            internal[selected].size = internal[selected].size - amount
            if internal[selected].size == 0 then internal[selected] = nil end
            return true
        end,
    }, { __index = forbidden })
    local function run(quantity)
        return auto.run(api, collector, preview, catalog, target, quantity or 2, 5, batch_journal, journal,
            function(line) output[#output + 1] = line end)
    end
    return run, function()
        return { swings = swings, places = places, upgrades = upgrades, sleeps = sleeps, supply = supply_calls,
            top = top, internal = internal, hand = hand, records = records, batches = batches, output = output,
            report = api.observe() }
    end, function(new_mode)
        mode = new_mode
        if new_mode == "normal" and not lower[1] then lower[1] = { name = "IC2:blockCrop", size = 40 } end
    end
end

for _, mode in ipairs({ "normal", "missing_rack", "break_rack" }) do
    local run, result = fixture(mode)
    local state = run()
    local actual = result()
    assert(state.phase == "complete" and state.owned == 2 and state.rounds == 3)
    assert(actual.swings == 3 and actual.upgrades >= 2)
    if mode ~= "break_rack" then assert(actual.supply > 0) end
    assert(actual.hand.name == "test:original_tool" and actual.internal[15].name == "test:pick" and actual.internal[16].size == 1)
    local stock = preview.inventory(catalog, {
        getInventorySize = function() return 32 end,
        getStackInSlot = function(_, slot) return actual.top[slot] end,
    }, 1)
    assert(stock.counts[target] == 2 and stock.counts["IC2:wheat"] == 1, "必须保存实际掉落的非目标种子")
    assert(not actual.internal[3] and not actual.internal[4] and not actual.internal[5], "副产物不能阻塞下一轮")
    if mode ~= "normal" then assert(actual.places > 0) end
    if mode == "break_rack" then assert(actual.supply == 0, "回收的作物架足够循环使用") end
end
do
    local run, result = fixture("owned")
    assert(run().phase == "complete" and result().swings == 0 and result().supply == 0)
end
for _, mode in ipairs({ "no_supply", "full", "disk_full", "unknown_seed", "partial_output", "changed_parent", "place_fail", "use_fail" }) do
    local run, result = fixture(mode)
    assert(not pcall(run), mode)
    local before = result()
    if mode == "full" or mode == "disk_full" then assert(before.swings == 0) end
    if mode == "partial_output" then assert(before.internal[5] and before.records[#before.records].phase == "output_pending") end
    if mode == "unknown_seed" then assert(before.internal[3] and before.records[#before.records].phase == "batch_pending") end
    assert(not pcall(run), "故障后不得重放未确认动作: " .. mode)
    assert(result().swings == before.swings and result().places == before.places)
end
do
    local run, result, change_mode = fixture("partial_supply")
    assert(not pcall(run))
    assert(result().internal[1].size == 1 and result().records[#result().records].phase == "working")
    change_mode("normal")
    assert(run().phase == "complete", "已核对的部分补给可以补足后继续，不能重复记账")
end
do
    local run, result, change_mode = fixture("cancel")
    assert(not pcall(run))
    assert(result().swings == 0 and result().records[#result().records].phase == "waiting")
    change_mode("normal")
    assert(run().phase == "complete", "纯等待中断后应可用同一命令继续")
end
print("crop_auto_test: passed (unwanted result, zero seeds, refill, missing/single racks, goal receipts, failures, waiting resume)")
