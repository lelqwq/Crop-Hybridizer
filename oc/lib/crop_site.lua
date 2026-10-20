-- 现场工位查询与显示；不移动机器人，不模拟未来环境，不授权自动执行。
local site = {}
local status_text = { pass = "通过", blocked = "未通过", unknown = "未知" }
local names = {
    center_crop_sticks = "中央作物架", left_crop_sticks = "左侧作物架", right_crop_sticks = "右侧作物架",
    empty_center = "中央是否为空", cross_sticks = "双层杂交架", parents_match = "亲本是否符合计划",
    extra_neighbor_3 = "中央另一侧邻居", extra_neighbor_4 = "机器人所在位置",
    left_can_grow_at_center = "左亲本对中央环境的要求", right_can_grow_at_center = "右亲本对中央环境的要求",
    left_can_cross = "左亲本能否参与杂交", right_can_cross = "右亲本能否参与杂交",
    candidate_can_grow_at_center = "候选能否通过中央位条件",
    candidate_weight = "候选是否有正权重",
}
local details = {
    crop_sticks_missing = "此位置未找到 IC2 作物架",
    empty_center_required = "需要中央位为空的杂交架",
    double_crop_sticks_required = "中央需要双层作物架",
    two_planted_parents_required = "左右需要两株已种植的亲本",
    planned_pair_differs_from_live_parents = "现场亲本与路线首步不一致",
    unplanned_adjacent_crop = "有额外相邻作物，双亲本模型不适用",
    parent_tile_not_observed = "亲本状态尚未读取完整",
    unreviewed_tile_class = "该作物方块类型尚未支持",
    cross_sticks_flag_unavailable = "无法确认作物架是否为双层",
    crop_or_tile_missing = "缺少可检查的作物或工位信息",
    candidate_weight_zero = "该亲本组合对候选的理论权重为0",
}

function site.query(geolyzer, front, first, second, candidate, fingerprint)
    local scan, reason = geolyzer.analyze(front, {
        crop_helper = "site", protocol = 1, parent_a = first, parent_b = second, candidate = candidate,
    })
    assert(type(scan) == "table", "工位扫描失败: " .. tostring(reason))
    local reply = scan.crop_helper
    assert(type(reply) == "table", "服务器未提供 crop_helper 接口")
    if reply.error == "unsupported_operation" then error("工位检查需要升级 crop_helper 到 0.2.0") end
    assert(reply.ok, tostring(reply.error) .. ": " .. tostring(reply.detail))
    assert(reply.protocol == 1, "辅助模组协议不兼容")
    assert(not fingerprint or reply.rules_fingerprint == fingerprint, "规则指纹已变化，请重新运行预演")
    local report = reply.site
    assert(type(report) == "table" and type(report.checks) == "table", "工位报告不完整")
    local aggregate = #report.checks == 0 and "unknown" or "pass"
    for _, check in ipairs(report.checks) do
        assert(status_text[check.status], "工位检查状态无效")
        if check.status == "blocked" then aggregate = "blocked"
        elseif check.status == "unknown" and aggregate == "pass" then aggregate = "unknown" end
    end
    assert(report.status == aggregate, "工位检查汇总不一致")
    assert(report.ready_for_crossing == (aggregate == "pass"), "工位就绪状态不一致")
    return report
end

function site.show(report, write)
    write("当前工位检查: " .. status_text[report.status])
    for _, key in ipairs({ "center", "left", "right" }) do
        local crop = report[key] or {}
        local label = ({ center = "中央", left = "左亲本", right = "右亲本" })[key]
        write(label .. ": " .. tostring(crop.species_id or "未识别到作物"))
        if crop.size ~= nil then
            write(string.format("  阶段=%s 光照=%s", tostring(crop.size), tostring(crop.light)))
        end
    end
    if report.candidate then write("本次候选: " .. report.candidate)
    else write("未指定候选，本次仅检查当前亲本") end
    for _, check in ipairs(report.checks) do
        write((names[check.name] or check.name) .. ": " .. status_text[check.status])
        if check.status ~= "pass" then
            local detail = details[check.detail]
            if check.detail == "predicate_false" then
                detail = check.name:find("can_cross", 1, true)
                    and "尚不满足该作物的杂交阶段或条件" or "中央位的当前生长条件未满足"
            end
            write("  " .. (detail or "该作物条件或环境信息尚未支持"))
            if check.status == "unknown" and not detail and check.detail then
                write("  原因: " .. tostring(check.detail))
            end
        end
    end
    write("仅核对当前一组亲本，不代表整条路线")
    write("整条路线尚不可自动执行")
    write("中央结果可用 crop_collect.lua inspect 检查")
end

return site
