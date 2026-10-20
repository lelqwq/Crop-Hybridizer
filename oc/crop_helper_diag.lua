-- crop_helper 诊断脚本
-- 用法:
--   crop_helper_diag.lua info
--   crop_helper_diag.lua catalog [过滤文本]
--   crop_helper_diag.lua crop <owner:name>
--   crop_helper_diag.lua predict <owner:name> <owner:name> [limit] [offset]
--   crop_helper_diag.lua scan
--
-- 依赖服务器端 crop_helper 模组；没有模组时 info/catalog 会给出明确提示。
-- 机器人或电脑的 geolyzer 必须朝向要扫描的作物。

local component = require("component")
local sides = require("sides")

local PROTOCOL = 1
local DEFAULT_LIMIT = 32
local MAX_PAGE = 64

local function get_geolyzer()
    local address = component.list("geolyzer")()
    if not address then
        return nil, "没有找到 geolyzer 组件"
    end
    return component.proxy(address)
end

local function request(geolyzer, operation, args)
    local options = { crop_helper = operation, protocol = PROTOCOL }
    if args then
        for key, value in pairs(args) do
            options[key] = value
        end
    end

    local ok, scan, reason = pcall(geolyzer.analyze, sides.front, options)
    if not ok then
        return nil, "geolyzer.analyze 调用失败: " .. tostring(scan)
    end
    if not scan then
        return nil, "geolyzer.analyze 失败: " .. tostring(reason)
    end
    if type(scan) ~= "table" then
        return nil, "geolyzer.analyze 返回了非表结果: " .. tostring(scan)
    end

    local reply = scan.crop_helper
    if type(reply) ~= "table" then
        return nil, "辅助接口不可用：扫描结果中没有 crop_helper 字段（服务器未安装模组或版本不匹配）"
    end
    return reply
end

local function ensure_ok(reply)
    if reply.ok == true then
        return true
    end
    print("请求失败: " .. tostring(reply.error))
    if reply.detail then
        print("detail: " .. tostring(reply.detail))
    end
    return false
end

local function dump(value, indent, seen)
    indent = indent or ""
    if type(value) ~= "table" then
        return tostring(value)
    end
    seen = seen or {}
    if seen[value] then
        return "<循环引用>"
    end
    seen[value] = true

    local lines = {}
    local count = #value
    if count > 0 then
        lines[#lines + 1] = "{"
        for index = 1, count do
            lines[#lines + 1] = indent .. "  " .. dump(value[index], indent .. "  ", seen)
        end
        lines[#lines + 1] = indent .. "}"
    else
        local keys = {}
        for key in pairs(value) do
            keys[#keys + 1] = key
        end
        table.sort(keys, function(left, right)
            return tostring(left) < tostring(right)
        end)
        lines[#lines + 1] = "{"
        for _, key in ipairs(keys) do
            lines[#lines + 1] = indent .. "  " .. tostring(key) .. " = "
                .. dump(value[key], indent .. "  ", seen)
        end
        lines[#lines + 1] = indent .. "}"
    end

    seen[value] = nil
    return table.concat(lines, "\n")
end

local function join_numbers(values)
    local parts = {}
    for _, value in ipairs(values or {}) do
        parts[#parts + 1] = tostring(value)
    end
    return table.concat(parts, ",")
end

local function command_info(geolyzer)
    local reply, err = request(geolyzer, "info")
    if not reply then
        print(err)
        return
    end
    if not ensure_ok(reply) then
        return
    end

    print("模组版本: " .. tostring(reply.mod_version))
    print("协议版本: " .. tostring(reply.protocol))
    print("规则指纹: " .. tostring(reply.rules_fingerprint))
    if reply.catalog_size ~= nil then
        print("品种数量: " .. tostring(reply.catalog_size))
    end
    if reply.operations then
        print("支持操作: " .. table.concat(reply.operations, ", "))
    end
end

local function command_catalog(geolyzer, filter)
    local needle = filter and string.lower(filter) or nil
    local offset = 0
    local total = 0
    local matched = 0

    repeat
        local reply, err = request(geolyzer, "catalog", { offset = offset, limit = MAX_PAGE })
        if not reply then
            print(err)
            return
        end
        if not ensure_ok(reply) then
            return
        end

        total = tonumber(reply.total) or 0
        for _, crop in ipairs(reply.crops or {}) do
            local haystack = string.lower(tostring(crop.species_id or "") .. " "
                .. tostring(crop.display_name or ""))
            if not needle or needle == "" or string.find(haystack, needle, 1, true) then
                matched = matched + 1
                print(string.format(
                    "%-38s tier=%s max=%s stats=%s attrs=%s  %s",
                    tostring(crop.species_id),
                    tostring(crop.tier),
                    tostring(crop.max_size),
                    join_numbers(crop.stats),
                    table.concat(crop.attributes or {}, ","),
                    tostring(crop.display_name)))
            end
        end

        offset = reply.next_offset
    until not offset

    print(string.format("目录共 %s 个品种，匹配 %s 个", tostring(total), tostring(matched)))
end

local function command_crop(geolyzer, species_id)
    if not species_id or species_id == "" then
        print("用法: crop <owner:name>")
        return
    end
    local reply, err = request(geolyzer, "crop", { species_id = species_id })
    if not reply then
        print(err)
        return
    end
    if not ensure_ok(reply) then
        return
    end
    print(dump(reply.crop))
end

local function command_predict(geolyzer, parent_a, parent_b, limit, offset)
    if not parent_a or not parent_b then
        print("用法: predict <owner:name> <owner:name> [limit] [offset]")
        return
    end

    local reply, err = request(geolyzer, "predict", {
        parent_a = parent_a,
        parent_b = parent_b,
        offset = tonumber(offset) or 0,
        limit = tonumber(limit) or DEFAULT_LIMIT,
    })
    if not reply then
        print(err)
        return
    end
    if not ensure_ok(reply) then
        return
    end

    print("亲本: " .. tostring(reply.parent_a) .. " x " .. tostring(reply.parent_b))
    print("总权重: " .. tostring(reply.total_weight) .. "，候选数: " .. tostring(reply.total))
    if tonumber(reply.total) == 0 then
        print("无正权重候选（总权重为 0）")
        return
    end

    for _, candidate in ipairs(reply.candidates or {}) do
        local probability = tonumber(candidate.probability) or 0
        print(string.format(
            "%-38s weight=%s probability=%.4f%%",
            tostring(candidate.species_id),
            tostring(candidate.weight),
            probability * 100))
    end
    if reply.next_offset then
        print("还有更多候选，下一页 offset=" .. tostring(reply.next_offset))
    end
end

local function command_scan(geolyzer)
    local ok, scan, reason = pcall(geolyzer.analyze, sides.front)
    if not ok then
        print("调用失败: " .. tostring(scan))
        return
    end
    if not scan then
        print("扫描失败: " .. tostring(reason))
        return
    end
    print(dump(scan))
end

local function usage()
    print("用法:")
    print("  crop_helper_diag.lua info")
    print("  crop_helper_diag.lua catalog [过滤文本]")
    print("  crop_helper_diag.lua crop <owner:name>")
    print("  crop_helper_diag.lua predict <owner:name> <owner:name> [limit] [offset]")
    print("  crop_helper_diag.lua scan")
end

local function main(args)
    local geolyzer, geolyzer_error = get_geolyzer()
    if not geolyzer then
        print(geolyzer_error)
        return
    end

    local command = args[1] or "info"
    if command == "info" then
        command_info(geolyzer)
    elseif command == "catalog" then
        command_catalog(geolyzer, args[2])
    elseif command == "crop" then
        command_crop(geolyzer, args[2])
    elseif command == "predict" then
        command_predict(geolyzer, args[2], args[3], args[4], args[5])
    elseif command == "scan" then
        command_scan(geolyzer)
    else
        usage()
    end
end

main({ ... })
