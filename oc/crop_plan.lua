-- 教程原布局的只读盘点和路线预演；不移动机器人或物品，不调用旧杂交循环。
-- 安装：/home/crop_plan.lua 与 /home/lib/ 下的 crop_preview.lua、crop_site.lua。
local component = require("component")
local sides = require("sides")
local filesystem = require("filesystem")
local path = filesystem.path(os.getenv("_") or "oc/crop_plan.lua")
local preview = assert(loadfile(filesystem.concat(path, "lib/crop_preview.lua")))()
local site = assert(loadfile(filesystem.concat(path, "lib/crop_site.lua")))()
local print = print

local function get_component(kind)
    local address = component.list(kind)()
    assert(address, "缺少组件: " .. kind)
    return component.proxy(address)
end

local function prepare(target, quantity, check_site)
    local geolyzer = get_component("geolyzer")
    local controller = get_component("inventory_controller")
    local catalog, fingerprint = preview.read_catalog(geolyzer, sides.front, function() os.sleep(0) end)
    -- 原教程中央待机位正上方的种子箱；不访问作物架、除草剂或充电器所在位置。
    local stock = preview.inventory(catalog, controller, sides.up)
    local plan
    if target then
        plan = preview.plan(catalog, stock.counts, target, quantity, {
            depth = 4, beam = 6, budget = 256,
            yield = function() os.sleep(0) end,
        })
    end
    local result = { catalog = catalog, fingerprint = fingerprint, stock = stock, plan = plan }
    if check_site and plan and plan.steps[1] then
        local step = plan.steps[1]
        local ok, report = pcall(site.query, geolyzer, sides.front,
            step.parent_a, step.parent_b, step.species_id, fingerprint)
        if ok then result.site = report else result.site_error = tostring(report) end
    end
    return result
end

local function show(result, target, quantity)
    print("教程布局：中央待机位，上方种子箱")
    print("只读预演，不移动机器人或物品")
    print("规则指纹:")
    for start = 1, #result.fingerprint, 32 do
        print("  " .. result.fingerprint:sub(start, start + 31))
    end
    print("已识别种子批次:")
    for _, batch in ipairs(result.stock.batches) do
        print(string.format("槽位 %d: %s x%d", batch.slot, batch.species_id, batch.count))
        print(string.format("  Gr=%d Ga=%d Re=%d", batch.growth, batch.gain, batch.resistance))
    end
    print("按品种合计（每种保护一份）:")
    for _, crop in ipairs(result.catalog.crops) do
        local count = result.stock.counts[crop.species_id]
        if count then print(crop.species_id .. " x" .. tostring(count)) end
    end
    for _, unknown in ipairs(result.stock.unknown) do
        print("未识别槽位 " .. tostring(unknown.slot))
        print("  " .. unknown.reason)
    end
    print("非种子占用槽位: " .. tostring(result.stock.ignored))
    print("左右已种活体与机器人背包未计入")
    if not result.plan then return end

    print("目标: " .. target .. " x" .. tostring(quantity))
    local plan = result.plan
    if plan.status == "owned" then
        print("箱内已识别种子数量已满足目标")
        return
    elseif plan.status == "insufficient_parents" then
        print("保护种子后，没有可部署的双亲本")
        print("异种：每种至少2份；同种：至少3份")
        return
    elseif plan.status == "not_found" then
        print("本次搜索预算内未找到候选路线")
        print("不表示不可达；可能需扩繁或增加资源")
    else
        print("候选路线（环境与取种尚未验证）:")
        for i, step in ipairs(plan.steps) do
            print("步骤 " .. tostring(i))
            print("  左亲本: " .. step.parent_a)
            print("  右亲本: " .. step.parent_b)
            print("  保存: " .. step.species_id .. " x" .. tostring(step.count))
            print(string.format("  条件相对概率=%.4f%%", step.probability * 100))
        end
        print(string.format("路线排序分值: %.2f", plan.cost))
        print("该分值不是预计秒数或保底尝试次数")
    end
    print("已评估亲本组合: " .. tostring(plan.evaluated))
    print("搜索上限：4步、6条分支、256次组合")
    print("工作种子按消耗计，不预估拆除回收")
    print("中间品种先留3份，不按最终三围淘汰")
    print("现场条件检查完成前不可自动执行")
    if result.site then site.show(result.site, print) end
    if result.site_error then
        print("当前工位检查未完成:")
        print(result.site_error)
    end
end

local args = { ... }
local command = args[1] or "plan"
if command ~= "inventory" and command ~= "plan" and command ~= "check" then
    print("crop_plan.lua inventory")
    print("crop_plan.lua plan <完整品种ID> [数量]")
    print("crop_plan.lua check <完整品种ID> [数量]")
    return
end
local target, quantity
if command ~= "inventory" then
    target = args[2]
    if not target then
        print("输入目标的完整品种ID，如 IC2:coffee")
        target = io.read("*l")
        print("输入目标种子数量（默认1）")
        local input = io.read("*l")
        quantity = input == "" and 1 or tonumber(input)
    else
        quantity = args[3] == nil and 1 or tonumber(args[3])
    end
end
if command ~= "inventory" and (type(target) ~= "string" or target == "") then
    print("未提供目标品种 ID")
    return
end
print("读取上方种子箱和目录，进行只读预演…")
local ok, result = pcall(prepare, target, quantity, command == "check")
if not ok then
    io.stderr:write("预演失败: " .. tostring(result) .. "\n")
    return
end

local pager
if io.output().tty then
    local reason
    pager, reason = io.popen("less", "w")
    if not pager then print("无法启动 less: " .. tostring(reason)); return end
    print = function(value) pager:write(tostring(value), "\n") end
    print("方向键滚动，PgUp/PgDn翻页，Q退出")
end
show(result, target, quantity)
if pager then pager:close() end
