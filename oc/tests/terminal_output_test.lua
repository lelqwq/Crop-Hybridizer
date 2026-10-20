-- 在项目根目录运行：lua oc/tests/terminal_output_test.lua
-- 用模拟组件检查输出，不执行机器人动作。
local original_print = print
local original_read = io.read
local lines = {}
local response
local scan = { ["crop:name"] = "wheat", ["crop:growth"] = 20 }
local geolyzer = {
    analyze = function(_, options)
        if options then
            return { crop_helper = response }
        end
        return scan
    end,
}

package.loaded.component = {
    list = function()
        return function() return "test-geolyzer" end
    end,
    proxy = function() return geolyzer end,
    geolyzer = geolyzer,
    inventory_controller = {},
}
package.loaded.sides = { front = 3 }
package.loaded.robot = {}

print = function(value, ...)
    assert(select("#", ...) == 0, "输出不应依赖多参数 print 的制表符间隔")
    for line in (tostring(value) .. "\n"):gmatch("(.-)\n") do
        assert(not line:find("\t", 1, true), "输出中存在制表符")
        assert(not line:gsub("^ +", ""):find("    ", 1, true), "输出中存在固定宽度补空格")
        -- 样本只包含 ASCII 和占两列的中文/全角标点。
        local width = 0
        for char in line:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            width = width + (#char == 1 and 1 or 2)
        end
        assert(width <= 50, "样本行超出 50 列屏幕: " .. line)
        lines[#lines + 1] = line
    end
end

local function run(reply, ...)
    lines = {}
    response = reply
    assert(loadfile("oc/crop_helper_diag.lua"))(...)
    return table.concat(lines, "\n")
end

local output = run({
    ok = true,
    parent_a = "IC2:wheat",
    parent_b = "berriespp:Blue Glowshroom",
    total_weight = 1618,
    total = 53,
    candidates = {
        { species_id = "IC2:wheat", weight = 1000, probability = 1000 / 1618 },
        { species_id = "berriespp:Blue Glowshroom", weight = 40, probability = 40 / 1618 },
    },
    next_offset = 5,
}, "predict", "IC2:wheat", "berriespp:Blue Glowshroom", "5", "0")
assert(output:find("IC2:wheat\n  权重=1000 概率=61.8047%", 1, true))
assert(output:find("offset=5", 1, true))

output = run({
    ok = true,
    total = 1,
    crops = { {
        species_id = "berriespp:Blue Glowshroom",
        display_name = "蓝色荧光菇",
        tier = 4,
        max_size = 5,
        stats = { 1, 2, 3, 4, 5 },
        attributes = { "Blue", "Food", "Mushroom" },
    } },
}, "catalog")
assert(output:find("berriespp:Blue Glowshroom\n  名称: 蓝色荧光菇", 1, true))
assert(output:find("固有属性: 1,2,3,4,5", 1, true))
assert(output:find("标签: Blue,Food,Mushroom", 1, true))

local fingerprint = string.rep("0123456789abcdef", 4)
run({
    ok = true,
    mod_version = "0.3.0",
    protocol = 1,
    rules_fingerprint = fingerprint,
    catalog_size = 160,
    operations = { "info", "catalog", "crop", "predict", "site" },
}, "info")
assert(lines[4]:sub(3) .. lines[5]:sub(3) == fingerprint, "规则指纹不能丢失字符")

output = run({ ok = true, crop = { species_id = "IC2:wheat", stats = { 1, 2, 3 } } }, "crop", "IC2:wheat")
assert(output:find("species_id = IC2:wheat", 1, true))
output = run(nil, "scan")
assert(output:find("crop:name = wheat", 1, true))
output = run({ ok = false, error = "unknown_crop", detail = "unknown parent_a: IC2:missing" },
    "predict", "IC2:missing", "IC2:wheat")
assert(output:find("请求失败: unknown_crop", 1, true))
output = run({ ok = true, parent_a = "A", parent_b = "B", total = 0, total_weight = 0 }, "predict", "A", "B")
assert(output:find("无正权重候选", 1, true))

-- 无效模式让入口立即返回，只检查启动提示和计数函数。
lines = {}
io.read = function() return 0 end
assert(loadfile("crop_hybridizer.lua"))()
io.read = original_read
add_success_counts()
IfPrintFailTimes = 1
add_fail_counts()
assert(lines[#lines - 1] == "失败=0 成功=1 总共=1")
assert(lines[#lines] == "失败=1 成功=1 总共=2")

print = original_print
print("terminal_output_test: passed (50-column output)")
