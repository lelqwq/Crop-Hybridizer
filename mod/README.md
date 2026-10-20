# crop_helper

服务端辅助模组：监听 OpenComputers 的 `GeolyzerEvent.Analyze`，为
`geolyzer.analyze(side, options)` 提供 IC2 作物目录与杂交权重查询。

当前实现设计文档第 7 节阶段 1、2，并提供阶段 4 的现场检查初版：

- `info`：模组版本、支持操作、规则指纹、目录是否就绪
- `catalog`：分页作物目录
- `crop`：单个品种的固有信息
- `predict`：双亲本对全部候选的整数权重与条件相对概率
- `site`：原教程布局的当前工位检查，支持核对计划亲本与一个候选品种

当前版本为 **0.3.0**。工位前置检查已全部实机通过；新增中央实际取种条件查询，配合 OC 单次拔除和入库核验，待实机验证。亲本部署和链式自动执行仍未实现。

## 构建

需要 JDK 25（GTNHGradle 2.x 的模块要求）；GTNHGradle 会自行下载 Minecraft/Forge 依赖。
如果 `JAVA_HOME` 仍指向 21，构建前显式指定：

Git Bash / Linux / macOS：

```bash
cd mod
JAVA_HOME="C:/Program Files/Java/jdk-25.0.3" ./gradlew build
```

PowerShell：

```powershell
cd mod
$env:JAVA_HOME = "C:\Program Files\Java\jdk-25.0.3"
.\gradlew.bat build
```

产物在 `build/libs/`（仓库根目录下为 `mod/build/libs/`），本版为 `crop-helper-0.3.0.jar`。

## 安装

- 停服后，用 `crop-helper-0.3.0.jar` 替换服务器 `mods/` 中的旧版，再启动服务器。该目录只保留一个版本，不安装 `-dev.jar` 或 `-sources.jar`。
- 运行时依赖 IC2 2.2.828-experimental 与 OpenComputers 1.11.20-GTNH。
- 模组声明 `acceptableRemoteVersions = "*"`，客户端无需安装。
- 查询消耗普通 geolyzer 扫描能量，受 `allowItemStackInspection` 配置限制。

## 协议 v1

请求通过 `geolyzer.analyze(side, options)` 的第二个参数传入：

```lua
local scan, reason = geolyzer.analyze(sides.front, {
    crop_helper = "catalog",
    protocol = 1,
    offset = 0,
    limit = 64,
})
local reply = scan and scan.crop_helper
```

`reply` 的公共字段：`ok`、`protocol`、`rules_fingerprint`；失败时还有 `error`、`detail`。
具体操作：

- `info`：`mod_version`、`operations`、`catalog_size`
- `catalog`：`offset`、`limit` → `crops`、`total`、`next_offset`
- `crop`：`species_id` → `crop`
- `predict`：`parent_a`、`parent_b`、`offset`、`limit` → `candidates`、`total`、`total_weight`、`next_offset`
- `site`：可选 `parent_a`、`parent_b`、`candidate` → `site` 工位报告；两份亲本参数必须同时提供，均使用完整品种 ID

品种字段：`species_id`（`owner:name`）、`owner`、`name`、`display_name`、`tier`、
`stats`（按 IC2 `stat(0..4)` 顺序排列；在 Lua 表中下标为 1..5）、`attributes`、`max_size`。
`predict` 的候选按权重降序、同权重按 `species_id` 升序排列；`total_weight` 是完整候选集合
的权重和，`probability = weight / total_weight`。

错误码：`unsupported_protocol`、`unsupported_operation`、`unknown_crop`、
`invalid_argument`、`registry_not_ready`、`query_failed`、`site_unavailable`。
注册表尚未就绪或为空时，所有操作（包括 `info`）都返回 `registry_not_ready`。
目录快照按 CropCard 对象身份签名校验；运行时同名重注册会使缓存失效，注册后原地修改
`CropCard` 字段不属于支持范围。

## 验证

把 `oc/crop_helper_diag.lua` 复制到 OC 电脑或机器人，运行：

```bash
crop_helper_diag.lua info
crop_helper_diag.lua catalog wheat
crop_helper_diag.lua crop IC2:wheat
crop_helper_diag.lua predict IC2:wheat IC2:wheat 5 0
crop_helper_diag.lua scan
crop_helper_diag.lua site
```

先确认 `catalog wheat` 输出包含 `IC2:wheat`，再执行单品种和预测查询；若服务器修改了注册表，使用目录实际返回的完整 `species_id`，包括大小写。也可运行不带过滤文本的 `catalog` 查看完整目录。

`catalog` 的过滤文本只匹配品种 ID 和显示名，不搜索产物。匹配 0 个表示没有匹配项；使用未注册的品种 ID 会返回 `unknown_crop`，应先从目录确认 ID。

实机已确认 `info`、目录与小麦预测查询能够返回结果。预测值是忽略工位环境、两个亲本均已参与时的条件相对概率，不能作为现场每次杂交的成功率。普通扫描可用 `crop_helper_diag.lua scan` 对比。

## 终端查看

直接在终端运行时，诊断脚本通过 OpenOS 自带的 `less` 查看输出：↑/↓ 滚动一行，PageUp/PageDown 或空格翻页，Home/End 跳到首尾，Q 或 Ctrl+C 退出。到达末尾后仍可向上回看。

`predict` 的可选参数为 `[limit] [offset]`：交互查看时，`limit` 是每次查询的候选数，`offset` 是起始位置，继续向下查看会自动获取后续候选，不必重新输入命令。每个候选先显示品种 ID，再显示权重和概率；目录字段分行显示，规则指纹每行显示 32 个字符。

重定向到文件或管道时不启动交互查看器，保留原来的单页预测输出和下一页 `offset` 提示。例如 `crop_helper_diag.lua predict IC2:wheat IC2:wheat 5 0 > prediction.txt`。

终端显示使用 OpenOS 自带的 `less`。新增 `site` 操作还需要服务器升级到 0.2.0，并将 `oc/lib/crop_site.lua` 安装到 OC 的 `/home/lib/crop_site.lua`；同时更新诊断脚本。

## 工位检查

机器人保持教程中央待机位，面向中央杂交架，无需移动或更换设备：

```sh
crop_helper_diag.lua site
crop_helper_diag.lua site IC2:wheat IC2:wheat IC2:coffee
```

第一条检查当前左右亲本；第二条还核对计划亲本是否匹配，以及候选在中央位的条件和正权重。左右顺序可以互换。若要核对规划路线首步，使用 `crop_plan.lua check IC2:coffee 2`，详见 [oc/README.md](../oc/README.md)。

`site` 请求不接受远程坐标，仅检查扫描点、机器人位置及中央位四邻，不强制加载区块。报告包含 `center`、`left`、`right`、`checks`、`status` 和 `ready_for_crossing`；每项检查状态为 `pass`、`blocked` 或 `unknown`，只在全部通过时就绪。

检查内容：三格作物架、中央空位及双层架、计划亲本匹配、额外相邻作物、亲本对中央位的 `canGrow` 与自身的 `canCross`，以及可选候选的 `canGrow` 和理论权重。中心已有作物时报告未通过，不会清空它。

0.2.1 修复 GT 发行版本识别：主模组 `gregtech` 声明 `MC1710` 时，读取同一 JAR 的 `gregtech_nh` 版本 `5.09.51.482`，并将其纳入规则指纹。`gregtech:Brown Mushrooms` 使用已审核的 `GTBaseCrop`；不应因主模组版本占位值而返回未知。未知结果现显示具体原因，其他版本仍保持未知。

当前已审核 IC2 2.2.828 基础作物的精确类，以及 GT5u 5.09.51.482 的 `GTBaseCrop`。其他类、版本变化、缺失环境缓存或需要未支持信息的判断返回 `unknown`。条件通过只说明当前杂交前置条件满足，不代表整条路线可执行。

调用发生在记录的服务端 tick 线程；作物卡只获得只读快照，无法通过该接口取得真实 World/TileEntity 或调用写入方法。`automation_ready=false`、`distribution_complete=false`：不返回完整环境过滤概率，也不执行真实杂交。0.3.0 增加当前中央作物的取种条件检查，见下节；不预测未来作物成熟。

### 0.3.0：中央单次取种条件

`site` 增加 `dimension`、`collection = {name, status, detail}`、`ready_for_collection`、`seed_drop_guaranteed=false`。`harvest_status` 为当前中央取种检查状态。此检查与“空中央位的杂交前置条件”分别报告：中央已有成熟作物时，旧 `status` 会因非空而未通过，但 `ready_for_collection` 可为 true。`automation_ready` 仍为 false，不能用单株取种就绪授权整条链。

严格限制到已审核取种路径的精确类与原有版本：GT `GTBaseCrop`，IC2 `CropCoffee`、`CropBrownMushroom`、`CropWheat`。在只读快照上调用实际 `canBeHarvested()`；小麦三围全不超过1时返回 `vanilla_wheat_seeds_only`。其余类返回 `unreviewed_seed_collection`，未成熟为 `not_harvestable_yet`，无中央作物为 `no_center_crop`。不调用 `pick`、`harvest`、`getSeeds` 或任何随机掉落函数试算；实际动作仍由 OC 机器人完成。

已核对实装 IC2 的 `pick` 路径：先收获产物，再随机产生最多两份种子并重置作物。GT 通用类及这里支持的 IC2 类不会改写该路径；小麦可能输出普通种子的分支单独阻止。完整分析仍依赖既有 geolyzer 的分析等级设置；实际掉落缺少可验证元数据时，OC 保留物品并停止入库。该工具不保证首次发现的植株必然保住种子。
