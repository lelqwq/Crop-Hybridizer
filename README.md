# Crop-Hybridizer

GTNH 2.8.4（旧 IC2 作物系统）的定向杂交工具。

## 目录

| 路径 | 内容 |
|---|---|
| `crop_hybridizer.lua` | 现有 OC 机器人脚本：模式 1 收获指定品种，模式 2 按三围培育 |
| `IC2_CHAIN_BREEDING_PLAN.md` | 定向链式杂交详细设计 |
| `mod/` | 服务端辅助模组 `crop_helper`，为 `geolyzer.analyze` 提供作物目录与杂交权重 |
| `oc/crop_helper_diag.lua` | OC 诊断脚本，支持终端滚动查看和预测结果自动续页 |
| `oc/tests/` | 输出排版、交互续页和退出行为的离线模拟测试 |

## 当前进度

已实现设计文档第 7 节的阶段 1、2：

- `crop_helper` 模组的 `info`、`catalog`、`crop`、`predict` 操作（协议 v1）
- OC 诊断脚本，以及适用于低分辨率屏幕的分行输出和 `less` 交互查看
- 权重、参数解析、目录排序与规则指纹的离线单元测试

`site`（真实工位环境检查）以及 OC 侧的盘点、规划和执行模块尚未实现。
实机已确认模组通信、作物目录和预测查询可用；新增交互查看功能已通过离线模拟测试，尚未实机复验。

## 诊断脚本使用

将 [oc/crop_helper_diag.lua](oc/crop_helper_diag.lua) 复制到机器人或 OC 电脑，在已安装辅助模组的服务器运行：

```sh
crop_helper_diag.lua info
crop_helper_diag.lua catalog wheat
crop_helper_diag.lua crop IC2:wheat
crop_helper_diag.lua predict IC2:wheat IC2:wheat 5 0
crop_helper_diag.lua scan
```

先从目录确认完整的品种 ID（区分大小写），再查询详情或预测。直接在终端运行时使用 OpenOS 自带的 `less`：

| 按键 | 操作 |
|---|---|
| ↑ / ↓ | 向上 / 向下滚动一行 |
| PageUp / PageDown | 向上 / 向下翻页；空格也可向下翻页 |
| Home / End | 跳到首尾 |
| Q / Ctrl+C | 退出查看 |

预测参数 `5 0` 表示每次查询 5 个候选、从位置 0 开始；交互查看会按需加载后续候选，到达末尾后仍可回看。重定向到文件或管道时输出普通文本，预测仍按指定参数输出单页，并提示下一页位置。

本次终端显示更新只需替换 Lua 脚本。模组构建、安装及协议说明见 [mod/README.md](mod/README.md)。

## 离线显示测试

在项目根目录使用 Lua 5.2 或兼容运行时分别执行：

```sh
lua oc/tests/terminal_output_test.lua
lua oc/tests/pager_test.lua
```

测试模拟组件与查看器管道，覆盖 50 列排版、自动续页、提前退出、重定向、规则指纹变化和异常分页，不执行机器人动作。
