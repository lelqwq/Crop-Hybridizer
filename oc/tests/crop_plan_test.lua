-- 项目根目录运行：lua oc/tests/crop_plan_test.lua
-- 白名单模拟组件：任何移动、种植、取放物品的调用都会失败。
local original_print, original_getenv, original_sleep = print, os.getenv, os.sleep
local original_output, original_popen = io.output, io.popen
local original_stderr = io.stderr
local output, errors, reads, mode, offsets, pager_closed, interactive, site_calls
local crops = {}
for i, name in ipairs({ "A", "M", "T" }) do
    crops[i] = { species_id = "test:" .. name, owner = "test", name = name, tier = i,
        stats = { 2 * (i - 1), 2 * (i - 1), 2 * (i - 1), 2 * (i - 1), 2 * (i - 1) },
        attributes = i == 1 and { "a" } or (i == 2 and { "a", "b" } or { "b" }), max_size = 4 }
end
local controller = setmetatable({
    getInventorySize = function(side)
        assert(side == 1, "只能读取中央待机位上方的种子箱")
        reads = reads + 1
        if mode == "missing_box" then return nil, "no inventory" end
        return 2
    end,
    getStackInSlot = function(side, slot)
        assert(side == 1)
        if slot == 1 then
            return { name = "ic2:itemcropseed", size = 3,
                crop = { name = "A", growth = 5, gain = 6, resistance = 1 } }
        end
        return { name = "ic2:itemcropseed", size = 1 }
    end,
}, { __index = function(_, key) error("禁止的物品操作: " .. key) end })
local geolyzer = {
    analyze = function(side, options)
        if options.crop_helper == "site" then
            site_calls = site_calls + 1
            assert(side == 3 and options.parent_a == "test:A" and options.parent_b == "test:A")
            assert(options.candidate == "test:M", "只能核对路线首步，不能假装部署未来亲本")
            if mode == "site_old" then
                return { crop_helper = { ok = false, error = "unsupported_operation" } }
            end
            return { crop_helper = { ok = true, protocol = 1, rules_fingerprint = "rules", site = {
                status = "blocked", ready_for_crossing = false,
                checks = { { name = "empty_center", status = "blocked", detail = "empty_center_required" } },
            } } }
        end
        assert(side == 3 and options.crop_helper == "catalog" and options.protocol == 1)
        local offset = options.offset
        offsets[#offsets + 1] = offset
        if mode == "no_helper" then return {} end
        local reply = { ok = true, protocol = 1, rules_fingerprint = "rules", total = 3,
            crops = { crops[offset + 1] }, next_offset = offset < 2 and offset + 1 or nil }
        if mode == "changed" and offset == 1 then reply.rules_fingerprint = "new" end
        if mode == "bad_page" then reply.next_offset = 0 end
        if mode == "duplicate" and offset == 1 then reply.crops = { crops[1] } end
        return { crop_helper = reply }
    end,
}
package.loaded.component = {
    list = function(kind)
        assert(kind == "geolyzer" or kind == "inventory_controller")
        return function() return kind end
    end,
    proxy = function(address) return address == "geolyzer" and geolyzer or controller end,
}
package.loaded.sides = { front = 3, up = 1 }
package.loaded.filesystem = {
    path = function(path) return assert(path:match("^(.*)/")) end,
    concat = function(path, name) return path .. "/" .. name end,
}
os.getenv = function(key) if key == "_" then return "oc/crop_plan.lua" end; return original_getenv(key) end
os.sleep = function(delay) assert(delay == 0) end
io.output = function() return { tty = interactive } end
io.popen = function(command, direction)
    assert(command == "less" and direction == "w" and interactive)
    return {
        write = function(_, ...) output[#output + 1] = table.concat({ ... }) end,
        close = function() pager_closed = true end,
    }
end
io.stderr = { write = function(_, value) errors[#errors + 1] = value end }
print = function(value) output[#output + 1] = tostring(value) .. "\n" end

local function run(test_mode, tty, ...)
    output, errors, offsets, reads, pager_closed, mode, interactive = {}, {}, {}, 0, false, test_mode, tty
    site_calls = 0
    assert(loadfile("oc/crop_plan.lua"))(...)
    return table.concat(output), table.concat(errors)
end

local text, err = run(nil, false, "inventory")
assert(err == "" and reads == 1 and table.concat(offsets, ",") == "0,1,2")
assert(text:find("test:A x3", 1, true) and text:find("Gr=5 Ga=6 Re=1", 1, true))
assert(text:find("未识别槽位 2", 1, true))
assert(not text:find("步骤 1", 1, true))

text, err = run(nil, true, "plan", "test:T", "2")
assert(err == "" and pager_closed)
assert(text:find("步骤 2", 1, true) and text:find("保存: test:T x2", 1, true))
assert(text:find("未识别槽位 2", 1, true))
assert(text:find("环境与取种尚未验证", 1, true))

text, err = run(nil, false, "check", "test:T", "2")
assert(err == "" and site_calls == 1 and text:find("当前工位检查: 未通过", 1, true))
text, err = run("site_old", false, "check", "test:T", "2")
assert(err == "" and site_calls == 1 and text:find("0.2.0", 1, true))
assert(text:find("步骤 2", 1, true), "检查不可用时仍保留候选路线，但不能称为已验证")

text, err = run(nil, false, "plan", "test:missing", "1")
assert(err:find("目标未注册", 1, true))
text, err = run(nil, false, "plan", "test:T", "oops")
assert(err:find("目标数量必须", 1, true))
text, err = run("missing_box", false, "inventory")
assert(err:find("上方种子容器", 1, true))
for _, test_mode in ipairs({ "changed", "bad_page", "duplicate", "no_helper" }) do
    text, err = run(test_mode, false, "inventory")
    assert(err ~= "" and reads == 0, "目录异常时不能继续盘点: " .. test_mode)
end

print, os.getenv, os.sleep = original_print, original_getenv, original_sleep
io.output, io.popen, io.stderr = original_output, original_popen, original_stderr
print("crop_plan_test: passed (tutorial layout, read-only APIs, paging, errors, less)")
