# crop_helper

服务端辅助模组：监听 OpenComputers 的 `GeolyzerEvent.Analyze`，为
`geolyzer.analyze(side, options)` 提供 IC2 作物目录与杂交权重查询。

当前实现设计文档第 7 节阶段 1、2：

- `info`：模组版本、支持操作、规则指纹、目录是否就绪
- `catalog`：分页作物目录
- `crop`：单个品种的固有信息
- `predict`：双亲本对全部候选的整数权重与条件相对概率

`site`（真实工位环境检查）尚未实现。

## 构建

需要 JDK 25（GTNHGradle 2.x 的模块要求）；GTNHGradle 会自行下载 Minecraft/Forge 依赖。
如果 `JAVA_HOME` 仍指向 21，构建前显式指定：

Git Bash / Linux / macOS：

```bash
cd mod
JAVA_HOME="C:/Program Files/Java/jdk-25.0.4" ./gradlew build
```

PowerShell：

```powershell
cd mod
$env:JAVA_HOME = "C:\Program Files\Java\jdk-25.0.4"
.\gradlew.bat build
```

产物在 `build/libs/`（仓库根目录下为 `mod/build/libs/`），通常为 `crop-helper-0.1.0.jar`。

## 安装

- 放入 GTNH 服务器的 `mods/` 目录；安装 `crop-helper-0.1.0.jar`，不要安装 `-dev.jar`。
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

品种字段：`species_id`（`owner:name`）、`owner`、`name`、`display_name`、`tier`、
`stats`（按 IC2 `stat(0..4)` 顺序排列；在 Lua 表中下标为 1..5）、`attributes`、`max_size`。
`predict` 的候选按权重降序、同权重按 `species_id` 升序排列；`total_weight` 是完整候选集合
的权重和，`probability = weight / total_weight`。

错误码：`unsupported_protocol`、`unsupported_operation`、`unknown_crop`、
`invalid_argument`、`registry_not_ready`、`query_failed`。
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
```

先确认 `catalog wheat` 输出包含 `IC2:wheat`，再执行单品种和预测查询；若服务器修改了注册表，使用目录实际返回的完整 `species_id`，包括大小写。也可运行不带过滤文本的 `catalog` 查看完整目录。

`catalog` 的过滤文本只匹配品种 ID 和显示名，不搜索产物。匹配 0 个表示没有匹配项；使用未注册的品种 ID 会返回 `unknown_crop`，应先从目录确认 ID。

实机已确认 `info`、目录与小麦预测查询能够返回结果。预测值是忽略工位环境、两个亲本均已参与时的条件相对概率，不能作为现场每次杂交的成功率。普通扫描可用 `crop_helper_diag.lua scan` 对比。

## 终端查看

直接在终端运行时，诊断脚本通过 OpenOS 自带的 `less` 查看输出：↑/↓ 滚动一行，PageUp/PageDown 或空格翻页，Home/End 跳到首尾，Q 或 Ctrl+C 退出。到达末尾后仍可向上回看。

`predict` 的可选参数为 `[limit] [offset]`：交互查看时，`limit` 是每次查询的候选数，`offset` 是起始位置，继续向下查看会自动获取后续候选，不必重新输入命令。每个候选先显示品种 ID，再显示权重和概率；目录字段分行显示，规则指纹每行显示 32 个字符。

重定向到文件或管道时不启动交互查看器，保留原来的单页预测输出和下一页 `offset` 提示。例如 `crop_helper_diag.lua predict IC2:wheat IC2:wheat 5 0 > prediction.txt`。

终端显示功能仅需更新 `oc/crop_helper_diag.lua`，使用 OpenOS 自带的 `less`；已有服务端模组不需要重新构建。新增交互查看及退出行为已通过离线模拟测试，尚未实机复验。
