local component = require("component")
local sides = require("sides")
local robot = require("robot")

local geolyzer = component.geolyzer
local inventory_controller = component.inventory_controller

local target_crop_name -- 用户输入要杂交的作物
local reference_growth, reference_gain = 0, 0 -- 生长、产量比较基准
local middle_crop_growth, middle_crop_gain, middle_crop_resistance = 0, 0, 0 -- 中间作物的生长、产量、抗性
local target_growth, target_gain, target_resistance = 0, 0, 0 -- 用户设置的生长、产量、抗性上限
local fail_counts = 0 -- 杂交失败次数
local success_counts = 0 -- 杂交成功次数
local SleepTime = 1 -- 扫描间隔（秒），启动时由用户输入

-- 从扫描结果 x 中返回作物名 crop:name，缺失时返回方块名 name；两者都缺失则返回 nil。
function get_crop_name(x)
    local name = x["crop:name"]
    if name == nil then
        name = x.name
    end
    return name
end

-- 从扫描结果 x 中依次返回 growth、gain、resistance；缺失的属性返回 nil，不执行扫描。
function get_mid_crop_status(x)
    return x["crop:growth"], x["crop:gain"], x["crop:resistance"]
end

-- 按 growth + gain 选出较弱的一侧亲本，并同步更新筛选基准；相等时选左侧。
function weaker_parent_side()
    if (Rgr + Rga) < (Lgr + Lga) then
        reference_growth = Rgr
        reference_gain = Rga
        return "right"
    else
        reference_growth = Lgr
        reference_gain = Lga
        return "left"
    end
end

-- 扫描机器人内部全部槽位，返回是否存在 IC2 种子袋，以及首次出现种子袋的槽位。
function has_seed_in_inventory()
    for slot = 1, robot.inventorySize() do
        local stack = inventory_controller.getStackInInternalSlot(slot)
        if stack and string.lower(stack.name) == "ic2:itemcropseed" then
            return true, slot
        end
    end
    return false, nil
end

-- 是否淘汰中间作物
function should_discard_middle_crop()
    -- 扫描结果缺少三围时无法比较，直接淘汰
    if middle_crop_growth == nil or middle_crop_gain == nil or middle_crop_resistance == nil then
        return true
    end

    -- 生长或产量低于基准亲本，或两者都没有提升，直接淘汰；忽略抗性下降
    if middle_crop_growth < reference_growth or middle_crop_gain < reference_gain
        or (middle_crop_growth == reference_growth and middle_crop_gain == reference_gain) then
        return true

    -- 任一属性超过用户设置的上限，直接淘汰
    elseif middle_crop_growth > target_growth or middle_crop_gain > target_gain or middle_crop_resistance > target_resistance then
        return true
    else
        return false
    end
end

-- 返回作物当前生长阶段
function get_crop_current_size(x)
    return x["crop:size"]
end

-- 返回作物最大生长阶段
function get_crop_max_size(x)
    return x["crop:maxSize"]
end

-- 放置作物架（不是双层的杂交架）
function place_crop_sticks()
    robot.select(1)
    robot.place()
end

-- 放置杂交架（放置两层作物架），完成后换回原手持物
function place_hybridization_rack()
    place_crop_sticks()
    robot.select(1)
    inventory_controller.equip()
    robot.use()
    inventory_controller.equip()
end

-- 更换左侧亲本（机器人视角）
function replace_left_parent_crop(seed_slot)
    robot.turnLeft()
    robot.forward()
    robot.turnRight()
    break_front_crop()
    place_crop_sticks()
	-- 放置种子，完成后换回原手持物
    robot.select(seed_slot)
    inventory_controller.equip()
    robot.use()
    inventory_controller.equip()
    -- 更新左侧亲本作物数值
    Lgr = middle_crop_growth
    Lga = middle_crop_gain
    Lre = middle_crop_resistance
	-- 没除草剂了，补充除草剂
    if robot.count(16) == 0 then
        robot.select(16)
        robot.suckDown(1)
    end
    apply_weed_ex_if_needed()
	-- 回到主位置
    robot.turnRight()
    robot.forward()
    robot.turnLeft()
end

-- 更换右侧亲本（机器人视角）
function replace_right_parent_crop(seed_slot)
    robot.turnRight()
    robot.forward()
    robot.turnLeft()
    break_front_crop()
    place_crop_sticks()
	-- 放置种子，完成后换回原手持物
    robot.select(seed_slot)
    inventory_controller.equip()
    robot.use()
    inventory_controller.equip()
    -- 更新右侧亲本作物数值
    Rgr = middle_crop_growth
    Rga = middle_crop_gain
    Rre = middle_crop_resistance
	-- 没除草剂了，补充除草剂
    if robot.count(16) == 0 then
        robot.select(16)
        robot.suckDown(1)
    end
    apply_weed_ex_if_needed()
	-- 回到主位置
    robot.turnLeft()
    robot.forward()
    robot.turnRight()
end

-- 作物架不足5个时补充至64个
function replenish_crop_sticks_if_needed()
	local crop_sticks_num =robot.count(1)
    if crop_sticks_num < 5 then
        robot.select(1)
        robot.suckDown(64 - crop_sticks_num)
        print("补充作物架")
    end
end

-- 清理槽位
-- 把除 1、15、16 号功能槽以外的物品向左扔出，配合垃圾桶表示丢弃
function clear_slots()
    for slot = 2, robot.inventorySize() do
        if slot ~= 15 and slot ~= 16 then
            local stack = inventory_controller.getStackInInternalSlot(slot)
            if stack then
                robot.select(slot)
                robot.drop(sides.left)
            end
        end
    end
end

-- 把指定槽位的种子袋放到上面的容器中
function drop_seed_up(slot)
    local stack = inventory_controller.getStackInInternalSlot(slot)
    if stack and string.lower(stack.name) == "ic2:itemcropseed" then
        robot.select(slot)
        robot.dropUp()
    end
end

-- 中间作物的除草剂值小于 50 时，尝试使用除草剂
function apply_weed_ex_if_needed()
    local crop = geolyzer.analyze(sides.front)
    local weedex = crop["crop:weedex"]

    if weedex ~= nil and weedex < 50 then
        robot.select(16)
        inventory_controller.equip()
        robot.use()
        inventory_controller.equip()
    end
end

-- 打掉作物或作物架
function break_front_crop()
    robot.select(15)
    inventory_controller.equip()
    robot.select(1)-- 设置掉落物收纳的起始槽位
    robot.swing()
    robot.select(15)
    inventory_controller.equip()
end

-- 成功计数加 1，并无条件打印失败、成功和总次数；不自行判断本次操作是否成功。
function add_success_counts()
    success_counts = success_counts + 1
    print("失败", fail_counts, "成功", success_counts, "总共", fail_counts + success_counts)
end

-- 失败计数加 1；仅当 IfPrintFailTimes == 1 时打印失败、成功和总次数。
function add_fail_counts()
    fail_counts = fail_counts + 1
    if IfPrintFailTimes == 1 then
        print("失败", fail_counts, "成功", success_counts, "总共", fail_counts + success_counts)
    end
end

-- 对亲本使用除草剂，在中间位置放置杂交架
function apply_weedex_and_place_rack()
    -- 初始位置：机器人位于中央，面向中间作物位置；1 号槽放作物架，16 号槽放除草剂

    -- 16号槽位有物品，即有除草剂，使用除草剂
    if robot.count(16) > 0 then
        -- 向左平移一格，重新面向左侧亲本
        robot.turnLeft()
        robot.forward()
        robot.turnRight()

        -- 将 16 号槽的除草剂与手持物交换，并对左侧亲本使用
        robot.select(16)
        inventory_controller.equip()
        robot.use()

        -- 向右平移两格，重新面向右侧亲本
        robot.turnRight()
        robot.forward()
        robot.forward()
        robot.turnLeft()

        -- 对右侧亲本使用除草剂，再交换回原来的手持物
        robot.use()
        inventory_controller.equip()

        -- 向左平移一格，回到中央并恢复初始朝向
        robot.turnLeft()
        robot.forward()
        robot.turnRight()
    end

    -- 在中央放置杂交架（双层作物架）
    place_hybridization_rack()
end

-- 培育作物三维数值
-- 内部为无限循环，正常工作时不会返回主菜单。
function breed_crop_by_stats()
    while true do
        local crop = geolyzer.crop(sides.front)
        local name = get_crop_name(crop)

        if name == "IC2:blockCrop" then
            -- 空杂交架，等待作物出现
            os.sleep(SleepTime)

        -- 目标作物
        elseif string.lower(name) == target_crop_name then
            middle_crop_growth, middle_crop_gain, middle_crop_resistance = get_mid_crop_status(crop)
            local parent_side = weaker_parent_side()

            -- 中间作物数值不达标
            if should_discard_middle_crop() then
                break_front_crop()
                clear_slots()
                place_hybridization_rack()
                add_fail_counts()

            -- 中间作物数值达标且生长进度100%
            elseif get_crop_current_size(crop) == get_crop_max_size(crop) then
                break_front_crop()

                local has_seed, seed_slot = has_seed_in_inventory()
                -- 没掉种子
                if not has_seed then
                    add_fail_counts()
                else
                    if parent_side == "right" then
                        replace_right_parent_crop(seed_slot)
                    else
                        replace_left_parent_crop(seed_slot)
                    end
                    print("成功", "Gr=", middle_crop_growth, "Ga=", middle_crop_gain, "Re=", middle_crop_resistance)
                    add_success_counts()
                    -- 如果该槽位还有种子，就把多的种子放到箱子里
                    drop_seed_up(seed_slot)
                end
                clear_slots()
                place_hybridization_rack()
            else
                os.sleep(SleepTime)
            end

        -- 其他作物或杂草
        else
            break_front_crop()
            clear_slots()
            place_hybridization_rack()
            add_fail_counts()
        end

        -- 补充作物架
        replenish_crop_sticks_if_needed()
    end
end

-- 模式 1：持续收获指定作物种子，不比较三围。
function harvest_target_crop_seeds()
    while true do
        local crop = geolyzer.analyze(sides.front)
        local name = get_crop_name(crop)
        
        if name == "IC2:blockCrop" then
            -- 空杂交架，等待作物出现
            os.sleep(SleepTime)

        -- 目标作物
        elseif string.lower(name) == target_crop_name then
            -- 作物生长100%
            if get_crop_current_size(crop) == get_crop_max_size(crop) then
                break_front_crop()
                local has_seed, seed_slot = has_seed_in_inventory()
                if not has_seed then
                    add_fail_counts()
                else
                    add_success_counts()
                    -- 把收获的种子放到上面的容器中
                    drop_seed_up(seed_slot)
                end
                clear_slots()
                place_hybridization_rack()
            else
                os.sleep(SleepTime)
            end
        else
            add_fail_counts()
            break_front_crop()
            clear_slots()
            place_hybridization_rack()
        end
        replenish_crop_sticks_if_needed()
    end
end

-- 模式 1 按指定品种筛选，模式 2 按三围培育。
function main()
    print("1号槽放作物架,15号槽放鹤嘴锄,16号槽除草剂,其他位置不要放物品\n")
    print("选择杂交模式:\n")
    print("\t1 -> 无视gr、ga、re值,只选择杂交出特定作物\n")
    print("\t2 -> 正常按照gr、ga、re值杂交\n")
    ChangeMode = io.read("*n")
    io.read("*l") -- 消耗换行符

    if (ChangeMode == 1) then
        print("输入特定作物")
        target_crop_name = string.lower(io.read("*l"))

        print("输入等待时间(秒),太长可能会长杂草或收获别的作物,太短会增加耗电量,EV世界加速器建议2~4")
        SleepTime = io.read("*n")
        print("失败时是否打印次数?(输入1则打印,输入2则不打印)")
        IfPrintFailTimes = io.read("*n")
        apply_weedex_and_place_rack()
        harvest_target_crop_seeds()
    elseif (ChangeMode == 2) then
        print("输入作物名称:")
        target_crop_name = string.lower(io.read("*l"))

        print("输入等待时间(秒),太长可能会长杂草或收获别的作物,太短会增加耗电量,EV世界加速器建议2~4")
        SleepTime = io.read("*n")
        print("失败时是否打印次数?(输入1则打印,输入2则不打印)")
        IfPrintFailTimes = io.read("*n")

        print("输入想要控制的Gr(生长速度)值(以内)")
        target_growth = io.read("*n")

        print("输入想要控制的Ga(产量)值(以内)")
        target_gain = io.read("*n")

        print("输入想要控制的Re(抗性)值(以内)")
        target_resistance = io.read("*n")

        print("注意左右两边作物架的Gr、Ga、Re值不能差太大")
        print("输入左边作物的Gr值")
        Lgr = io.read("*n")

        print("输入左边作物的Ga值")
        Lga = io.read("*n")

        print("输入左边作物的Re值")
        Lre = io.read("*n")

        print("输入右边作物的Gr值")
        Rgr = io.read("*n")

        print("输入右边作物的Ga值")
        Rga = io.read("*n")

        print("输入右边作物的Re值")
        Rre = io.read("*n")
        -- 对亲本使用除草剂，在中间放杂交架
        apply_weedex_and_place_rack()
        breed_crop_by_stats()
    end
end

-- 程序入口
main()
