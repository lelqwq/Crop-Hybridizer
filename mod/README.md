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
crop_helper_diag.lua catalog rubber
crop_helper_diag.lua predict IC2:rubber IC2:rubber 32 0
crop_helper_diag.lua scan
```

`predict` 的可选参数为 `[limit] [offset]`，可用它验证服务端分页。
`info` 能返回版本与指纹、`catalog` 能列出品种、`predict` 能给出权重，即表示阶段 1、2 的通信与目录接口打通。
普通 `geolyzer.analyze(side)` 不应受本模组影响，可用 `crop_helper_diag.lua scan` 对比。
