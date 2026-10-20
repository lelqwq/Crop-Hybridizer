-- 等待本身只读；目标确认后才交给已有单次取种流程。
local collector = assert(loadfile("oc/lib/crop_collect.lua"))()
local id = "gregtech:Brown Mushrooms"
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, item in pairs(value) do result[key] = copy(item) end
    return result
end
local function report(kind, size)
    local center = { x = 1, y = 64, z = 2, size = size or 0 }
    local parent = { species_id = "IC2:wheat", growth = 5, gain = 6, resistance = 1 }
    if kind ~= "empty" then
        center.species_id, center.growth, center.gain, center.resistance = id, 5, 6, 1
    end
    local ready = kind == "ready"
    return { center = center, left = copy(parent), right = copy(parent), dimension = 0,
        status = kind == "empty" and "pass" or "blocked", ready_for_crossing = kind == "empty",
        ready_for_collection = ready, collection = {
            status = ready and "pass" or "blocked", detail = ready and "reviewed_pick_with_random_seed_drops"
                or (kind == "empty" and "no_center_crop" or "not_harvestable_yet"),
        } }
end
local calls = 0
collector.run = function(api, preview, catalog, expected, journal, observed)
    assert(expected == id and observed.ready_for_collection and observed.center.species_id == id)
    calls = calls + 1
    return { phase = "done", stored = 1 }
end
local function fixture(reports, mode)
    local scans, sleeps, messages = 0, {}, {}
    local api = {
        robot = { inventorySize = function() return 16 end },
        controller = {
            getStackInInternalSlot = function() return nil end,
            getInventorySize = function() return 2 end,
            getStackInSlot = function() if mode == "full" then return { name = "test:item", size = 64 } end end,
        }, up = 1,
        observe = function()
            scans = scans + 1
            assert(reports[scans], "不得无限扫描或越过异常")
            return copy(reports[scans])
        end,
        sleep = function(interval)
            if mode == "cancel" then error("interrupted") end
            sleeps[#sleeps + 1] = interval
        end,
    }
    local journal = {
        load = function() if mode == "pending" then return { phase = "swing_pending" } end end,
        save = function() error("等待阶段不能写取种动作记录") end,
    }
    local function run(interval)
        return collector.wait_for_target(api, {}, { by_id = { [id] = {} } }, id, journal, interval,
            function(line) messages[#messages + 1] = line end)
    end
    return run, function() return scans, sleeps, messages end
end
do
    local run, state = fixture({ report("empty"), report("empty"), report("growing", 1), report("growing", 2), report("ready", 3) })
    assert(run(5).phase == "done" and calls == 1)
    local scans, sleeps, messages = state()
    assert(scans == 5 and #sleeps == 4)
    for _, seconds in ipairs(sleeps) do assert(seconds == 5) end
    assert(#messages == 15, "重复空架状态不应刷屏，生长阶段改变才输出")
end
for _, interval in ipairs({ 0, -1, 0.1, 61, math.huge, 0 / 0, "5" }) do
    local run, state = fixture({ report("ready", 3) })
    assert(not pcall(run, interval))
    assert(state() == 0, "无效间隔不能启动扫描")
end
local cases = {}
cases.other = { report("empty"), report("growing", 1) }
cases.other[2].center.species_id = "IC2:wheat"
cases.unknown = { report("growing", 1) }
cases.unknown[1].collection.status = "unknown"
cases.unsupported = { report("growing", 1) }
cases.unsupported[1].collection.detail = "vanilla_wheat_seeds_only"
cases.site_blocked = { report("empty") }
cases.site_blocked[1].status, cases.site_blocked[1].ready_for_crossing = "blocked", false
cases.site_unknown = { report("empty") }
cases.site_unknown[1].status, cases.site_unknown[1].ready_for_crossing = "unknown", false
cases.position = { report("empty"), report("ready", 3) }
cases.position[2].center.x = 2
cases.dimension = { report("empty"), report("ready", 3) }
cases.dimension[2].dimension = -1
cases.parent = { report("empty"), report("ready", 3) }
cases.parent[2].left.gain = 9
cases.replaced_target = { report("growing", 1), report("ready", 3) }
cases.replaced_target[2].center.growth = 10
cases.disappeared_target = { report("growing", 1), report("empty") }
for mode, reports in pairs(cases) do
    local run = fixture(reports)
    assert(not pcall(run, 5), mode)
    assert(calls == 1, mode .. " 时不能调用取种")
end
for _, mode in ipairs({ "pending", "full", "cancel" }) do
    local run, state = fixture({ report("empty") }, mode)
    assert(not pcall(run, 5), mode)
    local scans = state()
    assert(scans == (mode == "cancel" and 1 or 0) and calls == 1)
end
print("crop_wait_test: passed (empty to mature, one collection, changed site, cancellation, no action while waiting)")
