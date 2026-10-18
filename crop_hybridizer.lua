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

-- 从扫描结果 x 中返回作物名 crop:name，缺失时返回方块名 name；两者都缺失则返回 nil。
function get_crop_name(x)
    local name = x["crop:name"]
    if name == nil then
        name = x.name
    end
    return name
end

-- 从扫描结果 x 中依次返回 growth、gain、resistance；缺失的属性返回 nil，不执行扫描。
function middle_crop(x)
    return x["crop:growth"], x["crop:gain"], x["crop:resistance"]
end

-- 按 growth + gain 选择较小的一侧亲本，将其生长、产量写入 reference_growth/reference_gain；相等时选左侧。
-- 返回待替换侧 "left" 或 "right"，确保筛选基准与实际被替换的亲本一致；不移动机器人。
function l_or_r()
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

-- 生长和产量均不低于基准、至少一项提升，且三项属性均不超过用户设置的上限时保留。
-- 抗性只限制上限，不参与亲本优劣评分；返回 true 表示淘汰。
function should_discard_middle_crop()
    -- 生长或产量低于基准亲本，直接淘汰。
    if middle_crop_growth < reference_growth or middle_crop_gain < reference_gain then
        return true
	else -- middle_crop_growth >= reference_growth and middle_crop_gain >= reference_gain
		-- 任一属性超过用户设置的上限，直接淘汰。
		if middle_crop_growth > target_growth or middle_crop_gain > target_gain or middle_crop_resistance > target_resistance then
			return true
		end

		-- 生长和产量都没有提升时，不重复替换亲本；抗性下降不会抵消这两项的提升。
        return middle_crop_growth == reference_growth and middle_crop_gain == reference_gain
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

-- 更换左侧亲本（机器人视角）
function replace_left_parent_crop()
    robot.turnLeft()
    robot.forward()
    robot.turnRight()
    break_front_crop()
    place_crop_sticks()
	-- 放置种子
    robot.select(3)
    inventory_controller.equip()
    robot.use()
    inventory_controller.equip()
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
function replace_right_parent_crop()
    robot.turnRight()
    robot.forward()
    robot.turnLeft()
    break_front_crop()
    place_crop_sticks()
	-- 放置种子
    robot.select(3)
    inventory_controller.equip()
    robot.use()
    inventory_controller.equip()
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

-- 将收获的作物放到上方箱子里
function drop_up_crop()
	local crop_num = robot.count(2)
	robot.select(2)
	robot.dropUp(crop_num)
	robot.select(1)
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

-- 依次尝试将 3、4、5 号槽的全部物品向上转移
function drop_slots_3_to_5_up()
    robot.select(3)
    robot.dropUp()
    robot.select(4)
    robot.dropUp()
    robot.select(5)
    robot.dropUp()
    robot.select(1)
end

-- 扫描前方作物；存在 crop:weedex 且值小于 50 时，尝试使用 16 号槽的除草剂。
-- 施用后交换回原手持物并选中 1 号槽；条件不满足时不改变选中槽位，也不打掉杂草。
function apply_weed_ex_if_needed()
    local Analyze = geolyzer.analyze(sides.front)
    local weedex = Analyze["crop:weedex"]

    if weedex ~= nil and weedex < 50 then
        robot.select(16)
        inventory_controller.equip()
        robot.use()
        inventory_controller.equip()
        robot.select(1)
    end
end

-- 临时装备 15 号槽的工具，对前方执行一次 swing，再交换回原手持物，最后选中 1 号槽。
-- 用于打掉作物或作物架；不检查挥击是否成功，也不负责重新放置或种植。
function break_front_crop()
    robot.select(15)
    inventory_controller.equip()
    robot.select(1)-- 设置掉落物收纳的起始槽位
    robot.swing()
    robot.select(15)
    inventory_controller.equip()
    robot.select(1)
end

-- 成功计数加 1，并无条件打印失败、成功和总次数；不自行判断本次操作是否成功。
function success()
    success_counts = success_counts + 1
    print("失败", fail_counts, "成功", success_counts, "总共", fail_counts + success_counts)
end

-- 失败计数加 1；仅当 IfPrintFailTimes == 1 时打印失败、成功和总次数。
function failure()
    fail_counts = fail_counts + 1
    if IfPrintFailTimes == 1 then
        print("失败", fail_counts, "成功", success_counts, "总共", fail_counts + success_counts)
    end
end

-- 若 16 号槽有物品，则将其作为除草剂依次用于左右亲本，再回到中央并恢复初始朝向。
-- 随后用 1 号槽作物架尝试搭建中央双层杂交架；不检查移动、施药或放置是否成功。
function beginning()
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

    -- 在中央放置一个普通作物架
    place_crop_sticks()

    -- 手持作物架再次使用，补成双层杂交架，再恢复手持物
    inventory_controller.equip()
    robot.use()
    inventory_controller.equip()
end

-- 模式 2：持续扫描中央，淘汰非指定品种及属性不合格的作物，等待合格作物成熟后收获。
-- 以 3 号槽剩余容量是否为 64 判定收获失败；否则替换筛选时选定的亲本（生长 + 产量较低侧，相等选左侧）。
-- 更新被替换亲本的属性记录、统计次数、清理种子槽并重建杂交架，每轮检查作物架补给。
-- 内部为无限循环，正常工作时不会返回主菜单。
function main_2()
    while true do
        local crop = geolyzer.crop(sides.front)
        local Name = get_crop_name(crop)
		--如果是作物架就等几秒
        if Name == "IC2:blockCrop" then
            os.sleep(SleepTime)
        elseif string.lower(Name) == target_crop_name then
            MaxSizeOfSeed = get_crop_max_size(crop)
            middle_crop_growth, middle_crop_gain, middle_crop_resistance = middle_crop(crop)
            local parent_side = l_or_r()
            if should_discard_middle_crop() then
                break_front_crop()
                place_crop_sticks()
                inventory_controller.equip()
                robot.use()
                inventory_controller.equip()
                failure()
                drop_slots_3_to_5_up()
                print("作物属性不满足条件")
                --是否换掉作物架
            elseif get_crop_current_size(crop) == MaxSizeOfSeed then
                break_front_crop()
                if robot.space(3) == 64 then
                    failure()
                elseif parent_side == "right" then
                    print("成功", "Gr=", middle_crop_growth, "Ga=", middle_crop_gain, "Re=", middle_crop_resistance)
                    replace_right_parent_crop()
                    Rgr = middle_crop_growth
                    Rga = middle_crop_gain
                    Rre = middle_crop_resistance
                    success()
                else
                    print("成功", "Gr=", middle_crop_growth, "Ga=", middle_crop_gain, "Re=", middle_crop_resistance)
                    replace_left_parent_crop()
                    Lgr = middle_crop_growth
                    Lga = middle_crop_gain
                    Lre = middle_crop_resistance
                    success()
                end

                drop_slots_3_to_5_up()
                drop_up_crop()
                place_crop_sticks()
                inventory_controller.equip()
                robot.use()
                inventory_controller.equip()
                --收获新种子
            else
                os.sleep(SleepTime)
                --还没长好就等
            end
            --如果是特定种子
        else
            failure()
            drop_slots_3_to_5_up()
            break_front_crop()
            place_crop_sticks()
            inventory_controller.equip()
            robot.use()
            inventory_controller.equip()
        end
        --如果是杂草就除掉
        replenish_crop_sticks_if_needed()
    end
end

-- 模式 1：持续按白名单（子模式 1）或指定品种（子模式 2）筛选中央作物，不比较三围。
-- 合格作物成熟后收获，按 3 号槽剩余容量统计成败、清理物品并重建杂交架；不替换左右亲本。
-- 不合格作物直接清除并重建杂交架，且仅在此分支检查作物架补给；正常工作时不返回主菜单。
function main_1()
    while true do
        local Analyze = geolyzer.analyze(sides.front)

        local Name = get_crop_name(Analyze)
		--如果是作物架就等几秒
        if Name == "IC2:blockCrop" then
            os.sleep(SleepTime)
        elseif choiceChildMode == 1 then
            if if_is_white_list_seed(Name) then
                --print("是特定作物")
                MaxSizeOfSeed = get_crop_max_size(Analyze)
                --是否换掉作物架
                if get_crop_current_size(Analyze) == MaxSizeOfSeed then
                    break_front_crop()
                    if robot.space(3) == 64 then
                        failure()
                    else
                        success()
                    end

                    drop_slots_3_to_5_up()
                    drop_up_crop()
                    place_crop_sticks()
                    inventory_controller.equip()
                    robot.use()
                    inventory_controller.equip()
                    --收获新种子
                else
                    os.sleep(SleepTime)
                    --还没长好就等
                end
            else
                failure()
                print(Name)
                drop_slots_3_to_5_up()
                break_front_crop()
                place_crop_sticks()
                inventory_controller.equip()
                robot.use()
                inventory_controller.equip()
                --如果是杂草就除掉
                replenish_crop_sticks_if_needed()
                --如果是特定种子
            end
        elseif choiceChildMode == 2 then
            if string.lower(Name) == target_crop_name then
                --print("是特定作物")
                MaxSizeOfSeed = get_crop_max_size(Analyze)
                --是否换掉作物架
                if get_crop_current_size(Analyze) == MaxSizeOfSeed then
                    break_front_crop()
                    if robot.space(3) == 64 then
                        failure()
                    else
                        success()
                    end

                    drop_slots_3_to_5_up()
                    drop_up_crop()
                    place_crop_sticks()
                    inventory_controller.equip()
                    robot.use()
                    inventory_controller.equip()
                    --收获新种子
                else
                    os.sleep(SleepTime)
                    --还没长好就等
                end
            else
                failure()
                print(Name)
                drop_slots_3_to_5_up()
                break_front_crop()
                place_crop_sticks()
                inventory_controller.equip()
                robot.use()
                inventory_controller.equip()
                --如果是杂草就除掉
                replenish_crop_sticks_if_needed()
                --如果是特定种子
            end
        end
    end
end

-- 模式 3：持续清除品种 A、品种 B 和 weed；其他作物等待成熟后收获，不比较三围或替换亲本。
-- 按 3 号槽剩余容量统计收获成败，清理物品并重建杂交架，每轮检查作物架补给。
-- 内部为无限循环，正常工作时不会返回主菜单。
function main_3()
    while true do
        local Analyze = geolyzer.analyze(sides.front)

        Name = get_crop_name(Analyze)
        --print(Name)
        if Name == "IC2:blockCrop" then
            os.sleep(SleepTime)
            --如果是作物架就等几秒
        elseif string.lower(Name) ~= target_crop_nameA and string.lower(Name) ~= "weed" and string.lower(Name) ~= target_crop_nameB then
            --print("是特定作物")
            MaxSizeOfSeed = get_crop_max_size(Analyze)
            --是否换掉作物架
            if get_crop_current_size(Analyze) == MaxSizeOfSeed then
                break_front_crop()
                if robot.space(3) == 64 then
                    failure()
                else
                    success()
                end
                drop_slots_3_to_5_up()
                drop_up_crop()
                place_crop_sticks()
                inventory_controller.equip()
                robot.use()
                inventory_controller.equip()
                --收获新种子
            else
                os.sleep(SleepTime)
                --还没长好就等
            end
            --如果是特定种子
        else
            failure()
            drop_slots_3_to_5_up()
            break_front_crop()
            place_crop_sticks()
            inventory_controller.equip()
            robot.use()
            inventory_controller.equip()
        end
        --如果是杂草就除掉
        replenish_crop_sticks_if_needed()
    end
end

-- 将 seedName 转为小写，与 whiteListSeed.lua 中每行原文精确匹配，返回是否命中。
-- 每次调用都重新打开并读取文件；要求文件存在且可读，不会自动转换名单行的大小写或去除空白。
function if_is_white_list_seed(seedName)
    local file = io.open("whiteListSeed.lua", "r")
    for line in file:lines() do
        if string.lower(seedName) == line then
            file:close()
            return true
        end
    end
    file:close()
    return false
end

-- 交互式读取品种名并转为小写，查重后追加到 whiteListSeed.lua；发现重复时直接返回。
-- 正常添加后，可递归调用自身继续添加，或调用 main() 重新进入主菜单。
function add_white_list_mode()
    print("输入要添加的白名单作物并回车")
    local file = io.open("whiteListSeed.lua", "r")
    local found = false
    local weew = io.read("*l")
    local name = string.lower(io.read("*l"))
    if file then
        for line in file:lines() do
            if line == name then
                found = true
                print(line)
                print("有这个东西了!")
                file:close()
                return
            end
        end
        file:close()
    end

    if not found then
        local file = io.open("whiteListSeed.lua", "a")
        file:close()
        local file = io.open("whiteListSeed.lua", "r")
        for line in file:lines() do
            if line == name then
                print(line)
                print("白名单的物品冲突了!")
                file:close()
                return 0
            end
        end
        file:close()
        file = io.open("whiteListSeed.lua", "a")
        if file then
            file:write(name, "\n")
        end
        file:close()
    else
        print("无法打开文件以写入数据")
    end
    print("要继续添加输入1并回车,不添加输入2并回车")
    ifContinueAdd = io.read("*n")
    if ifContinueAdd == 1 then
        add_white_list_mode()
    elseif ifContinueAdd == 2 then
        main()
    end
end

-- 交互式读取待删除品种名并转为小写，通过 copyWhiteListSeed.lua 中转重写白名单，移除所有匹配行。
-- 操作结束后调用 main() 重新进入主菜单；中转文件会保留。
function delete_white_list_mode()
    local file0 = io.open("copyWhiteListSeed.lua", "w")
    local file = io.open("whiteListSeed.lua", "r")
    local reetgfdg = io.read("*l")
    --print(file)
    if file then
        print("输入要删除的白名单作物")
        local name = string.lower(io.read("*l"))
        for line in file:lines() do
            if line ~= name then
                file0:write(line, "\n")
                --print(name,line)
            end
            if line == name then
            end
        end
        --先复制保存的信息,并不复制要删除的东西
        file0:close()
        file:close()
        file0 = io.open("copyWhiteListSeed.lua", "r")
        os.remove("whiteListSeed.lua")
        if file0 then
            file = io.open("whiteListSeed.lua", "w")
            if file then
                local writeFile0 = file0:read("*a")
                file:write(writeFile0)
                file:close()
                file0:close()
            else
                print("无法打开新文件")
            end
        else
            print("无法打开拷贝文件")
        end
    else
        print("未找到文件")
    end
    main()
end

-- 逐行显示白名单，每输出 6 行显示页码并等待输入；末尾再次等待输入后调用 main()。
-- 文件不存在时打印提示；不足 6 行的尾页不单独打印页码。
function search_page()
    local CONTINUE = io.read("*l")

    local file = io.open("whiteListSeed.lua", "r")
    local page = 1
    local ifChangePage = 0
    if file then
        for line in file:lines() do
            print(line)
            ifChangePage = ifChangePage + 1
            if ifChangePage == 6 then
                print("第", page, "页")
                page = page + 1
                print("输入任意键并回车继续")
                local CONTINUE = io.read("*l")
                ifChangePage = 0
            end
        end
        file:close()
    else
        print("无目录文件")
    end

    print("输入任意键并回车继续")
    local CONTINUE = io.read("*l")
    main()
end

-- 打印布局说明并读取模式及参数：模式 1/2/3 先调用 beginning()，再进入对应的无限工作循环。
-- 模式 4 调用白名单添加、删除或查看函数；模式 1 缺少白名单文件时递归调用自身。
function main()
    print("--杂交系统,一号栏位放作物架，二号栏位先放点产物，15号栏位放鹤嘴锄，16号栏位放除草剂")
    print("--放产物是为了不让种子跑到二号栏位,面对多种产物的作物会出bug")
    print("--下面放作物架,上面放容器存储种子,左下↙和右下↘放杀虫剂,前面三格左右两格放作物架以及初始作物,中间放杂交架,后面放充电器")
    print("--使用前先给两端的作物喷上杀虫剂更好")

    print("选择杂交模式,输入1则无视gr、ga、re值，只选择杂交出白名单的作物或特定作物,输入2则正常按照gr、ga、re值杂交,输入3则杂交出非输入的作物，输入4则进入白名单模式")
    ChangeMode = io.read("*n")

    if (ChangeMode == 1) then
        local CONTIUE = io.read("*l")
        print("输入1则只杂交出白名单的作物，输入2则只杂交出特定作物")
        choiceChildMode = io.read("*n")
        if choiceChildMode == 1 then
            local file = io.open("whiteListSeed.lua", "r")
            if not file then
                print("无白名单文件")
                main()
            end
        elseif choiceChildMode == 2 then
            print("输入特定作物")
            local CONTIUE = io.read("*l")
            target_crop_name = string.lower(io.read("*l"))
        end

        print("输入等待时间(秒),太长可能会长杂草或收获别的作物,太短会增加耗电量,EV世界加速器建议2~4")
        SleepTime = io.read("*n")
        print("失败时是否打印次数?(输入1则打印,输入2则不打印)")
        IfPrintFailTimes = io.read("*n")
        beginning()
        main_1()
    end

    if (ChangeMode == 2) then
        gsfsds = io.read("*l")
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
        middle_crop_growth = (Lgr + Rgr) / 2
        middle_crop_gain = (Lga + Rga) / 2
        middle_crop_resistance = (Lre + Rre) / 2
        beginning()
        main_2()
    end

    if (ChangeMode == 3) then
        dsada = io.read("*l")
        print("输入不想杂交的作物名称A:")
        target_crop_nameA = string.lower(io.read("*l"))
        print(target_crop_nameA)
        print("输入不想杂交的作物名称B:")
        target_crop_nameB = string.lower(io.read("*l"))
        --print("作物能收获种子的生长阶段:")
        --MaxSizeOfSeed = io.read("*n")
        print("输入等待时间(秒),太长可能会长杂草或收获别的作物,太短会增加耗电量,EV世界加速器建议2~4")
        SleepTime = io.read("*n")
        print("失败时是否打印次数?(输入1则打印,输入2则不打印)")
        IfPrintFailTimes = io.read("*n")
        beginning()
        main_3()
    end

    if (ChangeMode == 4) then
        print("输入模式,1为添加,2为删除,3为显示白名单作物列表")
        local choiceMode = io.read("*n")
        if choiceMode == 1 then
            add_white_list_mode()
        elseif choiceMode == 2 then
            delete_white_list_mode()
        elseif choiceMode == 3 then
            search_page()
        end
    end
end

-- 程序入口
main()
