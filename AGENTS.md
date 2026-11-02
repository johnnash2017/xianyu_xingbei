# 星杯传说 · 项目说明

> 这份文档写给**第一次打开这个工程的人**。
> 读完它，你应该能回答四个问题：**这是什么、怎么跑起来、代码在哪、想改的东西去哪找。**
>
> 更偏“历史记录 / 开发细节”的内容见 [README.md](README.md)；本文件是**通俗版总览**，两者不冲突。

**快速跳转：** 想跑起来 → 第 2 节；想找代码 → 第 4、12 节；想懂架构 → 第 5~8 节；改表 / 改技能 → 第 8.4、9 节。

---

## 0. 一页纸速览

| 项 | 内容 |
| --- | --- |
| 游戏 | 《星杯传说》，工程内显示名「杂鱼星杯」 |
| 版本 | `1.0.51`（唯一来源：`project.godot` 的 `application/config/version`） |
| 类型 | 多人卡牌对战，当前提供 4 人 / 6 人房 |
| 引擎 | Godot **4.7**（Forward+，Windows 下使用 D3D12） |
| 语言 | **GDScript**（全部显式类型 + 大量中文命名） |
| 规模 | 212 个 `.gd`、约 7.9 万行；54 名可用角色、71 条角色数据、414 条技能、155 张卡 |
| 联机 | **去中心化**：谁建房，谁的电脑就兼任服务器 |
| 数据 | Excel 设计表 → CSV → 自动生成的 GDScript 数据表 |
| 主场景 | `scenes/Main.tscn` |
| 测试 | 62 个 headless 自检用例 + 端到端联机脚本 + F9/F10/F11 一键多开 |

### 0.1 开发协作约定（重要）

- **不要关闭用户手动打开的测试窗口 / Godot 进程。** 包括多开窗口、调试运行窗口、联机测试窗口。
- 自动化检查只跑独立的 headless 进程，不要为了跑检查去结束已有 GUI 进程。
- 需要重启客户端或服务端时，提醒用户自己操作，不要替用户关窗口。
- 如果某条命令可能影响用户已开着的进程，先说明并等确认。
- **没让做的事不要做，想做先问。** 修 bug 就只修这个 bug，不要顺手重构、顺手改文案、顺手删接口 / 配置表 / 兜底逻辑。范围稍大（解耦、迁移、清理“死代码”）时，先在回复里列出「要动哪些现有东西」，等确认后再动。
- **删“看起来没用”的东西之前必须证明它没人用，并说明后果。** 一次真实教训：做额外行动解耦时，顺手删掉了客户端「按技能号给系别兜底」的表和界面里相关兜底，原本显示「额外风系【攻击行动】」的按钮退化成「额外【攻击行动】」，把既有功能搞坏了。结论：**先保证现有行为不变，再谈解耦**；能不动界面就绝不动界面。
- **沟通时尽量不造新词。** 描述一个东西优先用项目里已有的叫法（代码标识符、文档里的名词、界面上的名字），比如「额外行动按钮」「二级技能栏」「额外行动阶段」，不要另起「芯片」这类同义词。确实没有合适的现成词时，先说明它对应代码里的哪个对象，再提出新词。
- **改完就提交，不用等用户催。** 一个改动自检通过就自己 `git commit`：提交信息写清「改了什么、怎么验证的」，需要时顺手把口径补进相关文档（`AGENTS.md` / `项目文档/`）。提交前先 `git status` 看范围，只提交本次改动；工作区里不属于本次的内容（别人的 WIP、临时文件）不要一起带进去。

---

**三句话理解整个工程：**

1. **客户端只负责“显示 + 收集操作”**，真正的规则判定在房主进程里的 `LocalServer` + `BattleEngine`。
2. **所有界面都是主场景 `Main.tscn` 里「界面层」上的一层层子节点**，由 `UI` 单例负责切换；背景只画一次。
3. **一个角色 = 一个 `role_*.gd` 脚本 + 设计表里的一行配置**，靠“钩子”嵌进战斗流程。

---

## 1. 这是什么项目

这是一款**基于开源“网杯”工程二次开发的《星杯传说》联机版**。

- 原工程：<https://github.com/chntujia/CodfiyAsteriatedGrailServer/>
- 本工程在它基础上做了这些事：
  1. 新增斩击、魔弹等出手特效（3D 素材转 2D 呈现）；
  2. 重做技能释放交互与战斗界面提示；
  3. 把角色技能更新到 **10 周年版本**（先做基础角色，再陆续补新角色）；
  4. 加入 **Steam 联机**能力，替代公网服务器，降低被攻击的风险；
  5. 把原来 C++ 服务端 + Unity 客户端的结构，整体移植成 **Godot + GDScript 单工程**。

两份原版参考源码放在**工程上层目录**（不在本仓库内；以下路径相对工程根目录）：

- `../CodfiyAsteriatedGrailClient-master`（原客户端，Unity/C#）
- `../CodfiyAsteriatedGrailServer-master`（原服务端，C++）
- 另有两份开发说明：`../多开与局域网实现说明.md`、`../Steam迁移完成度.md`

**它不是什么：**

- 不是 Unity 工程（虽然参考工程是）；
- 不需要单独部署一台公网服务器；
- 不是“客户端各自算一份结果”的弱联机——规则只在房主进程里算。

---

## 2. 五分钟跑起来

### 2.1 需要准备什么

- **Godot 4.7**（标准编辑器即可）。
- 仓库已经自带 Steam 接入用的 GodotSteam GDExtension（`addons/godotsteam/`，含 Windows/Linux/macOS 二进制），不需要另装。
- 只想本地跑通：**不需要** Steam 账号。
- 想测 Steam 联机：需要本机启动并登录 Steam 客户端。
- 工程当前按 **Windows** 配置（D3D12 + Windows Desktop 导出预设）；换平台需要同时调整渲染驱动与导出预设。

首次打开工程时，Godot 会生成 `.godot/` 缓存并导入资源，耐心等它跑完。

### 2.2 直接按 F5 会发生什么

**裸启动（不带任何参数）走的是 Steam 模式。** 如果本机 Steam 没开，登录界面会停在原地并写出原因（“Steam 初始化失败 / 未登录”），这是正常的，不是崩溃。

> 开发时更推荐下面的“本地模式”，它完全不碰 Steam。

### 2.3 三种推荐跑法

| 场景 | 怎么启动 | 说明 |
| --- | --- | --- |
| **单窗口本地模式** | `godot --path "<工程目录>" -- --slot=0` | 不连 Steam；本机当房主，可正常建房/开局 |
| **一键多开（开发主力）** | 双击 `tests/启动多开.bat`，或执行 `powershell -ExecutionPolicy Bypass -File tests\启动多开.ps1 -Count 4 -Auto` | 自动摆窗口、批量昵称、可选自动开局 |
| **Steam 模式** | 在编辑器直接 F5，或运行导出包，并先登录 Steam | 房间列表走 Steam 大厅，连接走 P2P |

注意 `--slot=0` 前面的 **`--`**：它是 Godot 的“用户参数分隔符”。少了它，`--slot` 会被引擎当成自己的参数而报错。

本地模式判定规则（见 [config.gd](scripts/client/config.gd)）：**带 `--slot` / `--count` / `--auto` 任一，就是本地模式；什么都不带才是 Steam 模式。**

### 2.4 启动参数小抄

| 参数 | 作用 |
| --- | --- |
| `--slot=N` | 槽位 0~7：决定窗口摆位、配置文件、昵称；也是多开脚本识别“自己那批窗口”的标记 |
| `--count=N` | 本批多开窗口数；自动开局时按它挑房间人数 |
| `--auto` | 自动走完“进入游戏 → 建房/进房 → 准备”；同时默认打开调试模式 |
| `--port=N` | 房主服务端口（默认 `11111`） |
| `--lan` | 局域网模式：不自动当房主，先进大厅搜索同一网段的主机 |
| `--nickname=xxx` | 指定昵称（ESC 重启窗口时用来沿用旧身份） |

本地调试模式下按 **ESC** 可以重启当前窗口（仅编辑器环境生效），方便快速换状态。

### 2.5 打包

- 导出配置在 [export_presets.cfg](export_presets.cfg)，当前预设是 **Windows Desktop**。
- 版本号只改 `project.godot` 一处；也可以勾选编辑器插件「版本号工具」，让每次导出自动把末位 +1。
- 想裁剪引擎体积时看 [编译设置.gdbuild](编译设置.gdbuild)（自定义 Godot 构建的 build profile，**不影响**用编辑器运行）。

---

## 3. 技术栈

| 层面 | 选型 | 说明 |
| --- | --- | --- |
| 引擎 | Godot 4.7 | Forward+ 渲染；主场景 `scenes/Main.tscn` |
| 语言 | GDScript | 不用 C#；全显式类型；大量中文标识符是既定风格 |
| 渲染 | Windows 下 D3D12 | 写在 `project.godot` 的 `rendering/rendering_device/driver.windows` |
| 物理 | Jolt Physics | 工程里指定了，但卡牌游戏几乎不用物理 |
| UI | Control 节点 + 全局主题 | 设计基准 **1920×1080**，`canvas_items` 拉伸 |
| 协议 | protobuf 线格式手写编解码 | `Framing`（分帧）+ `ProtoCodec`（编解码）+ `ProtoSchema`（字段表） |
| 联机 | 局域网 TCP / Steam P2P | 两条底座共用同一套房间与战斗逻辑 |
| 数据 | Excel → CSV → GDScript | 生成文件 `Table/TableScripts/DataTables.gd` |
| Steam | GodotSteam 4.23.1 | 开发期 AppID 480（SpaceWar），正式发布前要换 |

**代码风格**：变量、函数、文件名大量使用中文（作者自述“用中文编码”）。请不要“顺手改成英文”，否则会和现有代码、注释、表格字段大面积错位。

---

## 4. 目录地图

```text
xianyu_xingbei/
├─ project.godot                ← 工程配置：主场景、autoload、分辨率、渲染驱动、版本号
├─ AGENTS.md                    ← 本文件：项目总览与协作约定
├─ README.md                    ← 原有开发记录/细节说明
├─ 项目文档/                     ← 项目文档
│  └─ 技能维护约定.md            ← 改技能前必读
├─ export_presets.cfg           ← 导出预设（Windows Desktop）
├─ 编译设置.gdbuild             ← 自定义引擎构建的裁剪配置（可选）
│
├─ scenes/                      ← 所有界面与预制体（.tscn）
│  ├─ Main.tscn                 ← 唯一主场景：背景 + 界面层 + TAB 玩家列表
│  ├─ enter.tscn                ← 登录界面
│  ├─ lobby.tscn                ← 大厅：房间列表 / 建房面板
│  ├─ ReadyRoom.tscn            ← 房间准备室：分队、准备、聊天
│  ├─ BattleUIMobile.tscn       ← 战斗界面（手机版排版）
│  ├─ role_pick.tscn            ← 选将弹层
│  ├─ Settings.tscn             ← 设置浮层（音量等）
│  └─ prefabs/                  ← 卡牌、玩家面板、技能按钮、特效等小件
│
├─ scripts/                     ← 全部运行时逻辑（约 5.3 万行）
│  ├─ ui/                       ← 界面逻辑（battle_mobile.gd 最大，约 7300 行）
│  ├─ battle/                   ← 战斗引擎 + 角色基类 + 54 个角色脚本 + 独有技 helper
│  ├─ net/                      ← 网络：TCP / Steam / 局域网发现 / 权威服务端
│  ├─ client/                   ← 客户端逻辑、启动配置、音频
│  ├─ data/                     ← 卡牌、玩家、队伍的数据模型
│  ├─ core/                     ← 协议、常量、编解码、分帧
│  ├─ framework/                ← 资源索引、消息总线
│  ├─ effects/                  ← 2D/3D 特效脚本
│  └─ *.gd                      ← 从参考工程搬来的控件脚本（卡牌、玩家面板等）
│
├─ assets/                      ← 图片、音频、字体（约 330 个资源文件）
├─ Table/                       ← 配置表（设计表 / CSV / 生成的 GD）
├─ addons/                      ← 编辑器插件 + GodotSteam
├─ tests/                       ← 自检、联机测试、多开脚本
├─ icon.png / icon.svg          ← 工程图标
├─ _cut_33L.py / _cut_Big33L.py / _make_37.py
│                               ← 角色立绘“绿幕抠图”用的临时 Python 脚本，不参与游戏运行
└─ __pycache__/                 ← 上面那些脚本的缓存，可删
```

### 4.1 `scripts/` 分层

| 目录 | 文件数 / 行数 | 职责 | 先看哪个文件 |
| --- | --- | --- | --- |
| `scripts/ui/` | 16 / 约 1.1 万 | 界面逻辑：登录、大厅、准备室、战斗、选将、设置 | [ui_manager.gd](scripts/ui/ui_manager.gd) |
| `scripts/battle/` | 4 / 约 5800 | 权威战斗引擎、角色基类、玩家状态、牌库 | [battle_engine.gd](scripts/battle/battle_engine.gd) |
| `scripts/battle/roles/` | 54 / 约 2.3 万 | 每个角色一个脚本，实现技能与时机钩子 | 任选一个 `role_*.gd` |
| `scripts/battle/skills/` | 6 / 约 1500 | 跨角色独有技 helper（神箭手/狂战士/元素师/封印师/祈祷师/剑圣） | [skill_archer.gd](scripts/battle/skills/skill_archer.gd) |
| `scripts/net/` | 12 / 约 3000 | 房主/加入编排、TCP、Steam、局域网发现、协议收发 | [net_manager.gd](scripts/net/net_manager.gd) |
| `scripts/client/` | 3 / 约 1300 | 客户端逻辑（收包分派）、启动配置、音频 | [client_logic.gd](scripts/client/client_logic.gd) |
| `scripts/data/` | 4 / 约 850 | 卡牌 `GCard`、玩家 `GPlayer`、队伍 `GTeam`、数据接口 | [data_interface.gd](scripts/data/data_interface.gd) |
| `scripts/core/` | 4 / 约 2600 | 常量/枚举、协议号、protobuf 编解码、帧格式 | [const.gd](scripts/core/const.gd) |
| `scripts/framework/` | 4 / 约 480 | 资源名索引、消息总线 | [AssetIndex.gd](scripts/framework/AssetIndex.gd) |
| `scripts/effects/` | 11 / 约 1100 | 斩击、魔弹、发牌、弃牌、点击星屑等特效 | [effect_warmer.gd](scripts/effects/effect_warmer.gd) |
| `scripts/*.gd`（根级） | 10 / 约 2400 | 从参考工程搬来的控件脚本：卡牌 UI、玩家面板、技能按钮等 | [PlayerStatusMobile.gd](scripts/PlayerStatusMobile.gd) |

### 4.2 建议的阅读顺序

如果你是第一次接触这个工程，**按这个顺序读**会最省力：

1. [project.godot](project.godot) → [scenes/Main.tscn](scenes/Main.tscn) → [main.gd](scripts/ui/main.gd)：搞清楚游戏怎么启动。
2. [ui_manager.gd](scripts/ui/ui_manager.gd)：界面是怎么一层层切过去的。
3. [enter.gd](scripts/ui/enter.gd) → [lobby.gd](scripts/ui/lobby.gd)：登录和大厅做了哪些事。
4. [net_manager.gd](scripts/net/net_manager.gd) → [local_server.gd](scripts/net/local_server.gd)：联机是怎么搭起来的。
5. [battle_engine.gd](scripts/battle/battle_engine.gd) → [battle_role.gd](scripts/battle/battle_role.gd) → 随便挑一个 `role_*.gd`：战斗规则和技能怎么写。
6. [battle_mobile.gd](scripts/ui/battle_mobile.gd)：战斗界面怎么把服务端数据画出来、怎么收集玩家操作。

### 4.3 编辑器插件

`addons/` 下的插件会在打开工程时自动加载：

| 插件 | 作用 |
| --- | --- |
| **Excel 转数据表工具** | 「检查并转换表格」/ `Ctrl+Shift+T`：设计表 → CSV → `DataTables.gd` |
| **GD 文件别名显示** | 在编辑器里给文件/文件夹显示中文别名，实际文件名不变；别名存 `alias_data.json` |
| **ResDsp** | 阻止 Godot 把 CSV 当成翻译文件解析，并支持双击用系统程序打开 CSV/xlsx |
| **版本号工具** | 导出时勾选「导出后版本 +0.0.1」，自动更新 `project.godot` 的版本号 |
| **多开测试** | 在编辑器菜单 / F9~F11 一键拉起多个测试窗口 |
| **LabelFontAutoSizer** | 文字自适应辅助插件 |
| **godotsteam** | Steam GDExtension（不是编辑器插件，提供 `Steam` 全局接口） |

---

## 5. 程序是怎么跑起来的

### 5.1 启动链

```text
Godot 启动
  │
  ├─ 先按顺序加载 12 个 autoload（全局单例）
  │    Cfg → SteamNet → Data → Net → Logic → UI → Art → Audio
  │    → AssetIndex → MessageSystem → ClickDust → EffectWarmer
  │
  └─ 打开主场景 scenes/Main.tscn
	   └─ main.gd：画背景、把「界面层」交给 UI 管理、注册 TAB 玩家列表
			└─ UI.goto_enter() → 登录界面
```

之后每次切界面，都是往 `Main/界面层` 下面挂一个新场景，再把旧场景释放掉；**背景始终只有 Main 这一张**，所以切界面时背景不会闪。

### 5.2 界面流转

```text
启动
  │
  ▼
登录 Enter
  │  「进入游戏」
  ▼
大厅 Lobby
  │  「建房 / 进房」
  ▼
准备室 ReadyRoom
  │  「开局」
  ▼
战斗 BattleUIMobile
  │  「结算后返回」
  ▼
大厅 Lobby

（大厅可以返回登录；准备室可以返回大厅。）
```

| 界面 | 场景 | 脚本 | 什么时候出现 |
| --- | --- | --- | --- |
| 主场景 / 背景 | `scenes/Main.tscn` | [main.gd](scripts/ui/main.gd) | 始终存在 |
| 登录 | `scenes/enter.tscn` | [enter.gd](scripts/ui/enter.gd) | 启动后的第一个界面 |
| 大厅 | `scenes/lobby.tscn` | [lobby.gd](scripts/ui/lobby.gd) | 点「进入游戏」并连上房主后 |
| 准备室 | `scenes/ReadyRoom.tscn` | [ready_room.gd](scripts/ui/ready_room.gd) | 进房后、开局前 |
| 战斗 | `scenes/BattleUIMobile.tscn` | [battle_mobile.gd](scripts/ui/battle_mobile.gd) | 收到 `started = true` 的快照后 |
| 选将浮层 | `scenes/role_pick.tscn` | [role_pick.gd](scripts/ui/role_pick.gd) | 服务端下发 `RoleReq` 时叠在当前界面上 |
| 设置浮层 | `scenes/Settings.tscn` | [settings.gd](scripts/ui/settings.gd) | 任意界面点设置按钮 |
| 玩家列表 | 内嵌在 `Main.tscn` | [main.gd](scripts/ui/main.gd) | 在房间里按住 **TAB** |

切换逻辑全部集中在 [ui_manager.gd](scripts/ui/ui_manager.gd)：`goto_*()` 负责换主界面，`显示选角()` / `切换设置()` 负责叠浮层，切界面时浮层会被一并清掉。

### 5.3 12 个全局单例（autoload）

这些单例在 `project.godot` 的 `[autoload]` 中注册，**任何脚本都能直接按名字使用**，不需要 `get_node()`。

| 名字 | 文件 | 管什么 | 常用接口 |
| --- | --- | --- | --- |
| `Cfg` | [config.gd](scripts/client/config.gd) | 启动参数、槽位、昵称、本地配置、窗口摆位、ESC 重启 | `Cfg.nickname`、`Cfg.本地模式`、`Cfg.无Steam()` |
| `SteamNet` | [steam_net.gd](scripts/net/steam_net.gd) | Steam 初始化、Steam 身份、大厅的建/查/进/退 | `SteamNet.就绪`、`SteamNet.建房()`、`SteamNet.查询大厅()` |
| `Data` | [data_interface.gd](scripts/data/data_interface.gd) | 把数据表读进内存；维护当前对局的玩家、手牌、队伍 | `Data.player_list`、`Data.get_card()`、`Data.role_pool` |
| `Net` | [net_manager.gd](scripts/net/net_manager.gd) | 房主/加入编排；选传输底座；统一收发 | `Net.host_game()`、`Net.join_game()`、`Net.send()` |
| `Logic` | [client_logic.gd](scripts/client/client_logic.gd) | 把收到的协议分派成信号；封装所有上行操作 | `Logic.send_action()`、`Logic.turn_changed`、`Logic.game_info_updated` |
| `UI` | [ui_manager.gd](scripts/ui/ui_manager.gd) | 界面切换、浮层管理、Steam 状态行 | `UI.goto_lobby()`、`UI.确保对局界面()`、`UI.显示选角()` |
| `Art` | [art.gd](scripts/ui/art.gd) | 按名字取贴图/音效，带缓存 | `Art.tex()`、`Art.card_face()`、`Art.role_hero()`、`Art.play_sfx()` |
| `Audio` | [audio.gd](scripts/client/audio.gd) | 背景音乐、战斗音效、音量设置、失焦静音 | `Audio.播放音乐()`、`Audio.播音效()`、`Audio.设置音乐音量()` |
| `AssetIndex` | [AssetIndex.gd](scripts/framework/AssetIndex.gd) | 启动时扫描 `assets/`，按文件名建立索引 | `AssetIndex.image()`、`AssetIndex.audio()` |
| `MessageSystem` | [MessageSystem.gd](scripts/framework/MessageSystem.gd) | 全局消息总线（参考工程遗留，用得较少） | `MessageSystem.regist()` / `notify()` |
| `ClickDust` | [clickStardust.gd](scripts/effects/clickStardust.gd) | 全游戏鼠标点击星屑/涟漪 | 自动生效，不需要调用 |
| `EffectWarmer` | [effect_warmer.gd](scripts/effects/effect_warmer.gd) | 启动时预热所有出手特效的着色器，避免第一次放特效卡顿 | 自动生效；特效预制表也在这里 |

> **顺序有意义**：`Cfg` 要最先读启动参数，`SteamNet` 要在 `Net` 之前决定底座，`Logic` 要在 `UI` 之前准备好信号。

---

## 6. 联机架构

### 6.1 核心思想：房主就是服务器

这个项目**没有独立服务器**。谁点「创建房间」，谁的进程里就会跑一个**权威服务端**（`LocalServer`；本地 / Steam 模式在登录时已经起好了），其他人都是普通客户端：

```text
房主进程（= 一台服务器 + 一个玩家）

  客户端这一半：战斗界面 / Logic / NetManager
	   │  上行操作
	   ▼
  权威服务端 LocalServer ──▶ BattleEngine（规则）
  （房间、座位、选角、计时、胜负）
	   │  下行快照 / 事件（回到客户端）
	   │
	   │  局域网 TCP  或  Steam P2P
	   ▼
  玩家 2 / 玩家 3 / 观战者
  （只发操作、只收快照，自己不判规则）
```

这样做的好处：

- 不需要买公网服务器，也不会因为暴露服务端而被攻击；
- 房主一退，房间自然解散，没有“幽灵房间”；
- 所有客户端看到的是同一份权威结果，不会出现“各算各的”。

代价是：**房主掉线，这局就结束**（或由其他人重新建房）。

### 6.2 传输底座：两种实现 + 多路复用

`Net` 不直接碰 socket，而是持有一个“客户端底座”；`LocalServer` 持有一个“服务端底座”。上层只依赖抽象，所以换传输方式不用改房间和战斗逻辑。

| 角色 | 抽象类 | 局域网实现 | Steam 实现 |
| --- | --- | --- | --- |
| 客户端 | `NetworkClient` | [net_client.gd](scripts/net/net_client.gd)（TCP 长连接） | [steam_client.gd](scripts/net/steam_client.gd)（SteamNetworkingMessages） |
| 服务端 | `NetworkServer` | [net_server.gd](scripts/net/net_server.gd)（TCP 监听） | [steam_server.gd](scripts/net/steam_server.gd)（Steam P2P） |

Steam 模式下，服务端用的是**多路复用底座** [multi_server.gd](scripts/net/multi_server.gd)：

- 同时挂 `SteamServer` + `NetServer`；
- 因此 Steam 房里，**同一局域网、没登 Steam 的机器也能连进来**；
- 两种连接的 `conn_id` 天然不冲突（Steam 用对端 SteamID，局域网从 1 开始编号）。

Steam P2P 有两个细节：

- 客户端固定“发 0 号通道、收 1 号通道”，服务端反过来，避免同一进程里两个角色抢消息；
- 房主自己那一路**不走 Steam 回环**（实测发给自己会断），而是进程内直连 `LocalServer`。

### 6.3 三种运行模式

| 模式 | 怎么触发 | 用哪条底座 | 房间列表来自 | 用途 |
| --- | --- | --- | --- | --- |
| **本地调试模式** | 带 `--slot` / `--count` / `--auto` | 局域网 TCP | 本机服务端 | F9/F10/F11、日常开发、自检 |
| **局域网模式** | 带 `--lan` | 局域网 TCP | 同网段发现的主机 + 本机服务端 | 内网联调 |
| **Steam 模式** | 裸启动（编辑器 F5 / 导出包） | Steam P2P（+ 局域网 TCP 兜底） | Steam 大厅 | 正式玩家联机 |

判定集中在 [config.gd](scripts/client/config.gd)（简化写法）：

```gdscript
本地模式 = 带启动参数 or --auto or --count > 0
局域网模式 = --lan
无Steam() = 本地模式 or 局域网模式
```

**登录时各模式的行为不同：**

- 本地 / Steam：登录时先尝试**在本机起服务端**并连自己；起不来（端口被占，同机已有房主）则按“连已有房主”处理。
- 局域网：登录**不起服务端**，直接进大厅搜索主机；点「创建房间」时才在本机开服。

> Steam 联机代码已经比较完整（大厅、P2P、断线重连、座位认领都有），但仍在用开发 AppID 480 联调；正式发布前需要换成自有 AppID 并通过 Steam 审核。README 里写的是“尚未接完”，以实际联调结果为准。

### 6.4 连接、心跳、重连、座位

- **登录**：连接建立后发 `LoginReq`，带昵称、身份标识、协议版本、游戏版本。服务端回 `LoginRep`。
- **心跳**：服务端每 **2 秒**给所有连接发 `HeartBeat`；客户端原样回声，服务端据此算这一路的往返延迟（大厅/玩家列表里的 ping）。
- **断线判定**：客户端 **6 秒**没收到任何服务端消息，就主动标记断开并进入自动重连（Steam P2P 没有底层断连事件，必须靠这个兜底）。
- **重连**：局域网 TCP 首次连接最多等 6 秒、掉线后最多等 20 秒；Steam 每 4 秒一轮、试 3 轮。
- **认回座位**：服务端用 `client_id` 认人（Steam 模式 = SteamID；本地模式 = 昵称）。**选角开始之后**掉线才留座；准备室阶段掉线不留座，直接回大厅。
- **版本不一致**：房间在列表里看得见（会显示对方版本），但登录会被服务端拒绝——这是刻意设计，避免新旧规则混打。

> 本地模式用昵称当身份，所以**昵称不能重复**：重名会互相抢座位。本地模式下每个窗口默认会生成不同的随机昵称，正是为了避免撞名。

### 6.5 局域网发现

[discovery.gd](scripts/net/discovery.gd) 有两条互补的发现路径：

1. **跨机 UDP 广播**：默认端口 `11112`。搜索方周期性广播探测，房主应答；房主再广播一次，让同网段其他客户端也能收到。
2. **同机 TCP 探测**：对 `127.0.0.1` 和各网卡地址逐个尝试连接，连上即说明“本机有房”，随即断开。

设计细节：**搜索和应答各用一条独立 socket**。大厅退出时只关搜索；房主进房后仍要持续应答，否则别人就再也搜不到他了。

发现只负责“看见”，不按版本过滤；能不能进由登录校验决定。

### 6.6 协议长什么样

所有消息都走同一个帧格式（小端），见 [framing.gd](scripts/core/framing.gd)：

```text
[ uint32 外层长度 L ][ uint16 帧头长度 ][ uint16 协议号 ][ protobuf 消息体（可为 0 字节） ]
总帧长 = 4 + L；单帧上限 65535 字节
```

- [proto_schema.gd](scripts/core/proto_schema.gd) 用**字段表**描述每个协议号有哪些字段，不依赖 `.proto` 编译；
- [proto_codec.gd](scripts/core/proto_codec.gd) 按字段表做 protobuf 线格式的编码/解码；
- 协议号在 [const.gd](scripts/core/const.gd) 的 `GConst.Msg` 中：

| 区间 | 内容 |
| --- | --- |
| 1 ~ 24 | 登录、房间列表、建房/进房/退房、准备、心跳、错误等基础协议 |
| 101 ~ 112 | 战斗：选角、行动、回复、询问、命中、伤害、技能、卡牌 |
| 113 / 114 | 本项目扩展：调试指令 `DebugReq`、受伤飘字 `HurtFloat` |

登录包示例（[net_manager.gd](scripts/net/net_manager.gd)）：

```gdscript
Net.send(GConst.Msg.LoginReq, {
		"as_guest": true,
		"user_id": Cfg.nickname,
		"version": 161001,
		"client_id": Cfg.身份标识(),
		"game_version": Cfg.游戏版本(),
})
```

---

## 7. 一局游戏如何走完

### 7.1 从登录到开局

1. **登录**：客户端连上房主的服务端，发 `LoginReq`；服务端登记身份并回 `LoginRep`。
2. **进大厅**：本地/Steam 模式已有连接，直接请求房间列表；局域网模式先搜主机，选中后再连。
3. **建房**：房主点「创建房间」→ `CreateRoomReq` → `LocalServer._建房间()`，房间号 +1，房主落座。
4. **进房**：其他人 `EnterRoomReq` → 服务端分配座位号和 `player_id`，下发第一份 `Game` 快照。
5. **准备室**：分队 `JoinTeamReq`、准备 `ReadyForGameReq`。**人数坐满、全部准备、队伍平衡**后，开始 5 秒开局倒计时（本地调试为 0 秒，立刻开）。
6. **选角**：服务端 `RoleReq` 下发候选角色 → 客户端弹选将层 → `PickBan` 回选。超时 60 秒自动收尾；全员提交或超时后锁定名单，再等 5 秒正式开局。
7. **战斗**：`BattleEngine` 逐回合推进，期间的每次选择都通过“询问 → 回复”完成（见 7.2）。
8. **终局**：一方士气归零或星杯达到 5 个 → `over = true` → 房间立即解散；客户端**留在结算界面**看完结果，再自己回大厅。

### 7.2 战斗中的一问一答

服务端不会让客户端“自由操作”，而是每一步都先问、再收答案：

```text
服务端 BattleEngine
   │  ① 下发询问 CmdReq（cmd_type = Action 或 Respond，带可选项/可点牌/可点目标）
   ▼
客户端 Logic.command_received
   │  ② 战斗界面画出按钮、点亮头像和手牌
   ▼
玩家点击「确定」
   │  ③ 上行 Action（行动）或 Respond（应战/弃牌/治疗/技能选项）
   ▼
服务端校验
   ├─ 合法 → 结算，广播结果
   └─ 不合法 → 回 ErrorInput，界面恢复待选
```

几个关键点：

- **询问都走 `CmdReq`**：`cmd_type = 1` 是行动询问，`2` 是应答/技能询问。技能选项、选牌、选目标、弃牌、用治疗抵挡，全是同一套。
- **超时兜底**：普通玩家 60 秒、已掉线玩家 5 秒。超时后服务端按“最保守”的默认回复继续（放弃行动 / 不发动 / 默认挡伤害），不会把整局卡死。
- **重连补发**：玩家掉线重连回来，服务端会把“正等他的那份询问”原样再发一次，否则他手里没有界面，只能干等超时。
- **客户端只做体验过滤**：置灰、限制可点目标是为了少点错；**最终合法性一律由服务端校验**。

结算后客户端会收到这些事件（[client_logic.gd](scripts/client/client_logic.gd) 把它们转成信号）：

| 消息 | 含义 | 界面反应 |
| --- | --- | --- |
| `Game` | 完整对局快照 | 刷新头像、手牌、士气、星石、回合等 |
| `CmdReq` | 服务端询问 | 画出操作界面 |
| `Hit` | 命中/未命中 | 播命中特效、音效 |
| `Hurt` / `HurtFloat` | 伤害事件 / 伤害飘字 | 飘数字、受击动画 |
| `Skill` | 技能发动通知 | 发动者头像上飘技能名、特效 |
| `Card` | 展示/使用/交给牌 | 中间摊牌；打出时头像上飘卡牌名；给牌动效 |
| `Gossip` | 日志/聊天/系统公告；特殊行动附带结构化字段 | 战斗日志或聊天区；购买 / 合成 / 提炼在头像上飘字 |
| `TurnBegin` | 回合开始 | 高亮当前玩家、播音效 |
| `ErrorInput` | 操作被驳回 | 恢复待选并提示 |

---

## 8. 战斗引擎

### 8.1 栈式状态机

[BattleEngine](scripts/battle/battle_engine.gd) 是**权威规则实现**，每个房间一个实例。它不用协程、不阻塞，而是用“状态栈”推进：

```text
状态栈（后进先出）—— 越靠上越先执行：

  1. SHandOverflow    超限弃牌
  2. SAttackCard      出攻击牌
  3. SActionPhase     行动阶段
  4. SCheckTurnStart  回合开始
```

每个状态的 `handle()` 返回三选一：

| 返回值 | 含义 |
| --- | --- |
| `CONTINUE` (0) | 本状态完成，出栈，继续跑下一个 |
| `WAIT` (1) | 正等某个玩家回复，停在这里；收到回复后再次 `handle()` |
| `SUSPEND` (2) | 先跑刚压入栈顶的新状态，跑完再回来继续本状态 |

引擎的 `run()` 会一直循环到栈空或遇到 `WAIT`。`tick()` 每帧由服务端调用，负责推进“回复超时”。

常见状态（都在 `battle_engine.gd` 里）：

- `SCheckTurnStart` / `SActionPhase` / `STurnEnd` / `SNextPlayer`：回合骨架；
- `SAttackCard` / `SAttackedAsk` / `SReattackGo`：攻击、应战、反击；
- `STimeline2Hit` / `SHarmTimeline3` / `SAskCross` / `SHarmTimeline6`：伤害流水线；
- `SDraw` / `SHandOverflow` / `SOverloadMorale`：摸牌、超限弃牌、掉士气；
- `SHook`：跑一轮“所有角色的同名钩子”；
- `SkillRun`：执行主动技能。

### 8.2 伤害与士气（规则速写）

以一次攻击为例：

```text
命中判定
  → 广播 Hit（命中/未命中）
  → 广播伤害点数 HurtFloat / Hurt
  → 受伤者选择用多少【治疗】抵挡（RespondType.Heal）
  → 剩余点数让受伤者摸等量的牌
  → 手牌超过上限 → 选择弃牌，并按超限张数扣队伍士气
  → 某队士气 ≤ 0 → 结算胜负
```

> 【治疗】是角色身上的减伤点数；【士气】是整支队伍共用的“血条”（4/6 人局固定 15）。两者不是一回事。

### 8.3 角色钩子：技能是怎么“插”进去的

所有角色脚本都继承 [BattleRole](scripts/battle/battle_role.gd)。基类里定义了一大批 `p_*` 钩子，**默认什么都不做**，角色只覆写自己关心的那些：

```gdscript
func p_before_action(_ctx: Dictionary) -> int: return SUCCESS
func p_attacked(_ctx: Dictionary) -> int: return SUCCESS
func p_timeline_4(_ctx: Dictionary) -> int: return SUCCESS
```

引擎在对应时机，会按座位顺序对**每个玩家**调用一次同名钩子。角色可以：

- 返回 `SUCCESS`：跳过；
- 返回 `WAIT`：暂停整轮钩子，等服务端把询问发给玩家、收到回复后再从这个角色继续；
- 返回 `URGENT`：先执行它刚压入栈的新状态（比如造成一次伤害），回来再继续。

因为要支持“等回复”，角色内部用 `step` 记进度。现在 `step` 按“当前钩子轮次”隔离，不会互相污染。

**`p_*_skill` 压入引擎状态后必须返回 `URGENT`。** 技能本体里用 `engine.push_draw` / `push_harm` / `push(...)` 压入摸牌、伤害、弃置等状态后，如果返回 `SUCCESS`，`SkillRun` 会继续把「行动结束响应」压在这些状态上面：玩家先看到神圣追击 / 迅捷赐福等响应，响应结束才摸牌 / 结算（女武神【秩序之印】踩过——响应完才摸 2 张）。压了状态就返回 `URGENT`，让引擎先跑完压入的状态，再回来触发行动结束。

钩子覆盖的时机包括：回合开始/结束、行动前、攻击前后、法术前后、特殊行动前后、被攻击、伤害时间线 1~6、士气变化、盖牌变化、手牌变化、横置、展示手牌等。

### 8.3.1 行动聚合器（攻击/法术结束统一入口）

攻击结束和法术结束时，**所有可选的行动**统一由 [battle_engine.gd](scripts/battle/battle_engine.gd) 里的 `S行动聚合器` 收集并合成一次询问，不再由各角色自己 `ask_skill`。

聚合器只做四件事：

1. 收集角色登记的行动选项；
2. 收集目标身上未确认的基础效果额外行动（迅捷赐福等）；
3. 收集队列里尚未确认的额外行动；
4. 发询问，并把选中的 `cause` 分派回来源。

聚合器**不负责**扣费、标 `direct`、改 `additional_actions`、决定行动何时进入。

角色接口：

```gdscript
func action_end_options(ctx: Dictionary) -> Array:
	# 返回值描述：value / label / skill_id / need_card / need_target /
	# card_source / targets / enabled
	return []

func resolve_action_end_option(cause: int, reply: Dictionary, ctx: Dictionary) -> int:
	# 自己扣费、入队、标 direct、执行技能；多步时返回 WAIT/URGENT
	return SUCCESS
```

已接入的行动：

- 风之剑圣 105 剑影（103 风怒追击改为「攻击行动结束自动生效」，不再进响应选项）
- 剑之子 10804 剑残影 / 4504 剑影断念
- 剑之魔女 4501 技之剑意 / 4504 剑影断念
- 猎巫人 4205 偷袭
- 魔弓 2603 多重射击
- 剑帝 1907、红莲 2808、女武神 2501、兽灵 3602、血剑 3402、游击士 3802/3803
- 迅捷赐福 1601（基础效果来源）

纯「结束后自动 +1 攻击行动」的技能**不进聚合器**：封印师 406 法术激荡、剑圣 103 风怒追击、魔剑士 901 修罗连斩，都在 `p_after_attack` / `p_after_magic` 里直接 `player.add_action(种类, cause, true, …)`（direct = 引擎直接进入那份额外行动，不再弹「是否发动」）。玩家不想要就在那个额外行动阶段点「放弃行动」；`p_action_end` 里记「本回合已用」实现【回合限定】。要加限制就写进行动规格（`element` / `card_fate` 等）。

多步技能（如偷袭选 X 名追加目标、剑影断念弃牌摸牌）由角色返回 `WAIT` / `URGENT`，聚合器进入“待决”状态，**等该技能完全结算完**再继续问剩余选项；中途不会插问迅捷赐福。

额外行动在技能栏里按**获取序号固定排列**，当前行动只高亮，不再强制挪到最左。行动结束响应里的选项顺序是**行动在前、响应在后**：队列额外行动 → 基础效果（迅捷赐福等）→ 角色响应技能。**只有二级技能栏的父技能才强制最左**，主行动技能栏不要复用这条规则。

**额外行动的排序只有一个实现**：引擎 `BattleEngine.额外行动序列(pid, 含当前)`（队列按 `order` 升序 + 可选的当前行动）。行动结束响应的红色快捷按钮、额外行动阶段的技能栏、额外行动选择框都直接下发/渲染这个顺序，**客户端不排序、不重排**（`extra_attack_causes` 等字段的顺序就是显示顺序）。踩过的坑：客户端曾按 `extra_order` 二次排序，而该字段没写进 `proto_schema.gd`、永远收不到（恒为 0），技能栏退回按技能号排，和响应对不上。要改排列方式只改 `额外行动序列` 一处。

**`order`（获取序号）只在「玩家真正拿到这份行动」时取号。** 基础效果（迅捷赐福等）的行动可能被祈祷师/借用角色在行动结束钩子里**提前垫进队列**——那是演员顺序（座位顺序）决定的时刻，不是玩家获得时刻；玩家在响应里**确认**时才 `_确认基础效果额外行动` 重新取号，否则会出现「我确认的迅捷赐福排在自动生效的修罗连斩前面」。同理，自动生效的技能（`p_after_attack` 里 `add_action`）天然就在响应之前取号。

**额外行动的身份是唯一 ID（`uid`），不是 `cause`。** 同一个技能可以同时挂好几份行动（连续两张【疾风技】就是两份 101），按 `cause` 认会让选项一起点亮、还会进错份。所以：`BattlePlayer.add_action` 给每份行动发 `uid`（只增不减，换队不改）；下发给客户端时，单个命令带 `extra_uid`，列表带与 cause 一一对应的 `extra_attack_uids` / `option_uids`；客户端选中 / 提交一律用 `uid`（`args[0]`），引擎按 `额外行动按ID` / `额外行动下标按ID` 认人。`cause` 只用来显示来源技能名和驱动技能侧逻辑（`p_additional_action`、`行动结束确认代价` 等仍按技能号），不要拿它当身份。

**「这一手消耗哪份额外行动」由 `Action.extra_uid` 指定，打牌和技能行动都带。** 客户端本地选中的那份行动随每次行动提交下发；`resolve_action` 先按它换队（`_切换额外行动(cur, uid, 作为)`，按「马上要做的动作种类」判那份额外行动是否放行），换完再按新的 `行动允许` 过总闸。以前只有出攻击牌会换队，所以额外行动阶段「先点行动、再点技能」永远消耗服务端当前那一份。客户端那边「行动的选择」和「技能自己的选择」是两条独立的线：技能进本地二级技能栏时，把选中的额外行动按钮摆在本体前面。

**额外行动本身是通用工具，不认来源技能。** 授予时用 `player.add_action(种类, 来源, direct, skip_notice, spec)`，出牌白名单 / 目标白名单 / 系别 / 能否切换 / 是否作为行动结束响应都由技能在 `spec` 里一次写清（`cards` / `targets` / `element` / `switchable` / `in_end_response`），引擎只照单执行：下发 `card_ids` / `dst_ids` / `extra_element`，落牌与选目标时按同一份规格兜底，不再按 `cause` 回问角色（旧的 `extra_action_card_ids` / `extra_action_targets` / `extra_action_switchable` / `extra_action_element` / `v_additional_action` / `额外行动属于结束响应` 已删除）。技能需要按“进入那一刻”的状态重算限制时，在 `p_additional_action` 里 `player.改写额外行动(cause, spec)`；这份行动不再可用时 `player.撤回额外行动(cause)`。扣费、移除赐福牌、形态变化仍留在技能侧（确认时付费 / 进入时结算）。

有代价的额外行动采用“点选即付”：在响应里点选时走角色的 `行动结束确认代价(cause)` 扣能量/治疗/指示物等，已付不退。**响应阶段不能使用行动**：当前正在消耗的额外行动按钮（二级栏最左那颗）、已获得的额外行动/基础效果仍按原顺序显示，但一律置灰不可点，并排在响应选项**左边**；真正使用留到响应结束后的额外行动阶段（`SAdditionalAction`），在那边选中 / 放弃。取消响应**只结束响应**，不再清空或跳过任何额外行动；已获得的行动全部保留到额外行动阶段。响应里没点选、取消后直接使用的那份，在额外行动阶段真正进入时补扣一次代价（避免“取消一下就能免费使用”）。

不放进聚合器的特殊结算：

- 圣剑第三刀：在 `p_after_attack` 里先摸弃，属于优先结算；
- 格斗家念弹：`has_priority_action_end() = true` + `p_priority_action_end()`，强制且先加斗气，排在所有普通响应之前。

新增角色若在攻击/法术结束提供可选行动，必须实现 `action_end_options()` / `resolve_action_end_option()`，不要再自己开 `ask_skill` 选项循环。

### 8.4 角色、技能、数据三者的关系

```text
角色表（设计表）                          技能表（设计表）
  · 角色索引 = 1                            · 技能#风怒追击
  · 职业名 = 风之剑圣 / 姓名 = 威斯特姆      · 脚本号 = 103
  · 显示名 = 风之剑圣                        · 类型 = 响应 / 普通
  · 命格 = 技                               · 说明 / 提示列
  · 各项上限 / 指示物
  · 脚本 = role_jiansheng.gd
  · 技能 = [技能#…]
		│
		│ Data.role_script(角色号)
		▼
  scripts/battle/roles/role_jiansheng.gd
		│
		│ 按技能号分支
		▼
  技能的具体实现
```

- **角色号**是协议和代码里用的稳定数字（角色表的「角色索引」列）。
- **技能号**就是「技能表#N」里的 N；角色脚本里用这些数字判断“现在是谁的技能”。
- 角色脚本的路径写在角色表的「脚本」列，运行时由 `Data.role_script()` 读取并实例化。
- 技能的文案、提示语在技能表里；**能在表里配的，不要写死在脚本里**。

新增一个角色的最小步骤：

1. 设计表「角色表」加一行：索引、职业名、姓名、显示名、命格、各项上限、指示物、脚本路径、技能列表；
2. 设计表「技能表」补齐该角色的技能行（脚本号、说明、提示列）；
3. 新建 `scripts/battle/roles/role_xxx.gd`，继承 `BattleRole`，实现需要的钩子；
4. 把角色立绘/图标放进 `assets/`（命名与表的「图标名 / 形态图」对应）；
5. 导表（Ctrl+Shift+T）；
6. 补一个自检用例，跑 `tests/runSelfCheck.ps1`；
7. 需要头像提示 / 技能指示器 / 魔弹系别等客户端特性时，按 [技能维护约定](项目文档/技能维护约定.md) 的「公共能力与借用技约定」接进 `const.gd`；
8. 最后跑一遍全量自检（当前 62 例）。

> 角色技能有一份更细的规范：[技能维护约定](项目文档/技能维护约定.md)。改技能前建议先读一遍。

### 8.5 13 名 3★/3.5★ 角色（本轮新增）

本轮把角色表里原本禁用的 13 名 3★/3.5★ 角色补上脚本并启用，共 **59** 颗技能：

| 角色号 | 职业名 | 技能号 | 脚本 | 自检用例 |
| ---: | --- | --- | --- | --- |
| 38 | 游击士 | 3801~3805 | `role_youjishi.gd` | `tests/cases/30_youjishi.gd` |
| 41 | 战斗法师 | 4101~4104 | `role_zhandoufashi.gd` | `tests/cases/31_zhandoufashi.gd` |
| 45 | 剑之魔女 | 4501~4504 | `role_jianzhimoni.gd` | `tests/cases/32_jianzhimoni.gd` |
| 46 | 灵熙之潮 | 4601~4606 | `role_lingxizhichao.gd` | `tests/cases/33_lingxizhichao.gd` |
| 47 | 暴食少女 | 4701~4705 | `role_baoshishaonv.gd` | `tests/cases/34_baoshishaonv.gd` |
| 75 | EX魔弓 | 7501~7504 | `role_exmogong.gd` | `tests/cases/35_exmogong.gd` |
| 78 | 矜贵之女 | 7801~7805 | `role_jinguizhinv.gd` | `tests/cases/36_jinguizhinv.gd` |
| 87 | 贪婪少女 | 8701~8704 | `role_tanlanshaonv.gd` | `tests/cases/37_tanlanshaonv.gd` |
| 93 | 见习制片 | 9301~9305 | `role_jianxizhipian.gd` | `tests/cases/38_jianxizhipian.gd` |
| 97 | 萝莉番长 | 9701~9704 | `role_luolifanzhang.gd` | `tests/cases/39_luolifanzhang.gd` |
| 106 | 怠惰少女 | 10601~10605 | `role_daduoshaonv.gd` | `tests/cases/40_daduoshaonv.gd` |
| 107 | 忌妒少女 | 10701~10704 | `role_jidushaonv.gd` | `tests/cases/41_jidushaonv.gd` |
| 108 | 剑之子 | 10801~10804 | `role_jianzhizi.gd` | `tests/cases/42_jianzhizi.gd` |

- 角色表由 41 条启用变为 **54 条启用**（数据仍 71 条，其余 16 条补录角色 + 1 条 0 号占位保持禁用）；技能表仍 414 行，本批 59 行全部使用已有技能行。
- 为支撑这些角色，新增了 F1~F9 公共能力（魔弹泛化、额外行动计数、指示物/盖牌、基础效果钩子、独有技 helper、伤害转移/弃牌拦截、额外回合/角色替换、牌库顶/星杯/士气、跨玩家操作），6 份独有技 helper 在 `scripts/battle/skills/`。
- 客户端把角色号相关的魔弹系别、基础效果免疫、双张魔弹等集中到 [const.gd](scripts/core/const.gd) 的 `角色特性` 表，并补了本批的技能指示器 / 额外行动提示。
- 验证：`tests/cases/` 34 → **62** 例，headless 自检 `[自检] 用例 62 个：通过 62，失败 0`（2026-10-28）；逐角色实现要点、口径与遗留见 [禁用3星与3.5星角色开发计划](项目文档/禁用3星与3.5星角色开发计划.md) 第 0 节。

### 8.5.1 第二批 7 名角色（39 / 40 / 43 / 79 / 82 / 84 / 95）

| 角色号 | 职业名 | 技能号 | 脚本 | 自检用例 |
| ---: | --- | --- | --- | --- |
| 39 | 圣庭检察士 | 3901~3907 | `role_shengtingjianchashi.gd` | `tests/cases/45_newroles.gd` |
| 40 | 星坠女巫 | 4001~4009 | `role_xingzhuinvwu.gd` | 同上 |
| 43 | 圣殿骑士 | 4301~4307 | `role_shengdianqishi.gd` | 同上 |
| 79 | 噬神者 | 7901~7908 | `role_shishenzhe.gd` | 同上 |
| 82 | 结界师 | 8201~8207 | `role_jiejieshi.gd` | 同上 |
| 84 | 咒符师 | 8401~8405 | `role_zhoufushi.gd` | 同上 |
| 95 | 异教徒 | 9501~9506 | `role_yijiaotu.gd` | 同上 |

为支撑这批角色新增的公共能力（都在引擎 / 协议 / 客户端里，别的角色也能用）：

| 能力 | 落点 | 说明 |
| --- | --- | --- |
| 场卡 | `BattleEngine.field_cards` + `Game.field_cards`（`FieldCard`） | 摆在场上 / 某人面前的公共卡（【异端裁决所】【末日预言】【天雷劫火】【地裂波涛】【绝界】），带计数 / 上限 / 状态 / 隐藏牌堆张数；客户端在拥有者面板状态区画图标 |
| 盖牌「面朝上」 | `BattlePlayer.cover_open` / `cover_tags` + `cover_opens` 快照 | 【结界】这类放在角色旁、牌面公开的旁置牌；`engine.add_cover(pid, cards, src, cause, open, tag)` 放进去时打标记 |
| 【律法】标记 | `BattlePlayer.laws` + `laws` 快照 | 星坠女巫放在角色面前的标记（不是牌） |
| 治疗溢出 | `BattleRole.p_heal_overflow` | 治疗加到上限还有剩余时触发（裁决论定 / 神选者） |
| 禁止获得治疗 | `BattlePlayer.no_heal_round` | 记回合号自动过期（神威） |
| 士气下限 | `BattleRole.morale_floor()` | 本队士气不会被扣到它以下（圣炎形态 = 1） |
| 基础效果禁止 | `BattleRole.基础效果被禁止(pid)` | 决界：拥有者的基础效果无法触发 |
| 伤害摸牌改源 | `BattleRole.伤害摸牌替换(pid)` | 同步钩子：因伤害摸牌的第 1 张改从别处拿（末日预言的【预言】堆） |
| 特殊卡 | 卡表#1005【魔刃】/#1006【异刃】 | 血命格、虚拟牌不进牌库；元素写 `fire or water` / `thunder or wind`，当前系别在 `Card.tscn` 的 `ElementSwitch`（卡面外、手牌中始终显示）切换，本身作为普通攻击牌直接打出；渗蚀用 `ctx.removed` 移出弃牌流程 |

开发计划、逐技能口径与遗留全部记在 [新角色开发计划-异教徒等7名](项目文档/新角色开发计划-异教徒等7名.md)。

### 8.6 卡牌实例号（牌面 = 牌号，身份 = 实例号）

同一张牌面在场上**可能同时有多份**（测试指令发牌会克隆；正常对局里一张牌面就是一张实体牌）。
所以卡牌有两条 id，任何时候都要分清：

| 概念 | 值 | 用在哪 |
| --- | --- | --- |
| **牌号（牌面）** | 卡表里的 `卡牌#N`（0~149，虚拟牌 1000+） | 规则判定、白名单、技能文案、日志、卡面显示 |
| **实例号** | `序号 × GConst.实例步长 + 牌号`（步长 10000） | 手牌 / 盖牌 / 牌堆 / 弃牌堆 / 基础效果区的存取，客户端选中与节点身份 |

- 牌库里原来那 150 张序号为 0，**实例号 == 牌号**，所以正常对局的数据与原实现完全等价；
  克隆牌序号 ≥ 1（如 `10003` = 第 1 份克隆的 3 号牌面）。
- `GConst.牌号(id)` 把实例号折回牌面（负数原样返回）；`GConst.实例号(牌号, 序号)` 反过来造实例号。
  两端都用这一对函数，不需要维护「实例号 → 牌号」的映射表。
- `Data.get_card(id)` 两种 id 都收：查卡面时自动折回牌号。

**分层口径（改代码时按这个来）**

| 层 | 存 / 传什么 |
| --- | --- |
| 服务端区域（`BattlePlayer.hand_cards` / `cover_cards` / `basic_effects`、`BattleDeck.pile` / `discard`） | **实例号** |
| 客户端手牌 / 盖牌（`Data.hand_cards` + `Data.hand_iids`、`Data.cover_cards` + `Data.cover_iids`） | 卡面用 GCard，身份用并行的实例号 |
| 上行 `Action.card_ids` / `Respond.card_ids` | **实例号**（服务端靠它删到「点的那一份」） |
| 下行白名单（`CmdReq.commands[].card_ids`、`option_card_ids`、`ask_skill` 的 `cards`） | **牌面**（客户端按牌面判可点） |
| `Card` 消息的 `card_ids` / `as_card_id` | **牌面**（`send()` 里统一折面，展示 / 音效 / 动画用） |
| `Game` 快照的 `hands` / `covereds` / `basic_cards` | **实例号**（只有本人拿到真实牌；别人只有张数） |

**API 小抄（不要在业务代码里手算）**

- `BattlePlayer.有手牌(id)` / `有盖牌(id)` / `has_hand_card(id)` / `has_discard_card(id)`：实例号或牌面都认。
- `BattlePlayer.取出实例(列, id)` / `取出一张手牌(id)`：**移动一张牌必须用它**，返回实际实例号。
  直接「删一张、再 `add_hand_cards(牌号)`」会退化成凭空补一张同牌面的新牌，和场上原件撞号。
- `BattlePlayer.手牌实例(id)` / `盖牌实例(id)`：只认人不动手（先拿实例号，再交给 `remove_cover` 等删除）。
- `BattleDeck.取出实例(id)`：从牌堆 / 弃牌堆取牌同理（`remove_one` 是它的丢弃返回值包装）。
- `GConst.牌号(id)`：任何「按牌面比较 / 下发客户端」之前折一次。
- `BattleEngine._认一张(列, id, 已选)`：同一牌面的多份副本按份数逐个认，弃牌类询问用它。

**新技能 / 新字段检查**

- 角色脚本从手牌里拿到的 id 是**实例号**：比牌面用 `Data.get_card(id)`，不要直接和牌号常量比。
- `available_skills()` 的 `cards` 可以填实例号（引擎下发前会折面），但**不要**把牌面
  当成实例号塞进区域数组。
- 任何「把牌交给别人 / 放进盖牌区 / 挂成基础效果」的地方，都按 `取出实例` 的返回值走。
- 测试指令（战斗界面数字键 1 / 2 / 3）会克隆同牌面：牌库里没有时分配 `序号*10000+牌号` 的新实例号，
  所以手牌里可以同时出现多张同牌面、实例号互不相同——客户端按实例号选中，不会再「点一张、好几张一起亮」。

---

## 9. 配置表工作流（导表）

### 9.1 唯一权威源：设计表

```text
Table/Design/设计表.xlsx
  │  ① 在 Excel 里改（人改这里）
  ▼
「检查并转换表格」 / Ctrl+Shift+T
  │
  ├──▶ ② Table/Csv/*.csv                    供人工检查的中间态
  │
  └──▶ ③ Table/TableScripts/DataTables.gd   运行时真正读取的数据
```

**只导出工作表名以 `.csv` 结尾的表**；其余工作表忽略。当前 5 张：

| 工作表 | 内容 | 谁在用 |
| --- | --- | --- |
| 卡表 | 155 行（含 5 张无卡面的虚拟牌）：类型、元素、命格、卡名、资源名、技能、说明 | 手牌 UI、战斗引擎 |
| 技能表 | 414 条技能（本批 13 角色 59 条）：脚本号、技能名 / 说明说明名、类型、消耗、说明、8 个提示列 | 角色脚本、技能提示 |
| 角色表 | 71 行（54 条启用）：角色索引、启用开关、星数、上限、职业名 / 姓名、命格、势力、显示名、指示物、脚本、技能 | 选角、战斗初始化 |
| 词缀 | 17 条：关键字 → 图标替换规则 | 富文本说明 |
| 文本表 | 通用文本 | 界面/日志 |

> 维基补录的 29 条角色中，13 名 3★/3.5★ 已补脚本并启用（见 8.5），其余 16 条只配置了技能表文本、没有角色脚本，角色表里默认禁用；另有 1 条 0 号「未选角色」占位。启用前需要补脚本。
> 「星数」是使用难度，取自无名杀角色卡第三项：`3` / `3/4` / `4` / `4/5` / `5` 对应 `3` / `3.5` / `4` / `4.5` / `5` 星。
> 「技能名」是默认名：日志、提示条、单个技能悬停说明都用它。
> 「说明说明名」只用于两处：角色悬停说明里的技能名、技能栏按钮上的技能名。

### 9.2 导表怎么做

1. 用 Excel 打开 `Table/Design/设计表.xlsx`，改完保存并关闭；
2. 回到 Godot 编辑器，按 **Ctrl + Shift + T**，或点顶部工具菜单「检查并转换表格」；
3. 检查生成的 `Table/Csv/*.csv` 和 `DataTables.gd` 是否符合预期；
4. 重新运行游戏。

生成器实现见 [Run.gd](addons/excel_to_gd/Run.gd)（`ExcelToCsv.gd` → `CsvToGd.gd`）。

### 9.3 三条铁律

1. **只改设计表**，不要手改 CSV 或 `DataTables.gd`（文件头写着“请勿手动修改”，下次导表会覆盖）。
2. **改完必须导表**，否则运行时读到的还是旧数据。
3. **设计表和导表产物一起提交**，避免源表与生成结果不一致。

---

## 10. 美术、音频与特效

### 10.1 资源目录

| 目录 | 内容 |
| --- | --- |
| `assets/textures/hero/` | 角色大立绘、横置形态图、选角用图 |
| `assets/textures/card/` | 卡面 |
| `assets/textures/battle/` | 战斗界面素材、命格图标、状态图标 |
| `assets/textures/lobby/` | 登录/大厅/准备室背景、主题 `ui_theme.tres` |
| `assets/textures/affix/` | 词缀图标 |
| `assets/media/audio/` | 背景音乐（lobby、battle1~6、win/lose）、角色语音 |
| `assets/media/sfx/` | 界面与战斗短音效 |
| `assets/fonts/` | 字体 |

### 10.2 按名字取资源

[AssetIndex](scripts/framework/AssetIndex.gd) 在启动时扫描 `assets/`，按**文件名**（忽略大小写和扩展名）建索引；[Art](scripts/ui/art.gd) 再封装成 `card_face()` / `role_hero()` / `status_icon()` 这类语义接口。

索引顺序有讲究：**先收本层文件、再进子目录，且两层都按名字排序**。否则编辑器里和导出包里可能取到同名但不同路径的两张图（比如正式卡面和备用图）。

### 10.3 音频

[audio.gd](scripts/client/audio.gd) 负责：

- 主界面音乐、战斗音乐（随机且不重复）、胜负音乐；
- 出牌、命中、受伤、治疗、士气、星石、选将等音效；
- 角色语音（轮到该角色时播放）；
- 多开时只有当前聚焦的窗口出声（失焦自动压低音量），设置里可改成“后台播放”。

音量设置保存在各自窗口的 `config[_N].cfg` 的 `[设置]` 段。

### 10.4 特效

- 斩击、魔弹：3D 素材放在 `scenes/prefabs/effects/slash3D/`、`magicBullet3D/`，通过 `SubViewport` 渲染成 2D 预制体再挂到战斗界面；
- 发牌、弃牌、治疗、受击飘字、行动播报（出牌 / 技能名）、状态图标、点击星屑：2D 预制体；
- [EffectWarmer](scripts/effects/effect_warmer.gd) 在启动时把每种特效离屏渲染两帧，**提前编译着色器**，避免第一次出手卡一下；
- 要加新特效：在 `scenes/prefabs/effects/` 做预制体 → 在 `EffectWarmer.特效预制表` 登记 → 在战斗界面按卡名/技能触发。

---

## 11. 测试与调试

### 11.1 headless 自检（不开窗口）

```powershell
powershell -ExecutionPolicy Bypass -File tests\runSelfCheck.ps1
# 或直接跑 headless 场景（多代理并行/CI 用这条，避免固定临时文件互相覆盖）：
# "D:\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path <工程目录> res://tests/selfCheck.tscn
```

- 运行器是 [selfCheck.tscn](tests/selfCheck.tscn) / [selfCheck.gd](tests/selfCheck.gd)；
- 会遍历 `tests/cases/` 下全部用例（当前 62 个），逐条打印 `[通过] / [失败]`，最后一行是汇总；
- 有失败时退出码为 1；
- 增删了素材/场景后，加 `-导入` 先重导一次；
- 引擎路径默认写死在本机 Steam 目录，换机器时用 `-EnginePath` 指定。

用例覆盖：数据与素材、界面版面、音频、战斗交互、指示器、角色分配、强制弃牌、阴阳师/月女/圣弓等技能边界、协议字段、场景资源完整性，以及 13 名 3★/3.5★ 角色、F1~F9 公共能力（额外行动/指示物/基础效果/伤害转移/额外回合/牌库顶/跨玩家）和客户端角色特性收口。

### 11.2 端到端联机测试

```powershell
powershell -ExecutionPolicy Bypass -File tests\runLanPlay.ps1 -窗口数 4
```

- 拉起 N 个客户端窗口，自动跑“登录 → 大厅 → 建房/进房 → 准备 → 开局 → 出牌”；
- 日志写到工程外的 `../_联调日志`，每次运行前清空；
- **窗口数要和房间人数一致**，否则永远凑不齐、开不了局。

### 11.3 一键多开（F9 / F10 / F11）

| 快捷键 | 效果 |
| --- | --- |
| **F9** | 打开 4 个测试窗口（本地模式，不自动开局） |
| **F10** | 打开 4 个窗口，自动进同一房间并准备 |
| **F11** | 打开 6 个窗口，自动进入六人房 |

- 双击 `tests/启动多开.bat` 是默认 4 开；
- 快捷键需要自己绑：右键 `.bat` → 发送到桌面快捷方式 → 属性 → 设置快捷键；
- 不同数量/自动开局通过“目标”末尾追加参数实现，例如 `"...\启动多开.bat" -Count 6 -Auto`；
- 脚本会先杀掉上一批带 `--slot=` 的本工程进程，不会越开越多；
- 窗口按屏幕宫格自动摆位；布局参数写在 Godot 的 `user://shared.cfg`（Windows 下为 `%APPDATA%\Godot\app_userdata\<工程名>\shared.cfg`）。

也可以在 Godot 编辑器里用插件「多开测试」（`addons/multi_open`）的菜单启动。

### 11.4 作弊 / 调试模式

建房面板有「开启作弊 / 调试模式」勾选项；勾上后**房间内所有玩家**都能用测试键（不是房主特权）。F10/F11 自动开局拉起的窗口默认开启。

战斗界面左上角会出现一块可拖拽的提示，键位如下（见 [battle_mobile.gd](scripts/ui/battle_mobile.gd) 的 `测试指令表`）：

| 按键 | 效果 |
| --- | --- |
| `0` | 跳过当前行动玩家的回合 |
| `1` | 给自己发 4 张【圣光】 |
| `2` | 给自己发每个技能的技能牌 |
| `3` | 发 3 张同系斩 + 3 张异系法术；再按清空手牌 |
| `4` | 当前倒计时压到 1 秒 |
| `5` | 双方士气拉满到 99 |
| `6` | 自己标识物拉满；再按清空 |
| `7` | 随机填充双方战绩区星石；再按清空 |
| `8` | 自己治疗拉满；再按清零 |
| `9` | 自己宝石补满；再按清空 |
| `~` | 退出战斗界面并断开本场战斗（仅客户端本地，不下发） |

未开调试模式时，提示不显示、指令也不响应；服务端还会再拦一道。

---

## 12. 想改点什么，去哪里找

| 我想改… | 先看这里 | 备注 |
| --- | --- | --- |
| 登录界面 | [scenes/enter.tscn](scenes/enter.tscn) / [enter.gd](scripts/ui/enter.gd) | 布局在场景里，逻辑在脚本里 |
| 大厅、建房面板 | [scenes/lobby.tscn](scenes/lobby.tscn) / [lobby.gd](scripts/ui/lobby.gd) | 人数/选角/座位按钮的 `metadata` 决定取值 |
| 准备室、分队 | [scenes/ReadyRoom.tscn](scenes/ReadyRoom.tscn) / [ready_room.gd](scripts/ui/ready_room.gd) | 座位数据来自 `Game` 快照 |
| 战斗界面排版 | [scenes/BattleUIMobile.tscn](scenes/BattleUIMobile.tscn) | 节点通过 `@export` 绑到脚本 |
| 战斗交互（出牌/选目标/技能/应战） | [battle_mobile.gd](scripts/ui/battle_mobile.gd) | 最大的脚本，建议先看目录注释 |
| 玩家头像面板 | [PlayerStatusMobile.gd](scripts/PlayerStatusMobile.gd) | 头像、状态图标、治疗/星石显示 |
| 卡牌控件 / 技能按钮 | [CardUI.gd](scripts/CardUI.gd) / [SkillUI.gd](scripts/SkillUI.gd) | |
| 战斗规则 | [battle_engine.gd](scripts/battle/battle_engine.gd) | 状态机 + 伤害流水线 |
| 某个角色的技能 | `scripts/battle/roles/role_*.gd` | 对照设计表里的技能号/提示列 |
| 跨角色独有技（借用 301/201/401…） | `scripts/battle/skills/` | 借用角色要连同触发钩子一起转发，见技能维护约定 |
| 角色特性（魔弹系别/基础效果免疫/双张魔弹） | [const.gd](scripts/core/const.gd) 的 `角色特性` 表 | 客户端与服务端共用，不要在界面里写角色号名单 |
| 技能指示器 / 头像提示 / 额外行动提示 | [const.gd](scripts/core/const.gd) 的 `技能指示器` / `额外行动提示` 表 | 技能号按当前角色的技能行取 |
| 角色/技能/卡牌数值与文案 | [Table/Design/设计表.xlsx](Table/Design/设计表.xlsx) | **改完必须导表** |
| 选角流程、随机分配 | [local_server.gd](scripts/net/local_server.gd) + [role_pick.gd](scripts/ui/role_pick.gd) | 候选池来自角色表「启用」列 |
| 网络协议字段 | [proto_schema.gd](scripts/core/proto_schema.gd) + [const.gd](scripts/core/const.gd) | 要同时改服务端、客户端、UI、测试 |
| 房主/加入/重连 | [net_manager.gd](scripts/net/net_manager.gd) / [local_server.gd](scripts/net/local_server.gd) | |
| 传输底座（TCP/Steam） | [scripts/net/](scripts/net) | 抽象类 + 两套实现 + 多路复用 |
| 局域网发现 | [discovery.gd](scripts/net/discovery.gd) | UDP 11112 + 同机 TCP 探测 |
| 多开/窗口摆位 | [config.gd](scripts/client/config.gd) / [启动多开.ps1](tests/启动多开.ps1) | 槽位端口 11130+ |
| 音效/音乐 | `assets/media/` + [audio.gd](scripts/client/audio.gd) | 按文件名查找，换文件即可 |
| 特效 | `scenes/prefabs/effects/` + [effect_warmer.gd](scripts/effects/effect_warmer.gd) | 新特效记得登记预热表 |
| 界面主题/字体 | `assets/textures/lobby/ui_theme.tres` + [ui_manager.gd](scripts/ui/ui_manager.gd) | 默认字号 20（按 1920×1080） |
| 版本号 | [project.godot](project.godot) | 只改这一处；或用「版本号工具」自动 +1 |
| 导出/打包 | [export_presets.cfg](export_presets.cfg) | 当前只有 Windows Desktop |
| 引擎裁剪 | [编译设置.gdbuild](编译设置.gdbuild) | 自定义构建用，不影响编辑器运行 |

---

## 13. 项目约定（改代码前请先看）

1. **中文命名 + 显式类型**：变量、函数、文件名大量用中文；类型一律写明，**不用 `:=`**。这是既定风格，不要为了“规范”去改成英文。
2. **服务端权威**：合法牌、合法目标、资源是否足够，最终都由服务端校验；客户端过滤只负责让玩家少点错。
3. **设计表是唯一权威**：所有表格数据先改 `设计表.xlsx`，再导表；不要手改 CSV / `DataTables.gd`。
4. **三层闭环**：加字段/加功能时，协议 schema → 服务端下发 → 客户端读取 → UI 真正使用 → 测试覆盖，缺一层就会出现“看起来接上了但没生效”。
5. **不可用的技能选项也要下发**，用 `enabled = false` 置灰，不要直接删掉——玩家需要看见“这个技能存在，但现在用不了”。
6. **生成文件不要手改**：`DataTables.gd`、CSV 都是产物；`.godot/`、`__pycache__/` 是缓存，不要提交。
7. **版本号单一来源**：只改 `project.godot`；大厅隔离、局域网发现、登录校验都读同一个值。
8. **渲染驱动保持一致**：编辑器运行与导出包使用同一个驱动（当前是 D3D12），否则同一个特效两边观感会不同。
9. **改完跑自检**：至少跑一遍 `tests/runSelfCheck.ps1`（当前 62 例）；区分“新增失败”和“原有失败”。
10. **提交前清理**：用 Excel 插件改表会生成 `.bak` / `.patch.json`，确认无误后删掉，不要提交。
11. **角色号/技能号集中配置**：客户端角色名单、魔弹系别、基础效果免疫、双张魔弹、额外行动限制文案都进 `const.gd` 的 `角色特性` / `额外行动提示` 表，不要在 `battle_mobile.gd` 里再散落 `[8, 76]` 之类的名单。
12. **借用别人独有技要转发触发钩子**：`scripts/battle/skills/` 的 helper 只负责校验与结算；借用角色必须把 `p_show_hand`、`p_timeline_2_hit`、`p_after_attack`、`p_after_magic`、`p_additional_action` 等触发钩子转发过去，否则“放置了但永远不触发”。完整约定见 [技能维护约定](项目文档/技能维护约定.md) 的「公共能力与借用技约定」。
13. **只做要求内的事**：没有明确要求时，不改任务范围外的代码、文案、配置和资源，不顺手重构、不顺手换图。工作区里未提交的改动（尤其立绘、图片、表格）一律不自行还原、覆盖或提交；发现冲突先报告，由需求方决定。
14. **清理缓存只能清缓存**：清理 `.import` 噪音只能按精确路径还原 `.import`，禁止 `git checkout` 整个资源目录；`PNG` / `JPG` / `webp` 等源资源文件不得批量还原，也不得为了“让工作区干净”而丢弃未提交的资源改动。
15. **所有代码尽量解耦**：不是只针对额外行动，而是整个工程都按“单一职责、明确接口、少共享隐式状态”来写。数据、规则、代价、行动、界面展示、网络协议不要互相绑死；能通过参数 / 返回值 / 描述表传的东西，不要靠全局标志、隐式约定或“顺手在这里补一下”耦合。改一个模块时，应尽量不要求其它无关模块跟着改。
    - 额外行动是一个具体例子：行动本身只是“用来行动”的资格；扣能量/鲜血/治疗/指示物、移除赐福、退出形态等代价与一次性效果，由授予它的技能在释放/确认时结算；`p_additional_action` 不写代价、不写一次性技能效果。
    - 判断标准：这段逻辑如果换一个调用方 / 换一个时点就失效，通常说明它绑错了地方。

---

## 14. 常见问题

**Q：按 F5 后一直停在登录界面？**
A：裸启动走的是 Steam 模式。要么先登录 Steam，要么用本地模式启动（带 `--slot=0`，注意前面的 `--`），或者直接用多开脚本。

**Q：改了设计表，游戏里没变化？**
A：没导表。回到 Godot 按 **Ctrl+Shift+T**，看 `DataTables.gd` 顶部的生成时间是否更新。

**Q：多开时两个人抢同一个座位？**
A：本地模式用昵称当身份，昵称相同就会被当成同一个人。本地模式下每个窗口默认会随机生成不同昵称，不要手动改成一样的。

**Q：房间列表里有房，却进不去？**
A：常见原因：满房、已经开局、房主已解散、双方版本不一致、房间不允许游客。状态栏会显示服务端返回的具体错误。

**Q：第一次放斩击特效会卡一下？**
A：着色器首次编译。`EffectWarmer` 已经在启动时预热；如果仍然卡，检查显卡驱动和 D3D12 缓存。

**Q：导出包和编辑器里特效不一样？**
A：编辑器与导出包用了不同的渲染驱动。`project.godot` 里当前指定 D3D12，两边要一致。

**Q：多开窗口很小 / 叠在一起？**
A：窗口按 `shared.cfg` 里的 `layout_cols` / `layout_rows` 宫格摆放；超过格数的窗口会缩小 90% 错位叠放，这是设计行为。

**Q：大厅为什么只有 4 人 / 6 人房？**
A：当前版本只做 4 人局和 6 人局，建房面板就这两个选项；服务端也会把房间人数限制在最多 6 人。

**Q：为什么代码里全是中文标识符？**
A：作者的习惯，Godot 完全支持 Unicode 标识符。全项目已经按这个风格写了 5 万行，统一改成英文的收益远小于风险。

**Q：工程根目录那几个 `_cut_*.py` 是什么？**
A：做角色立绘“绿幕抠图”的一次性脚本（依赖 numpy/Pillow/scipy），不参与游戏运行，也不影响打包。`__pycache__/` 是它们的缓存。

---

## 15. 名词表

| 名词 | 含义 |
| --- | --- |
| **命格** | 角色与卡牌的流派属性：技 / 血 / 幻 / 咏 / 圣；影响牌库构成与技能体系 |
| **士气** | 队伍共用的“血条”：上限固定 15；归零即败 |
| **治疗** | 角色身上的减伤点数；受伤时可选择用治疗抵挡伤害 |
| **星石** | 队伍战绩区里的宝石 / 水晶，是购买、合成、提炼的资源 |
| **星杯** | 合成目标；某队星杯达到 5 个即获胜（`GRAIL_WIN = 5`） |
| **盖牌** | 角色面前的盖放牌区（cover），有上限；部分技能需要盖牌作代价 |
| **实例号** | 一张实体牌的身份：`序号×10000 + 牌号`。正常牌等于牌号，测试指令克隆的副本序号 ≥ 1。区域存取与客户端选中用它，规则比较先 `GConst.牌号()` 折回牌面（见 8.6） |
| **指示物** | 角色专属计数器（槽 0 / 1 / 盖牌槽），上限来自角色表的「指示物」列 |
| **横置 / 形态** | 角色卡横置状态（tap）；部分角色有专属形态图 |
| **选角策略** | 建房时的角色分配方式：随机 / 三选一 / 五选一 / 任选 |
| **布座模式** | 建房时的座位规则：乱序 / 间隔（红蓝交替） |
| **快照** | 服务端下发的完整对局状态，协议号 `Game` |
| **询问 / 回复** | 服务端下发 `CmdReq` 让玩家做选择，客户端回 `Action` 或 `Respond` |
| **房主** | 建房的人；其进程内运行权威服务端 |
| **底座** | 传输层实现：局域网 TCP 或 Steam P2P |
| **槽位** | 多开时每个窗口的编号（0~7），决定配置文件、昵称、窗口摆位 |
| **留座** | 选角开始后掉线，服务端保留座位等待重连；准备室阶段不留座 |
| **观战** | 不占战斗座位、只收快照的玩家；上限 16 人 |
| **自检** | `tests/selfCheck` 跑的 headless 用例测试 |

---

## 附录 A：关键文件速查

| 文件 | 作用 |
| --- | --- |
| [project.godot](project.godot) | 工程入口：主场景、autoload、分辨率、渲染、版本号 |
| [scenes/Main.tscn](scenes/Main.tscn) | 唯一主场景 |
| [scripts/ui/main.gd](scripts/ui/main.gd) | 主场景逻辑：背景、界面层、TAB 玩家列表、自动开局 |
| [scripts/ui/ui_manager.gd](scripts/ui/ui_manager.gd) | 界面切换与浮层管理 |
| [scripts/net/net_manager.gd](scripts/net/net_manager.gd) | 房主/加入编排、统一收发 |
| [scripts/net/local_server.gd](scripts/net/local_server.gd) | 权威服务端：房间、座位、选角、开局、心跳 |
| [scripts/battle/battle_engine.gd](scripts/battle/battle_engine.gd) | 战斗状态机与规则 |
| [scripts/battle/battle_role.gd](scripts/battle/battle_role.gd) | 角色基类与全部钩子定义 |
| [scripts/ui/battle_mobile.gd](scripts/ui/battle_mobile.gd) | 战斗界面与交互 |
| [scripts/core/const.gd](scripts/core/const.gd) | 协议号、枚举、规则常量、技能号 |
| [scripts/core/proto_schema.gd](scripts/core/proto_schema.gd) | 协议字段表 |
| [Table/TableScripts/DataTables.gd](Table/TableScripts/DataTables.gd) | 生成的数据表（勿手改） |
| [tests/启动多开.ps1](tests/启动多开.ps1) | 多开脚本 |
| [tests/runSelfCheck.ps1](tests/runSelfCheck.ps1) | headless 自检入口 |
| [tests/runLanPlay.ps1](tests/runLanPlay.ps1) | 端到端联机测试入口 |

## 附录 B：规模一览

| 统计项 | 数量 |
| --- | --- |
| GDScript 文件 | 212 个（运行时 128 + 插件 16 + 测试 67 + 生成表 1） |
| GDScript 行数 | 约 78,800 行 |
| 场景文件 `.tscn` | 53 个 |
| 资源文件（不含 `.import`） | 365 个 |
| 可玩角色 | 54 名（角色数据 71 条，含未启用 17 条） |
| 技能 | 414 条（本批 13 角色 59 条） |
| 卡牌 | 155 行（含 5 张虚拟牌，实体牌库 150 张） |
| 自检用例 | 62 个 |
| 协议号 | 基础 1~24 + 战斗 101~112 + 扩展 113/114 |

## 附录 C：更多文档

- [README.md](README.md)：原开发记录、插件说明、历史约定；
- [tests/多开测试说明.md](tests/多开测试说明.md)：多开脚本的详细用法；
- `../多开与局域网实现说明.md`：联机/多开/发现机制的完整设计（工程上层目录）；
- `../Steam迁移完成度.md`：Steam 接入进度（工程上层目录）；
- [技能维护约定](项目文档/技能维护约定.md)：角色技能修改规范（改技能前必读）；
- [禁用3星与3.5星角色开发计划](项目文档/禁用3星与3.5星角色开发计划.md)：本轮 13 角色的完成状态、口径与遗留（第 0 节）；
- [开发认领任务板](项目文档/开发认领/任务板.md) / [多代理协议](项目文档/开发认领/protocol.md)：本轮任务、认领与互审记录。

---

> 本文档按当前工程状态整理。**如果文档和代码/设计表冲突，以代码和设计表为准。**
