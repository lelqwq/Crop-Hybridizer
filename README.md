# Crop-Hybridizer

GTNH 2.8.4（旧 IC2 作物系统）的定向杂交工具。

## 目录

| 路径 | 内容 |
|---|---|
| `crop_hybridizer.lua` | 现有 OC 机器人脚本：模式 1 收获指定品种，模式 2 按三围培育 |
| `IC2_CHAIN_BREEDING_PLAN.md` | 定向链式杂交详细设计 |
| `mod/` | 服务端辅助模组 `crop_helper`，为 `geolyzer.analyze` 提供作物目录与杂交权重 |
| `oc/crop_helper_diag.lua` | OC 诊断脚本，用于验证模组通信、目录与预测接口 |

## 当前进度

已实现设计文档第 7 节的阶段 1、2：

- `crop_helper` 模组的 `info`、`catalog`、`crop`、`predict` 操作（协议 v1）
- OC 诊断脚本
- 权重、参数解析、目录排序与规则指纹的离线单元测试

`site`（真实工位环境检查）以及 OC 侧的盘点、规划和执行模块尚未实现。
模组构建与服务器验证步骤见 `mod/README.md`。
