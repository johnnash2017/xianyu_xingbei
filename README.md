原工程地址：https://github.com/chntujia/CodfiyAsteriatedGrailServer/

这是通过修改原版网杯的开源工程，进行二次开发的游戏版本。

1.新增了斩击特效

2.改善了技能释放交互

3.提升了界面提示性，以让玩家清楚当前发生了什么事

4.提供了Steam联机功能（还没上线，正在审核）以防止被黑客攻击

5.将角色技能更新至 10 周年版本，目前仅开发至基础角色，后面将陆续更新新角色


# 杂鱼星杯 · 项目说明

> 本文整合开发沟通中的关键信息，作为项目的总入口说明。
> 细节另见工程上层目录的 [多开与局域网实现说明.md](../多开与局域网实现说明.md) 与 [Steam迁移完成度.md](../Steam迁移完成度.md)。

---

## 一、项目定位

- 游戏名：**星杯传说**（Godot 4.7 工程，工程目录 `xianyu_xingbei`）。
- 性质：基于原版"网杯"开源工程二次开发的游戏版本。原工程：
  `https://github.com/chntujia/CodfiyAsteriatedGrailServer/`
  （仓库内保留了两份原版参考源码：`CodfiyAsteriatedGrailClient-master`、`CodfiyAsteriatedGrailServer-master`）
- 相对原版的改动：新增斩击特效、改善技能释放交互、增强界面提示；角色技能更新到 **10 周年版本**（先做基础角色，后续陆续补新角色）；加入 **Steam 联机**能力（替代公网服务器，防止被黑客攻击）。
- 联机拓扑：**去中心化的房主模式** —— 谁建房谁的本机进程跑权威服务端，其余人连他的地址。

### 技术栈与编码风格

- 引擎：Godot **4.7**（Forward+）；渲染驱动不指定（走引擎默认的 Vulkan —— 编辑器运行与导出包必须同一个驱动，否则同一个特效两边观感会不一样），物理引擎 `Jolt Physics`；设计分辨率 1920×1080，`canvas_items` 拉伸。
- 语言：**GDScript**，全部显式类型声明（不用 `:=`）；变量/函数/文件名大量使用**中文命名**（作者自述"用中文编码""看着会很异端"），这是本项目的既定风格。
- 协议：`protobuf` 线格式解析 + `Framing` 分帧 + `ProtoCodec`，线格式沿用旧服务端，协议号见 [proto_schema.gd](scripts/core/proto_schema.gd)。

---

## 二、编辑器插件"全家桶"

项目自带以下编辑器插件（`addons/`），在 [project.godot](project.godot) 的 `editor_plugins/enabled` 中启用：

| 插件 | 目录 | 作用 |
| --- | --- | --- |
| **Excel 转数据表工具** | `addons/excel_to_gd` | 把 `设计表.xlsx` 转成代码可读的数据文件（详见第三节） |
| **GD 文件别名显示** | `addons/gd_alias` | 在文件系统面板 / 脚本列表里为文件 / 文件夹显示**自定义别名（可中文）**，实际文件名不变；别名存 `alias_data.json` |
| **ResDsp** | `addons/resdsp` | 让 Godot **不把 CSV 当作语言文件解析**，并支持在编辑器里**双击用系统默认程序打开 CSV / xlsx** |
| godotsteam | `addons/godotsteam` | Steam 接入（GodotSteam 4.23.1，camelCase 接口） |
| label_font_auto_sizer | `addons/label_font_auto_sizer` | 字体自适应（辅助用） |

其中前三个是本项目**作者自写**的插件，插件描述里的 author 分别署名"杂鱼""Trae""Johnansh"。

**ResDsp 解决的核心痛点**：把设计表转成 CSV、再由 CSV 转成 GD 的过程中，若不拦截，Godot 会把每个 CSV 当成"语言/翻译文件"处理，结果产生**巨量无意义的语言文件**；该插件把 CSV/xlsx 排除出语言解析，同时让它们能双击打开，导表流程才干净可用。

---

## 三、配置表工作流（导表）

```
Table/Design/设计表.xlsx   ──①Excel→CSV──▶   Table/Csv/*.csv   ──②CSV→GD──▶   Table/TableScripts/DataTables.gd
（人在 Excel 里设计）                         （供人工检查）                    （运行时真正读取的数据表）
```

- **入口**：编辑器顶部工具菜单「**检查并转换表格**」，或快捷键 **`Ctrl + Shift + T`**（组合键）。
- **转换规则**：
  - 只导出 `设计表.xlsx` 中**名称以 `.csv` 结尾的工作表**，其余工作表忽略；导出的 CSV 覆盖写入 `Table/Csv`。
  - `Table/Csv` 下的所有 CSV 再合并生成 [DataTables.gd](Table/TableScripts/DataTables.gd)（`class_name 数据表格`，运行时读取的就是它）。
- **两份产物各有用处**：CSV 是**给人检查**的中间态；`DataTables.gd` 是**自动生成、运行时会读**的最终表（文件头有"请勿手动修改"）。
- 当前的表：`卡表`、`技能表`、`角色表`、`词缀`。
- 实现见 [Run.gd](addons/excel_to_gd/Run.gd)（`ExcelToCsv.gd` → `CsvToGd.gd`）。生成时若 `DataTables.gd` 在编辑器中打开，会先关闭再重开，避免覆盖触发编辑器报错。

---

## 四、两种运行模式

| 模式 | 怎么启动 | 联机底座 | 状态 |
| --- | --- | --- | --- |
| **本地模式** | 由多开脚本拉起（带 `--slot` / `--count` / `--auto`），即按 **F9 / F10 / F11** | 本机当房主的局域网 TCP（[network_client.gd](scripts/net/network_client.gd) / `network_server.gd`） | 可用，测试主力 |
| **Steam 模式** | **裸启动**：编辑器直接点运行按钮、或运行导出包 | `SteamNetworkingMessages` P2P（[steam_net.gd](scripts/net/steam_net.gd)） | **尚未接完**，需对接正确的 SteamAPI 与 AppID 才能正常开房 |

- 模式判定在 [config.gd](scripts/client/config.gd) 的 `Cfg.本地模式`：**带了 `--slot/--count/--auto` 任一 → 本地模式；裸启动 → Steam**（编辑器里裸跑也走 Steam）。
- Steam 侧目前用 **AppID 480**（SpaceWar）验通路；作者预计 Steam 审核通过、正式接完约需十余天。
- 大厅标题栏会显示当前模式，一眼可确认在哪个模式；大厅房间列表 UI 两种模式共用。
- 局域网那条链路**保留不删**（F9~F11 与联调脚本都依赖它），Steam 只是并行的第二条路。

---

## 五、多开测试快捷键（F9 / F10 / F11）

在一台机器上拉起多个客户端窗口，快速验证联机。逻辑全部在 `tests/`（脚本 [启动多开.ps1](tests/启动多开.ps1) / `启动多开.bat`）。

| 快捷键 | 行为 |
| --- | --- |
| **F9** | 打开 4 个测试窗口（本地模式，不自动开局） |
| **F10** | 打开 4 个窗口，并**自动进入同一房间** |
| **F11** | 打开 6 个窗口，并自动进入一个**六人房间** |

- 通过 F9~F11 启动的一律是**本地模式**：脚本会把你当前这个主机当成房间。
- **快捷键需要每人自绑一次**（不随工程走）：右键 `启动多开.bat` → 发送到桌面快捷方式 → 快捷方式属性里设快捷键（F9/F10/F11）；不同数量通过给"目标"追加参数实现，例如 `...启动多开.bat" -Count 6 -Auto`。
- 脚本常用参数：`-Count N`（1~8）、`-Width W`（0＝等比铺满）、`-Names 甲,乙,丙`（批量起昵称，不覆盖已有）、`-Auto`（自动开局）、`-DryRun`（只演算）、`-KeepConsole`（排查用）。
- 反复按快捷键会先关掉上一批（只认带 `--slot=` 的本工程进程），不会越开越多；窗口按屏幕宫格自动摆位（布局参数写在 `%APPDATA%\Godot\app_userdata\星杯传说\`）。
- 引擎找不到时脚本会按序探测（`-EnginePath` → VSCode 设置 → 工程同级 `godot*.exe` → PATH → Steam 常见路径），详见 [多开测试说明.md](tests/多开测试说明.md)。
- 多开与存档隔离、局域网发现的完整设计见 [多开与局域网实现说明.md](../多开与局域网实现说明.md)。

---

## 六、作弊 / 调试模式

- 建房面板有一个勾选项「**开启作弊**」（界面上也叫"调试模式"）。勾上后，**本房间内所有玩家**都能使用测试指令（不是房主特权）。
- **F10 / F11**（`-Auto`）拉起的窗口**默认就开着作弊**，所以拿它们做测试很方便；手动开游戏时默认关闭，只有房主在「创建房间」里勾选才会开。
- 打开后，**战斗界面屏幕左上角会出现一块"牛皮癣"式提示**，告诉你有哪些作弊键位（可拖拽、常驻不消失）。测试指令表定义在 [battle_mobile.gd](scripts/ui/battle_mobile.gd) 的 `测试指令表`；未开调试模式时既不显示提示、也不响应指令（服务端也会再拦一道）。
- 该设置随建房写进大厅数据 / 房间快照下发（键 `debug`），房间列表也会标出来。

---

## 七、目录速览

**本工程根目录（`xianyu_xingbei/`）内：**

- `scenes/` —— 场景（含 `prefabs/ui/` 预制体）。
- `scripts/` —— 脚本：`client/`（配置与客户端逻辑）、`net/`（网络）、`battle/`（战斗）、`data/`、`ui/`、`core/`（分帧/编解码/协议）、`effects/`、`framework/`。
- `assets/` —— 美术、字体、音频等资源。
- `Table/` —— 配置表（`Design/设计表.xlsx`、`Csv/`、`TableScripts/DataTables.gd`）。
- `addons/` —— 编辑器插件（见第二节）。
- `tests/` —— 多开与自检（[多开测试说明.md](tests/多开测试说明.md)）。
