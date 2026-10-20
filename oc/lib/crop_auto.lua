-- 固定双亲本工位的完整循环；只操作中央位，不丢弃收集到的物品。
local auto = {}
local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end
local function read(reader, ...)
    local value, reason = reader(...)
    assert(not reason, "读取失败: " .. tostring(reason))
    return value
end
local function sticks(stack)
    return stack and type(stack.name) == "string" and
        (stack.name:lower() == "ic2:itemcrop" or stack.name:lower() == "ic2:blockcrop")
end
local function seed(stack)
    return stack and type(stack.name) == "string" and stack.name:lower() == "ic2:itemcropseed"
end
local function checks(report)
    local result = {}
    for _, check in ipairs(report.checks or {}) do result[check.name] = check end
    return result
end

function auto.run(api, collector, preview, catalog, target, quantity, interval, batch_journal, journal, write)
    assert(catalog.by_id[target], "未知目标品种 ID")
    assert(integer(quantity, 1, 1000000), "目标数量须为正整数")
    assert(type(interval) == "number" and interval >= 0.5 and interval <= 60, "扫描间隔须为0.5至60秒")
    local old = journal.load()
    assert(not old or old.phase == "complete" or old.phase == "waiting" or (old.phase == "working" and not old.pending),
        "自动任务有未核对动作，请用 auto_status 查看记录，不能重放")
    if old and old.phase ~= "complete" then
        assert(old.target == target and old.quantity == quantity and old.robot_address == api.address
            and old.fingerprint == api.fingerprint, "已有自动任务与本次目标、机器人或规则不符，请先核对旧任务")
    end
    local batch = batch_journal.load()
    assert(not batch or batch.phase == "done" or batch.phase == "no_seed", "单次取种批次未完成，请先查看 status")
    local state = old and old.phase ~= "complete" and old or {
        version = 1, phase = "waiting", target = target, quantity = quantity, rounds = 0,
        robot_address = api.address, fingerprint = api.fingerprint,
    }
    local function save(phase, pending)
        state.phase, state.pending = phase, pending
        journal.save(state)
    end
    local function observe()
        local report = api.observe()
        if state.origin then
            assert(collector.same_position(state.origin, report)
                and collector.same_crop(state.origin.left, report.left)
                and collector.same_crop(state.origin.right, report.right), "工位位置或亲本已变化，停止自动任务")
        else
            assert(report.left.species_id and report.right.species_id, "左右需要已种植亲本")
            state.origin = report
        end
        local list = checks(report)
        for _, name in ipairs({ "parents_match", "extra_neighbor_3", "extra_neighbor_4", "candidate_weight" }) do
            assert(list[name] and list[name].status == "pass", "工位检查未通过: " .. name)
        end
        assert(list.center_crop_sticks and (list.center_crop_sticks.status == "pass"
            or list.center_crop_sticks.detail == "crop_sticks_missing"), "中央方块类型尚未支持")
        return report, list
    end
    local function snapshot(side)
        local size = api.controller.getInventorySize(side)
        assert(integer(size, 1, 100000), "补给或存储容器不可读取")
        local result = {}
        for slot = 1, size do result[slot] = read(api.controller.getStackInSlot, side, slot) end
        return result, size
    end
    local function same_amount(original, current, amount)
        if amount == 0 then return current == nil end
        if not current or current.size ~= amount then return false end
        local expected = {}
        for key, value in pairs(original) do expected[key] = value end
        expected.size = amount
        return collector.same_stack(expected, current)
    end
    local function supply(required)
        local stack = read(api.controller.getStackInInternalSlot, 1)
        assert(not stack or sticks(stack), "1号槽必须存放作物架")
        local count = stack and stack.size or 0
        if count >= required then return end
        local items, size = snapshot(api.down)
        for slot = 1, size do
            if sticks(items[slot]) then
                local amount = math.min(required - count, items[slot].size)
                assert(api.robot.select(1), "选择作物架槽失败")
                save("supply_pending", { slot = slot, count = amount, source = items[slot], before = count })
                local ok, reason = pcall(api.controller.suckFromSlot, api.down, slot, amount)
                local after = read(api.controller.getStackInInternalSlot, 1)
                local moved = (after and after.size or 0) - count
                assert(sticks(after) and moved > 0 and moved <= amount
                    and same_amount(items[slot], read(api.controller.getStackInSlot, api.down, slot), items[slot].size - moved),
                    "作物架补给未确认: " .. tostring(ok and "数量不符" or reason))
                save("working")
                count = after.size
                if count >= required then return end
            end
        end
        error("下方作物架补给不足，请补充后核对记录")
    end
    local function store_outputs()
        for slot = 2, api.robot.inventorySize() do
            if slot ~= 15 and slot ~= 16 then
                local source = read(api.controller.getStackInInternalSlot, slot)
                assert(not seed(source), "背包仍有未核对种子，保留并停止")
                if sticks(source) then
                    local stock = read(api.controller.getStackInInternalSlot, 1)
                    assert(not stock or sticks(stock), "1号槽不是作物架，停止回收")
                    local count = stock and stock.size or 0
                    local amount = math.min(source.size, 64 - count)
                    if amount > 0 then
                        assert(api.robot.select(slot), "选择回收槽失败")
                        save("recycle_pending", { source = slot, destination = 1, count = amount, stack = source })
                        pcall(api.robot.transferTo, 1, amount)
                        assert(same_amount(source, read(api.controller.getStackInInternalSlot, slot), source.size - amount)
                            and same_amount(source, read(api.controller.getStackInInternalSlot, 1), count + amount), "作物架回收未确认")
                        save("working")
                        source = read(api.controller.getStackInInternalSlot, slot)
                    end
                end
                if source then
                    local top, size = snapshot(api.up)
                    local destination
                    for index = 1, size do if not top[index] then destination = index; break end end
                    assert(destination, "上方箱满，剩余副产物保留背包中")
                    assert(api.robot.select(slot), "选择副产物槽失败")
                    save("output_pending", { source = slot, destination = destination, stack = source })
                    local ok, reason = pcall(api.controller.dropIntoSlot, api.up, destination, source.size)
                    assert(not read(api.controller.getStackInInternalSlot, slot)
                        and collector.same_stack(source, read(api.controller.getStackInSlot, api.up, destination)),
                        "副产物入库未确认: " .. tostring(ok and "数量或身份不符" or reason))
                    save("working")
                end
            end
        end
    end
    local function restore_rack()
        local report, list = observe()
        if report.center.species_id then return report end
        if list.center_crop_sticks.status ~= "pass" then
            supply(2)
            assert(api.robot.select(1), "选择作物架槽失败")
            local before = read(api.controller.getStackInInternalSlot, 1)
            save("rack_place_pending", { count_before = before.size })
            pcall(api.robot.place)
            report, list = observe()
            assert(list.center_crop_sticks.status == "pass"
                and same_amount(before, read(api.controller.getStackInInternalSlot, 1), before.size - 1), "放置中央作物架未确认")
            save("working")
        end
        if report.center.species_id then return report end
        assert(list.cross_sticks and list.cross_sticks.status ~= "unknown", "双层作物架状态未知")
        if list.cross_sticks.status ~= "pass" then
            supply(1)
            assert(api.robot.select(1), "选择作物架槽失败")
            local before = read(api.controller.getStackInInternalSlot, 1)
            save("rack_upgrade_pending", { count_before = before.size })
            assert(api.controller.equip(), "装备作物架失败")
            local parked = read(api.controller.getStackInInternalSlot, 1)
            state.pending.parked = parked
            local ok, reason = pcall(function()
                journal.save(state)
                local current, current_checks = observe()
                assert(not current.center.species_id and current_checks.cross_sticks
                    and current_checks.cross_sticks.status == "blocked", "升级前中央已变化")
                api.robot.use()
            end)
            assert(collector.same_stack(parked, read(api.controller.getStackInInternalSlot, 1)), "装备暂存槽变化，请人工恢复")
            assert(api.robot.select(1) and api.controller.equip(), "恢复手持物失败")
            assert(ok, tostring(reason))
            report, list = observe()
            assert(same_amount(before, read(api.controller.getStackInInternalSlot, 1), before.size - 1)
                and (report.center.species_id or (list.cross_sticks and list.cross_sticks.status == "pass")),
                "双层作物架升级未确认")
            save("working")
        end
        return report
    end

    observe()
    collector.check_storage(api)
    local initial_sticks = read(api.controller.getStackInInternalSlot, 1)
    assert(not initial_sticks or sticks(initial_sticks), "1号槽必须存放作物架")
    save("waiting")
    local last_message
    while true do
        local stock = preview.inventory(catalog, api.controller, api.up)
        local owned = stock.counts[target] or 0
        local changed = state.owned ~= owned
        state.owned = owned
        if changed and state.phase == "waiting" then journal.save(state) end
        if owned >= quantity then
            state.owned = owned
            save("complete")
            write("目标箱内已确认: " .. target .. " x" .. owned)
            return state
        end
        local report = restore_rack()
        local processed = false
        if report.center.species_id then
            local crop, check = report.center, report.collection
            local message = crop.species_id .. ":" .. tostring(crop.size) .. ":" .. tostring(check.status)
            if message ~= last_message then collector.show(report, write); last_message = message end
            if crop.species_id ~= target or report.ready_for_collection then
                local clear = crop.species_id ~= target
                write(clear and ("清除非目标中央作物: " .. crop.species_id) or "目标已可取种，开始保存")
                save("batch_pending", { species_id = crop.species_id, clear = clear, crop = crop })
                local result = collector.run(api, preview, catalog, crop.species_id, batch_journal, report, { clear = clear })
                state.rounds = state.rounds + 1
                store_outputs()
                processed = true
                write(string.format("已处理%d轮，本轮保存种子%d份", state.rounds, result.stored or 0))
                last_message = nil
            else
                assert(check.status == "blocked" and check.detail == "not_harvestable_yet",
                    "目标取种条件未知或不受支持，保留目标植株并停止")
            end
        else
            local list = checks(report)
            for _, check in pairs(list) do assert(check.status ~= "unknown", "工位条件未知: " .. check.name) end
            if last_message ~= "empty" then write("等待杂交结果或当前环境恢复…"); last_message = "empty" end
        end
        if state.phase ~= "waiting" then save("waiting") end
        if not processed then api.sleep(interval) end
    end
end

return auto
