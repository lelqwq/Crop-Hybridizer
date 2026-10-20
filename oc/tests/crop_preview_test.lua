-- 项目根目录运行：lua oc/tests/crop_preview_test.lua
local preview = assert(loadfile("oc/lib/crop_preview.lua"))()
local function crop(id, tier, value, attributes)
    local owner, name = id:match("^([^:]+):(.+)$")
    return { species_id = id, owner = owner, name = name, tier = tier,
        stats = { value, value, value, value, value }, attributes = attributes or {}, max_size = 4 }
end
local catalog = preview.catalog({
    crop("test:A", 1, 0, { "a" }),
    crop("test:M", 2, 2, { "A", "b" }),
    crop("test:T", 3, 4, { "B" }),
})
local function seed(name, size, growth)
    return { name = "IC2:itemCropSeed", size = size,
        crop = { name = name, growth = growth or 0, gain = 0, resistance = 0 } }
end
local items = { seed("A", 2), seed("A", 3, 10),
    { name = "ic2:itemcropseed", size = 1 }, seed("T", 1, 32),
    seed("missing", 1), { name = "minecraft:stone", size = 64 } }
local inventory = preview.inventory(catalog, {
    getInventorySize = function(side) assert(side == 1); return 7 end,
    getStackInSlot = function(side, slot) assert(side == 1); return items[slot] end,
}, 1)
assert(#inventory.batches == 2 and inventory.counts["test:A"] == 5)
assert(inventory.batches[1].growth == 0 and inventory.batches[2].growth == 10)
assert(#inventory.unknown == 3 and inventory.ignored == 1)
assert(not pcall(preview.inventory, catalog, { getInventorySize = function() return nil, "no inventory" end }, 1))

local ambiguous = preview.catalog({ crop("one:A", 1, 1), crop("two:A", 2, 2) })
local result = preview.inventory(ambiguous, {
    getInventorySize = function() return 1 end,
    getStackInSlot = function() return seed("A", 3) end,
}, 1)
assert(#result.unknown == 1 and #result.batches == 0, "同名作物不能按标签或等级猜测身份")
assert(not pcall(preview.catalog, { crop("one:A", 1, 1), crop("one:A", 1, 1) }))
assert(not pcall(preview.plan, catalog, {}, "test:missing", 1))
assert(not pcall(preview.plan, catalog, {}, "test:T", 1.5))
assert(preview.plan(catalog, { ["test:T"] = 2 }, "test:T", 2).status == "owned")
assert(preview.plan(catalog, { ["test:A"] = 1 }, "test:T", 1).status == "insufficient_parents")
assert(preview.plan(catalog, { ["test:A"] = 2 }, "test:T", 1).status == "insufficient_parents")

-- A 无法直接得到 T，必须先获得 M；验证资源保留和批次工作种子的扣除。
local counts = { ["test:A"] = 3 }
result = preview.plan(catalog, counts, "test:T", 2)
assert(result.status == "candidate" and #result.steps == 2)
assert(result.steps[1].species_id == "test:M" and result.steps[1].count == 3)
assert(result.steps[2].species_id == "test:T" and result.steps[2].count == 2)
assert(counts["test:A"] == 3 and counts["test:M"] == nil, "预演不能修改真实库存快照")
local replay = { ["test:A"] = 3 }
for _, step in ipairs(result.steps) do
    replay[step.parent_a] = replay[step.parent_a] - 1
    replay[step.parent_b] = replay[step.parent_b] - 1
    assert(replay[step.parent_a] >= 1 and replay[step.parent_b] >= 1)
    replay[step.species_id] = (replay[step.species_id] or 0) + step.count
end
assert(replay["test:A"] == 1 and replay["test:M"] == 1 and replay["test:T"] == 2)
assert(preview.plan(catalog, counts, "test:T", 2, { depth = 1 }).status == "not_found")
local yielded = 0
result = preview.plan(catalog, counts, "test:T", 2, { budget = 1, yield = function() yielded = yielded + 1 end })
assert(result.status == "not_found" and result.budget_reached and yielded == 1)

-- 两个不同亲本各留一份，用工作亲本批量扩繁已有目标品种。
local same = preview.catalog({ crop("test:A", 1, 0), crop("test:B", 1, 0) })
result = preview.plan(same, { ["test:A"] = 2, ["test:B"] = 2 }, "test:A", 5)
assert(result.status == "candidate" and result.steps[1].count == 4)

-- 用用户导出的真实目录复算游戏截图中的小麦组合。
local file = assert(io.open("crop_catalog.txt", "r"))
local crops = {}
while true do
    local id = file:read("*l")
    if not id or id:match("^目录共") then break end
    id = id:gsub("\r$", "")
    local display = assert(file:read("*l"))
    local level = assert(file:read("*l"))
    local stats = assert(file:read("*l"))
    local tags = assert(file:read("*l")):gsub("\r$", "")
    local owner, name = id:match("^([^:]+):(.+)$")
    local tier, size = level:match("等级=(%d+) 最大阶段=(%d+)")
    local values, attributes = {}, {}
    for value in stats:gmatch("%-?%d+") do values[#values + 1] = tonumber(value) end
    for tag in tags:sub(#"  标签: " + 1):gmatch("[^,]+") do attributes[#attributes + 1] = tag end
    crops[#crops + 1] = { species_id = id, owner = owner, name = name, display_name = display,
        tier = tonumber(tier), max_size = tonumber(size), stats = values, attributes = attributes }
end
file:close()
local real = preview.catalog(crops)
assert(#real.crops == 160)
local wheat = real.by_id["IC2:wheat"]
local weights, total = preview.distribution(real, wheat, wheat)
local candidates = 0
for _, weight in pairs(weights) do if weight > 0 then candidates = candidates + 1 end end
assert(total == 1618 and candidates == 53 and weights["IC2:wheat"] == 1000)
assert(weights["IC2:potato"] == 40 and weights["berriespp:Barley"] == 40)
assert(weights["IC2:carrots"] == 30 and weights["berriespp:Turnip"] == 30)
result = preview.plan(real, { ["IC2:wheat"] = 3 }, "IC2:coffee", 1, { budget = 32 })
assert(result.evaluated <= 32)
print("crop_preview_test: passed (inventory, chain, reserves, budget, 160-crop weights)")
