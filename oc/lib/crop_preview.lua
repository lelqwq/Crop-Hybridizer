-- 纯数据逻辑：品种目录、种子识别和受库存约束的候选路线预演。
local preview = {}

local function integer(value, minimum, maximum)
    return type(value) == "number" and value == math.floor(value)
        and value >= minimum and value <= maximum
end

function preview.catalog(crops)
    local catalog = { crops = {}, by_id = {}, by_name = {} }
    for _, crop in ipairs(crops) do
        assert(type(crop.owner) == "string" and crop.owner ~= "", "目录缺少 owner")
        assert(type(crop.name) == "string" and crop.name ~= "", "目录缺少原始名称")
        assert(crop.species_id == crop.owner .. ":" .. crop.name, "品种 ID 与目录身份不一致")
        assert(not catalog.by_id[crop.species_id], "重复品种 ID: " .. crop.species_id)
        assert(integer(crop.tier, 0, 1000), "无效品种等级")
        assert(type(crop.stats) == "table" and #crop.stats == 5, "固有属性必须有五项")
        for _, value in ipairs(crop.stats) do
            assert(integer(value, -1000, 1000), "无效固有属性")
        end
        assert(type(crop.attributes) == "table", "目录缺少标签")
        for _, attribute in ipairs(crop.attributes) do
            assert(type(attribute) == "string", "无效品种标签")
            assert(not attribute:find("[\128-\255]"), "非 ASCII 标签需使用服务器权重查询")
        end
        catalog.crops[#catalog.crops + 1] = crop
        catalog.by_id[crop.species_id] = crop
        local matches = catalog.by_name[crop.name] or {}
        matches[#matches + 1] = crop
        catalog.by_name[crop.name] = matches
    end
    table.sort(catalog.crops, function(a, b) return a.species_id < b.species_id end)
    return catalog
end

function preview.inventory(catalog, controller, side)
    local size, reason = controller.getInventorySize(side)
    assert(integer(size, 1, 100000), "无法读取上方种子容器: " .. tostring(reason))
    local result = { batches = {}, unknown = {}, counts = {}, ignored = 0, slots = size }
    for slot = 1, size do
        local stack, read_error = controller.getStackInSlot(side, slot)
        assert(not read_error, "读取上方容器失败: " .. tostring(read_error))
        if stack then
            if type(stack.name) == "string" and stack.name:lower() == "ic2:itemcropseed" then
                local crop = stack.crop
                local species, issue
                if not integer(stack.size, 1, 1000000) then
                    issue = "种子数量无效"
                elseif type(crop) ~= "table" or type(crop.name) ~= "string" then
                    issue = "缺少分析数据，需完整分析种子"
                else
                    local matches = catalog.by_name[crop.name] or {}
                    if #matches == 1 then
                        species = matches[1]
                    elseif #matches > 1 then
                        issue = "原始名称对应多个品种，无法确认身份"
                    else
                        issue = "原始名称未在当前目录注册: " .. crop.name
                    end
                    for _, key in ipairs({ "growth", "gain", "resistance" }) do
                        if not integer(crop[key], 0, 31) then
                            issue = "缺少或无效的种子三围"
                        end
                    end
                end
                if issue then
                    result.unknown[#result.unknown + 1] = { slot = slot, reason = issue }
                else
                    result.batches[#result.batches + 1] = {
                        species_id = species.species_id, slot = slot, count = stack.size,
                        growth = crop.growth, gain = crop.gain, resistance = crop.resistance,
                    }
                    result.counts[species.species_id] = (result.counts[species.species_id] or 0) + stack.size
                end
            else
                result.ignored = result.ignored + 1
            end
        end
    end
    return result
end

function preview.ratio(candidate, parent)
    if candidate.species_id == parent.species_id then return 500 end
    local weight = 0
    for i = 1, 5 do weight = weight + 2 - math.abs(candidate.stats[i] - parent.stats[i]) end
    for _, a in ipairs(candidate.attributes) do
        for _, b in ipairs(parent.attributes) do
            if a:lower() == b:lower() then weight = weight + 5 end
        end
    end
    local difference = candidate.tier - parent.tier
    if difference > 1 then weight = weight - 2 * difference end
    if difference < -3 then weight = weight + difference end
    return math.max(weight, 0)
end

function preview.distribution(catalog, first, second)
    local weights, total = {}, 0
    for _, crop in ipairs(catalog.crops) do
        local weight = preview.ratio(crop, first) + preview.ratio(crop, second)
        weights[crop.species_id] = weight
        total = total + weight
    end
    return weights, total
end

local function copy(map)
    local result = {}
    for key, value in pairs(map) do result[key] = value end
    return result
end

local function pairs_for(catalog, counts)
    local ids = {}
    for _, crop in ipairs(catalog.crops) do
        if (counts[crop.species_id] or 0) >= 2 then ids[#ids + 1] = crop.species_id end
    end
    local i, j = 1, 0
    return function()
        while i <= #ids do
            j = j + 1
            if j > #ids then i = i + 1; j = i end
            if i > #ids then return end
            local first, second = ids[i], ids[j]
            -- 每个品种保护一份；同品种双亲本还需要两份工作种子。
            if first ~= second or counts[first] >= 3 then return first, second end
        end
    end
end

local function signature(catalog, counts)
    local values = {}
    for _, crop in ipairs(catalog.crops) do
        values[#values + 1] = tostring(counts[crop.species_id] or 0)
    end
    return table.concat(values, ",")
end

function preview.plan(catalog, counts, target, quantity, options)
    assert(catalog.by_id[target], "目标未注册，请输入目录中的完整品种 ID")
    assert(integer(quantity, 1, 1000000), "目标数量必须是 1～1000000 的整数")
    for id, count in pairs(counts) do
        assert(catalog.by_id[id] and integer(count, 1, 1000000), "库存记录无效")
    end
    options = options or {}
    local depth = options.depth or 4
    local beam = options.beam or 6
    local budget = options.budget or 256
    assert(integer(depth, 1, 16) and integer(beam, 1, 32) and integer(budget, 1, 4096), "搜索预算无效")
    if (counts[target] or 0) >= quantity then
        return { status = "owned", steps = {}, cost = 0, evaluated = 0 }
    end
    if not pairs_for(catalog, counts)() then
        return { status = "insufficient_parents", steps = {}, evaluated = 0 }
    end

    local frontier = { { counts = copy(counts), steps = {}, cost = 0 } }
    local seen = { [signature(catalog, counts)] = 0 }
    local best, evaluated, limited = nil, 0, false
    local goal = catalog.by_id[target]

    local function priority(state)
        local affinity = 0
        for id, count in pairs(state.counts) do
            if count >= 2 then affinity = math.max(affinity, preview.ratio(goal, catalog.by_id[id])) end
        end
        -- 仅用作束搜索排序；不是经过环境验证的预计耗时或最优性证明。
        return state.cost + 1000 / (1 + affinity)
    end

    for _ = 1, depth do
        local next_frontier = {}
        for _, state in ipairs(frontier) do
            for first, second in pairs_for(catalog, state.counts) do
                if evaluated >= budget then limited = true; break end
                evaluated = evaluated + 1
                if options.yield then options.yield(evaluated) end
                local weights, total = preview.distribution(catalog, catalog.by_id[first], catalog.by_id[second])
                for _, crop in ipairs(catalog.crops) do
                    local id = crop.species_id
                    local after = (state.counts[id] or 0) - (id == first and 1 or 0) - (id == second and 1 or 0)
                    local required = id == target and quantity or 3
                    local amount = required - after
                    -- 已有足量品种不重复扩展；目标和中间品种分别按实际所需数量保种。
                    if (state.counts[id] or 0) < required and amount > 0 and weights[id] > 0 then
                        local probability = weights[id] / total
                        local next_counts = copy(state.counts)
                        next_counts[first] = next_counts[first] - 1
                        next_counts[second] = next_counts[second] - 1
                        next_counts[id] = (next_counts[id] or 0) + amount
                        local cost = state.cost + amount / probability
                        local key = signature(catalog, next_counts)
                        if (not seen[key] or cost < seen[key]) and (not best or cost < best.cost) then
                            local steps = {}
                            for i, step in ipairs(state.steps) do steps[i] = step end
                            steps[#steps + 1] = {
                                parent_a = first, parent_b = second, species_id = id,
                                count = amount, probability = probability,
                            }
                            local next_state = { counts = next_counts, steps = steps, cost = cost, key = key }
                            if id == target then
                                best = next_state
                            else
                                for index = #next_frontier, 1, -1 do
                                    if next_frontier[index].key == key then
                                        if next_frontier[index].cost <= cost then next_state = nil
                                        else table.remove(next_frontier, index) end
                                    end
                                end
                                if next_state then
                                    next_state.priority = priority(next_state)
                                    next_frontier[#next_frontier + 1] = next_state
                                    table.sort(next_frontier, function(a, b)
                                        if a.priority ~= b.priority then return a.priority < b.priority end
                                        return a.key < b.key
                                    end)
                                    if #next_frontier > beam then table.remove(next_frontier) end
                                end
                            end
                        end
                    end
                end
            end
            if limited then break end
        end
        frontier = next_frontier
        -- 只保留实际入选状态的去重记录，避免在低内存机器人上累积全部分支。
        for _, state in ipairs(frontier) do seen[state.key] = state.cost end
        if limited or #frontier == 0 then break end
    end
    return {
        status = best and "candidate" or "not_found",
        steps = best and best.steps or {}, cost = best and best.cost,
        evaluated = evaluated, budget_reached = limited,
    }
end

function preview.read_catalog(geolyzer, front, yield)
    local crops, offset, fingerprint, total = {}, 0
    repeat
        local scan, reason = geolyzer.analyze(front, {
            crop_helper = "catalog", protocol = 1, offset = offset, limit = 64,
        })
        assert(type(scan) == "table", "目录扫描失败: " .. tostring(reason))
        local reply = scan.crop_helper
        assert(type(reply) == "table", "服务器未提供 crop_helper 接口")
        assert(reply.ok, tostring(reply.error) .. ": " .. tostring(reply.detail))
        assert(reply.protocol == 1, "辅助模组协议不兼容")
        assert(type(reply.rules_fingerprint) == "string" and reply.rules_fingerprint ~= "", "缺少规则指纹")
        if fingerprint then
            assert(reply.rules_fingerprint == fingerprint and reply.total == total, "目录发生变化，请重新运行")
        else
            fingerprint, total = reply.rules_fingerprint, reply.total
            assert(type(total) == "number" and total > 0 and total == math.floor(total), "目录数量无效")
        end
        assert(type(reply.crops) == "table" and #reply.crops > 0, "目录分页为空")
        for _, crop in ipairs(reply.crops) do crops[#crops + 1] = crop end
        assert(#crops <= total, "目录数量超过声明总数")
        if not reply.next_offset then break end
        assert(type(reply.next_offset) == "number" and reply.next_offset == offset + #reply.crops,
            "目录分页位置无效")
        offset = reply.next_offset
        if yield then yield() end
    until false
    assert(#crops == total, "目录不完整，请重新运行")
    return preview.catalog(crops), fingerprint
end

return preview
