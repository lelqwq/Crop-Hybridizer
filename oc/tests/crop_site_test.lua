-- 项目根目录运行：lua oc/tests/crop_site_test.lua
local site = assert(loadfile("oc/lib/crop_site.lua"))()
local report = {
    status = "pass", ready_for_crossing = true, automation_ready = false,
    checks = { { name = "parents_match", status = "pass", detail = "planned_pair_matches" } },
    center = { size = 0, light = 12 }, left = { species_id = "IC2:wheat", size = 7, light = 12 },
    right = { species_id = "IC2:wheat", size = 7, light = 12 }, candidate = "IC2:coffee",
}
local reply = { ok = true, protocol = 1, rules_fingerprint = "rules", site = report }
local calls = 0
local geolyzer = {
    analyze = function(front, options)
        calls = calls + 1
        assert(front == 3 and options.crop_helper == "site" and options.protocol == 1)
        assert(options.x == nil and options.y == nil and options.z == nil)
        assert(options.parent_a == "IC2:wheat" and options.parent_b == "IC2:wheat")
        assert(options.candidate == "IC2:coffee")
        return { crop_helper = reply }
    end,
}
local function query(fingerprint)
    return site.query(geolyzer, 3, "IC2:wheat", "IC2:wheat", "IC2:coffee", fingerprint)
end
assert(query("rules") == report and calls == 1)
local output = {}
site.show(report, function(line) output[#output + 1] = line end)
local text = table.concat(output, "\n")
assert(text:find("当前工位检查: 通过", 1, true))
assert(text:find("整条路线尚不可自动执行", 1, true))

report.checks[1] = { name = "parents_match", status = "blocked", detail = "planned_pair_differs_from_live_parents" }
report.status, report.ready_for_crossing = "blocked", false
assert(query("rules").status == "blocked")
report.checks[2] = { name = "candidate_can_grow_at_center", status = "unknown", detail = "unreviewed_crop_class: test" }
assert(query("rules").status == "blocked", "确认不满足优先于未知")
report.checks[1].status = "pass"
report.status = "unknown"
assert(query("rules").status == "unknown")
output = {}
site.show(report, function(line) output[#output + 1] = line end)
assert(table.concat(output, "\n"):find("原因: unreviewed_crop_class: test", 1, true))
report.checks[2].detail = "unreviewed_crop_version: IC2=other; gregtech=MC1710"
output = {}
site.show(report, function(line) output[#output + 1] = line end)
assert(table.concat(output, "\n"):find("原因: unreviewed_crop_version:", 1, true))
report.ready_for_crossing = true
assert(not pcall(query, "rules"), "未知不能显示为可杂交")
report.ready_for_crossing = false
assert(not pcall(query, "different"), "不能混用不同规则快照")
reply = { ok = false, protocol = 1, error = "unsupported_operation" }
local ok, reason = pcall(query, "rules")
assert(not ok and tostring(reason):find("0.2.0", 1, true))

-- 诊断脚本的 site 子命令也必须能定位共享模块并显示三态报告。
report.checks = { { name = "parents_match", status = "pass", detail = "planned_pair_matches" } }
report.status, report.ready_for_crossing = "pass", true
reply = { ok = true, protocol = 1, rules_fingerprint = "rules", site = report }
package.loaded.component = {
    list = function() return function() return "geolyzer" end end,
    proxy = function() return geolyzer end,
}
package.loaded.sides = { front = 3 }
package.loaded.filesystem = {
    path = function(value) return value:match("^(.*)/") end,
    concat = function(path, file) return path .. "/" .. file end,
}
local original_print, original_getenv = print, os.getenv
os.getenv = function(key) if key == "_" then return "oc/crop_helper_diag.lua" end; return original_getenv(key) end
local diagnostic = {}
print = function(line) diagnostic[#diagnostic + 1] = line end
assert(loadfile("oc/crop_helper_diag.lua"))("site", "IC2:wheat", "IC2:wheat", "IC2:coffee")
print, os.getenv = original_print, original_getenv
assert(table.concat(diagnostic, "\n"):find("当前工位检查: 通过", 1, true))
print("crop_site_test: passed (tri-state, snapshot, old-mod detection, no remote coordinates)")
