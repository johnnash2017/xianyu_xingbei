# 多代理开发协议（认领 / 互审 / 总验收）

## 0. 环境

- 仓库：`D:\星杯传说工程\星杯传说2\xianyu_xingbei`
- 分支：`feat/disabled-3star-agents`
- 基线 commit：`3f098ef`（节日魔导重做 + 开发计划 + 本认领工具）
- Godot：`D:\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`
- 任务板：`项目文档/开发认领/tasks.json`（由 `make_tasks.py` 生成）
- 认领/评审记录：`项目文档/开发认领/claims/<任务>.json`、`reviews/<任务>.json`
- 计划：`项目文档/禁用3星与3.5星角色开发计划.md`
- 技能约定：`项目文档/技能维护约定.md`

## 1. 认领

所有命令在仓库根目录执行，Python 只用标准库。

```bash
python 项目文档/开发认领/claim.py next --agent W1
python 项目文档/开发认领/claim.py next --agent W1 --chain     # 核心代理：连续做 core 任务
python 项目文档/开发认领/claim.py finish --agent W1 --id F1 --summary "做了什么" --tests "跑了什么" --files "a.gd,b.gd"
python 项目文档/开发认领/claim.py finish --agent W1 --id F1 --blocked --summary "卡住原因"
python 项目文档/开发认领/claim.py next-fix --agent FIX1       # 修复代理：认领 needs_fix / blocked
```

### 核心链与修复

- **核心链**：F2/F3/F4/F6/F7/F8/F9 共用 `battle_engine.gd` 等文件，由同一个核心代理 `next --chain` 连续做；
  依赖处于 `review` 也可继续，同一代理可连续改同一批文件。核心代理每完成一颗仍要 `finish`，评审仍独立进行。
- **修复**：评审退回的任务进入 `needs_fix`；修复代理用 `next-fix` 认领（不能是原实现者/评审者），修完 `finish` 回 `review`，
  由**新的**评审代理复审。修复代理不修改范围外文件，不自己评审。
- 所有代理的最终短报告只写 task id、改动文件、测试/阻塞，不要贴大段代码。

- `next` 会原子地检查：依赖是否都 `done`、是否与正在 `claimed/review/reviewing/needs_fix/blocked` 的任务文件范围重叠。没有可认领时输出 `NO_TASK`。
- 认领后 **只能改任务 `files` 列出的文件**；不要为了“顺手”改共享文件、其他角色、设计表、CSV、DataTables、客户端常量。需要跨范围时：`finish --blocked` 说明原因，主代理处理。
- 不要 `git commit / checkout / reset / stash / clean`，不要删别人的文件。
- 不要运行 `--import`（会与其他代理抢 Godot 缓存）。
- 工作区是共享的：只碰自己的文件；临时文件放 `%TEMP%`，不要放仓库。
- 完成时 `--files` 写全实际改动的文件（逗号分隔），`--summary` 写清实现点，`--tests` 写跑了什么/结果。

## 2. 测试

- **实现代理**：并发实现期间不要跑全量自检（其他代理可能正在写文件，会看到临时 parse error）。
  **注意**：本机 Godot 4.7.2 的 `--check-only --script` 在 autoload 注册前编译，对引用 `Data` 等单例的脚本会误报
  `Identifier not found: Data`（未改动的现有脚本也一样）。因此：
  - 不要用 `--check-only` 判定失败；它可以用来抓纯语法错，但 `Data` 报错属环境假失败。
  - 需要自检时，用 `%TEMP%` 下的临时 SceneTree runner 正常启动项目、只加载自己的脚本/用例；跑完删除，仓库里不留临时文件。
  - 最终的全量自检由评审代理跑。
- **评审代理**：在实现批次结束后跑全量自检（此时工作区稳定）：
  ```bash
  "D:\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path "D:\星杯传说工程\星杯传说2\xianyu_xingbei" res://tests/selfCheck.tscn
  ```
  不要用 `tests/runSelfCheck.ps1`（它用固定临时文件名，多个代理会撞）。
- 全量自检以 `[自检] 用例 N 个：通过 N，失败 0` 为准；出现 `[失败]` / `SCRIPT ERROR` / `Parse Error` 都算失败。
- **评审必须自己跑一遍**，不能只信实现者的 `--tests`。

## 3. 互审

```bash
python 项目文档/开发认领/claim.py next-review --agent R1
python 项目文档/开发认领/claim.py review --agent R1 --id F1 --approve --notes "通过理由"
python 项目文档/开发认领/claim.py review --agent R1 --id F1 --issues "问题1；问题2"
```

- **禁止自评**：`next-review` 会跳过自己实现的任务，`review` 也会拒绝。
- 评审代理 **不修改代码、不提交 git、不修改任务板/别人的认领**；只读、跑测试、写 `reviews/<任务>.json`。
- 评审范围：
  1. 是否只改了任务 `files` 列出的文件（用 `git diff -- <files>`；基线 commit 之后）。
  2. 是否满足 `acceptance`；主路径和关键边界是否有测试。
  3. 上下游：调用方/被调用方、数据表/客户端/现有角色是否被破坏；同名技能 ID 是否按角色取；旧行为是否回归。
  4. 全量自检是否通过。
- 失败时把问题写进 `--issues`（`;` 或 `；` 分隔），任务进入 `needs_fix`；**不要自己修**，主代理处理。
- 通过时 `--approve`，任务进入 `done`，依赖它的任务才会解锁。

## 4. 阻塞与问题

- 实现不了/需要跨范围：`finish --blocked --summary "..."`，任务进入 `blocked`；主代理处理。
- 评审发现问题：任务进入 `needs_fix`，问题挂在任务/认领记录下；主代理修复或重新分派，再走评审。
- 不要修改 `tasks.json` 的状态/依赖/文件范围；只通过 `claim.py` 操作。

## 5. 总验收

主代理在所有批次结束后：

1. `python 项目文档/开发认领/claim.py status` 看是否有 `needs_fix/blocked/pending`。
2. 逐条看 `reviews/` 与 `git diff`。
3. 跑全量自检 + 联机（至少每批一局）。
4. 检查设计表/CSV/DataTables 一致、角色启用/选角池、文档计数。
5. 通过后才把角色启用、提交；不通过则修完重跑评审。

## 6. 禁止清单

- 禁止自评、代评、改别人的 claim/review。
- 禁止改任务范围外的文件（含 `battle_engine.gd`、`battle_player.gd`、`battle_role.gd`、`battle_mobile.gd`、`const.gd` 等共享文件，除非任务明确列了）。
- 禁止改设计表/CSV/DataTables（只有 `DATA` 任务可以）。
- 禁止提交 git、切分支、reset、stash、删资源。
- 禁止在仓库里留临时脚本/临时测试；用完删除。
- 禁止把“没跑/没通过”写成通过。
