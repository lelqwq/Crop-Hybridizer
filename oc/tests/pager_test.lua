-- 在项目根目录运行：lua oc/tests/pager_test.lua
-- 模拟 OpenOS less 管道，验证自动续页、退出和重定向行为。
local original_output, original_popen, original_print = io.output, io.popen, print
local terminal = { tty = true }
local calls, chunks, closed, quit_after, page_mode
local cancelled = {}

package.loaded.component = {
    list = function() return function() return "geolyzer" end end,
    proxy = function()
        return {
            analyze = function(_, options)
                calls[#calls + 1] = options.offset
                local offset = options.offset
                return { crop_helper = {
                    ok = true,
                    rules_fingerprint = page_mode == "changed" and offset > 0 and "new" or "rules",
                    parent_a = "IC2:wheat",
                    parent_b = "IC2:wheat",
                    total = 3,
                    total_weight = 100,
                    candidates = { { species_id = "test:crop" .. offset, weight = 10, probability = 0.1 } },
                    next_offset = page_mode == "invalid" and offset or (offset < 2 and offset + 1 or nil),
                } }
            end,
        }
    end,
}
package.loaded.sides = { front = 3 }

io.output = function() return terminal end
io.popen = function(command, mode)
    assert(command == "less" and mode == "w")
    assert(terminal.tty, "重定向时不应启动 less")
    return {
        write = function(_, ...)
            if quit_after and #chunks >= quit_after then
                -- OpenOS 管道在 less 退出后终止上游进程。
                error(cancelled)
            end
            chunks[#chunks + 1] = table.concat({ ... })
        end,
        close = function() closed = true end,
    }
end
print = function(value) chunks[#chunks + 1] = tostring(value) .. "\n" end

local function run(tty, stop, mode)
    terminal.tty = tty
    calls, chunks, closed, quit_after, page_mode = {}, {}, false, stop, mode
    local ok, reason = pcall(assert(loadfile("oc/crop_helper_diag.lua")),
        "predict", "IC2:wheat", "IC2:wheat", "1", "0")
    return ok, reason, table.concat(chunks)
end

local ok, reason, output = run(true)
assert(ok, tostring(reason))
assert(table.concat(calls, ",") == "0,1,2", "应继续查询后续候选")
assert(output:find("test:crop2", 1, true))
assert(not output:find("下一页 offset=", 1, true))
assert(closed, "查询结束应向 less 发送 EOF，让用户继续回看直到退出")
local _, header_count = output:gsub("亲本 A:", "")
assert(header_count == 1, "续页不应重复打印标题")

ok, reason = run(true, 5)
assert(not ok and reason == cancelled)
assert(#calls == 1, "退出查看后不能继续请求后续页")

ok, reason, output = run(false)
assert(ok, tostring(reason))
assert(#calls == 1 and not closed)
assert(output:find("下一页 offset=1", 1, true), "普通输出保留显式分页提示")

ok, reason, output = run(true, nil, "changed")
assert(ok and #calls == 2)
assert(output:find("规则指纹已变化", 1, true))
assert(not output:find("test:crop1", 1, true), "不能混用不同规则快照")

ok, reason, output = run(true, nil, "invalid")
assert(ok and #calls == 1)
assert(output:find("分页位置无效", 1, true), "异常分页不能无限循环")

io.output, io.popen, print = original_output, original_popen, original_print
print("pager_test: passed")
