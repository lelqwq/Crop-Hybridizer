# Crop-Hybridizer

GTNH 2.8.4（旧 IC2 作物系统）的定向杂交工具。

## 目录

| 路径 | 内容 |
|---|---|
| `crop_hybridizer.lua` | 现有 OC 机器人脚本：模式 1 收获指定品种，模式 2 按三围培育 |
| `IC2_CHAIN_BREEDING_PLAN.md` | 定向链式杂交详细设计 |
| `mod/` | 服务端辅助模组 `crop_helper`，为 `geolyzer.analyze` 提供作物目录与杂交权重 |
| `oc/crop_helper_diag.lua` | OC 诊断脚本，支持终端滚动查看和预测结果自动续页 |
| `oc/crop_plan.lua`、`oc/lib/` | 沿用教程布局，盘点上方种子箱、预演路线并核对当前工位 |
| `oc/crop_collect.lua` | 中央作物观察、单次取种、固定双亲本持续杂交与入库核验 |
| `oc/tests/` | 输出排版、交互查看、种子识别与路线预演的离线测试 |
| `update-oc.cmd`、`tools/Update-OcScripts.ps1` | Windows 一键上传 OC 脚本，交互输入 SSH 密码，校验、备份与失败回滚 |

## Windows 一键更新机器人脚本

1. 在游戏中先关闭机器人电源，避免旧程序运行期间替换共享库。
2. 在这台 Windows 电脑上双击项目根目录的 **`update-oc.cmd`**。
3. 按 SSH 提示输入服务器 root 密码（输入时不显示字符）。首次连接需核对服务器主机指纹；脚本不读取或保存密码。
4. 窗口显示 `[OK] Updated ... scripts` 后，重新启动游戏中的机器人，再运行所需命令。失败时窗口会保留错误信息。

默认连接 `root@160.202.47.74:22`，更新到：

```text
/root/GTNH_server/World/opencomputers/bcf373d0-1809-4659-9cae-75d28b2b3ad0/home
```

每次自动打包本地 `oc/*.lua` 和 `oc/lib/*.lua`，目前共7个运行文件；不需要逐个选择或修改上传列表。使用一次 SSH 连接完成传输、备份、安装及 SHA-256 校验。只替换这些程序文件，保留 `crop_collect.journal`、`crop_auto.journal` 和其他远程文件；不更新服务器模组 JAR。

旧脚本备份在服务器 **OC 文件系统之外**，不会占用机器人硬盘容量：

```text
/root/GTNH_server/oc-script-backups/bcf373d0-1809-4659-9cae-75d28b2b3ad0/<UTC时间-编号>/
```

备份中的 `files/` 保存原文件，`existing.txt`、`added.txt` 记录替换与新增列表，`installed.sha256` 保存更新后的文件哈希。远程校验失败会停止；安装失败会尝试恢复已改动文件，备份始终保留。更新完成后要重启机器人，已加载的旧程序不会因上传自动切换版本。

本机使用 Windows PowerShell、OpenSSH 客户端和 `tar.exe`（本电脑已检测到）。密码认证由 SSH 自己处理；已配置可用 SSH 密钥时无需输入密码。不需要额外安装上传软件，也不修改系统的永久执行策略。

可先只做本地打包检查，不连接服务器：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Update-OcScripts.ps1 -CheckOnly
```

SSH 端口不同可使用 `update-oc.cmd -Port 2222`；脚本参数也支持 `ServerAddress`、`UserName`、`RemoteHome`、`BackupRoot`。离线安装及回滚测试使用模拟目录，不连接真实服务器：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\tests\Update-OcScripts.Tests.ps1
```

## 当前进度

已实现设计文档第 7 节的阶段 1、2：

- `crop_helper` 模组的 `info`、`catalog`、`crop`、`predict` 操作（协议 v1）
- OC 诊断脚本，以及适用于低分辨率屏幕的分行输出和 `less` 交互查看
- 权重、参数解析、目录排序与规则指纹的离线单元测试

阶段 3 已提供只读初版：上方种子箱盘点、目标品种及数量输入、带库存保护和搜索预算的候选路线预演。沿用[现有教程布局](https://gtnh.huijiwiki.com/wiki/%E4%BD%BF%E7%94%A8OC%E6%9C%BA%E5%99%A8%E4%BA%BA%E8%BF%9B%E8%A1%8CIC%E6%9D%82%E4%BA%A4%E8%87%AA%E5%8A%A8%E5%8C%96)，不增加设备或调整农场。

阶段 4 已提供工位检查初版：辅助模组 0.2.0 新增 `site` 操作，核对当前杂交架、实际亲本和候选条件。布局和亲本条件已实机通过；0.2.1 修复 GT 主模组版本声明导致候选误报未知，并显示未知原因。当前工位的全部前置检查已实机通过。0.3.0 新增中央单次取种和逐份入库核验，待实机验证；固定双亲本的持续循环已加入 `auto`（待实机验证），可自动清除非目标、补架、补给、保存掉落物，直到目标库存达标；自动换亲本与链式执行仍未实现。

实机已确认模组通信、目录查询、库存盘点和多步路线预演可用；工位前置检查已全部实机通过；新增单次取种尚待实机验证。

## 种子盘点与路线预演

将 `oc/crop_plan.lua` 放到 OC 的 `/home/crop_plan.lua`，将 `oc/lib/crop_preview.lua`、`oc/lib/crop_site.lua` 放到 `/home/lib/`。机器人位于原布局中央，面向中央杂交架，种子放在上方容器中。

```sh
crop_plan.lua inventory
crop_plan.lua plan IC2:coffee 2
crop_plan.lua check IC2:coffee 2
```

程序只读盘点和展示路线，不移动机器人或物品。未识别种子不参与规划，左右已种活体暂不计入种子资源。`check` 额外将路线首步与当前工位核对，需要服务器升级至 `crop-helper-0.3.0.jar`。通过不代表后续成熟取种可靠；未支持的特殊条件明确报告未知。安装与检查说明见 [oc/README.md](oc/README.md)。

## 固定亲本持续自动杂交

在已有0.3.0模组和共享库基础上，更新 `/home/crop_collect.lua`、`/home/lib/crop_collect.lua`，新增 `/home/lib/crop_auto.lua`。保持原布局、停止旧脚本并独占工位、种子箱，清理旧掉落物。下方容器提供作物架，上方种子箱留足空位，非功能背包槽腾空。

```sh
crop_collect.lua auto "gregtech:Brown Mushrooms" 2 5
crop_collect.lua auto_status
```

参数为目标品种、箱内目标种子总数（默认1）、扫描间隔秒（默认5）。非目标作物立即清除、掉落种子和副产物入箱，回收作物架并恢复中央双层架，继续杂交。目标出现后等待可取种再保存；未掉种子继续重试。以箱内实际识别数量达标为结束条件，不按出现次数计成功。左右亲本保持原位，Ctrl+C停止；箱满、补给不足或未核对动作会暂停并保留记录。详情见 [oc/README.md](oc/README.md)。

**非目标幼苗会直接清除，不保证留下种子。** 本命令用于当前固定亲本刷一个目标品种；自动部署整条路线尚未接入。

## 单次取种验证（0.3.0）

保持原布局并停止旧杂交脚本。服务器安装 `crop-helper-0.3.0.jar`，机器人新增 `/home/crop_collect.lua`、`/home/lib/crop_collect.lua`，同时更新 `/home/lib/crop_preview.lua` 和 `/home/lib/crop_site.lua`。

```sh
crop_collect.lua inspect
crop_collect.lua wait "gregtech:Brown Mushrooms" 5
crop_collect.lua collect "gregtech:Brown Mushrooms"
crop_collect.lua status
```

可以直接运行 `wait`，默认每5秒扫描一次，目标出现后等待到可取种并自动执行一次取种入库；完成一株后退出。若出现其他品种或工位条件变化，保留现场并停止。`inspect` 只观察一次，`collect` 用于已经可取种的目标。该命令实际拔除中央一株，种子掉落有随机性；先腾空背包非功能槽，并在上方种子箱留至少2个空槽。首版支持 GT 通用作物，以及 IC2 咖啡、棕色蘑菇和符合种子袋条件的小麦。异常时保留现场和批次记录，不自动重放动作；不补架、不换亲本、不清理其他品种。详见 [oc/README.md](oc/README.md)。

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

仅更新排版可替换 Lua 脚本；新增 `site` 工位检查需要服务端 0.2.0 和 `/home/lib/crop_site.lua`。模组构建、升级及协议说明见 [mod/README.md](mod/README.md)。

## 离线测试

在项目根目录使用 Lua 5.2 或兼容运行时分别执行：

```sh
lua oc/tests/terminal_output_test.lua
lua oc/tests/pager_test.lua
lua oc/tests/crop_preview_test.lua
lua oc/tests/crop_plan_test.lua
lua oc/tests/crop_site_test.lua
lua oc/tests/crop_collect_test.lua
lua oc/tests/crop_wait_test.lua
lua oc/tests/crop_auto_test.lua
```

测试模拟组件与查看器管道，覆盖 50 列排版、自动续页、提前退出、重定向、规则指纹变化和异常分页，单次取种测试使用模拟机器人验证故障停机、装备恢复、种子批次和入库回执；等待及自动循环测试覆盖空架、目标生长、非目标、零掉种、补架、回收补给、箱满、失败和中断，不操作游戏世界。
