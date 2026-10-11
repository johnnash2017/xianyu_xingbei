# 星杯传说 · 端到端联机测试
#
# 作用：拉起 N 个客户端窗口跑一遍「登录 → 大厅 → 建房/进房 → 准备 → 开局 → 出牌」，
#       汇总各窗口的结论与脚本报错。窗口由 res://tests/lanPlay.tscn（tests/lanPlay.gd）驱动，
#       跑完自己退出；日志写在工程外的 _联调日志 下，每次运行前清空。
#       多开时只有当前聚焦的那个窗口出声，失焦的窗口由 audio.gd 自动静音。
#
# 注意：窗口数要和建房时选中的人数一致（大厅默认 4 人），否则人数永远凑不齐、开不了局。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tests\runLanPlay.ps1
#   powershell -ExecutionPolicy Bypass -File tests\runLanPlay.ps1 -窗口数 2
#
# 参数：
#   -窗口数      同时拉起的客户端数量（默认 4，对应大厅默认的 4 人房）
#   -端口        这批窗口共用的端口（默认 32717；被占用时会自动往后找空闲端口）
#   -秒          等待秒数（默认 45）
#   -EnginePath  Godot 可执行文件路径
#   -ProjectPath Godot 工程目录（含 project.godot）

param(
    [int]$窗口数 = 4,
    [int]$端口 = 32717,
    [int]$秒 = 45,
    [string]$EnginePath = "D:\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
    [string]$ProjectPath = "d:\星杯传说工程\星杯传说2\xianyu_xingbei"
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# 端口得先腾出来：本机别的程序（代理、别的游戏等）占了端口的话，三个窗口谁也起不了服务端
$起点 = $端口
while ($null -ne (Get-NetTCPConnection -LocalPort $端口 -ErrorAction SilentlyContinue)) {
    "端口 $端口 已被占用，改用 $($端口 + 1)"
    $端口++
    if ($端口 -gt $起点 + 20) {
        "从 $起点 起 20 个端口都被占用，请用 -端口 指定一个空闲端口"
        exit 1
    }
}

$日志 = Join-Path (Split-Path -Parent $ProjectPath) "_联调日志"
Remove-Item -Recurse -Force $日志 -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $日志 | Out-Null

$进程 = @()
$种子 = Get-Random -Maximum 2147483000
for ($k = 0; $k -lt $窗口数; $k++) {
    $出 = Join-Path $日志 "窗口$k.out.log"
    $错 = Join-Path $日志 "窗口$k.err.log"
    # headless：测试只看逻辑，不需要渲染窗口。多开时几个窗口一起渲染会把 GPU 压垮
    # （实测 4 窗口 FPS 只有 1~4，单窗口 60），headless 下进程不画窗口，又快又稳。
    # --seed：本批共用同一个随机种子，让各窗口选到不同角色、且每批覆盖不同组合。
    $进程 += Start-Process -FilePath $EnginePath `
        -ArgumentList @("--headless", "--path", $ProjectPath, "res://tests/lanPlay.tscn", "--", "--slot=$k", "--port=$端口", "--count=$窗口数", "--seed=$种子") `
        -RedirectStandardOutput $出 -RedirectStandardError $错 -PassThru -WindowStyle Hidden
}
"已拉起 $窗口数 个窗口（端口 $端口），等 $秒 秒…"
Start-Sleep -Seconds $秒
foreach ($p in $进程) {
    if (-not $p.HasExited) { $p.Kill() }
}

# ---------- 汇总 ----------
$失败 = 0
for ($k = 0; $k -lt $窗口数; $k++) {
    # 结论优先读窗口主动落盘的“结论_k.txt”：stdout 在 Windows 重定向时是块缓冲，
    # 窗口被强杀会丢内容，落盘文件不受影响；没有该文件时再回退看 out.log
    $结论文件 = Join-Path $日志 "结论_$k.txt"
    $行文本 = $null
    if (Test-Path -LiteralPath $结论文件) {
        $行文本 = Get-Content -LiteralPath $结论文件 -Encoding UTF8 -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $行文本) {
        $文本 = Get-Content (Join-Path $日志 "窗口$k.out.log") -Encoding UTF8 -ErrorAction SilentlyContinue
        $命中 = $文本 | Select-String -Pattern "\[联机$k\] 结论=" | Select-Object -First 1
        if ($命中) { $行文本 = $命中.Line }
    }
    if ($行文本) {
        $行文本
        if ($行文本 -notmatch "结论=通过") { $失败++ }
    } else {
        "[联机$k] 结论=失败：没有输出结论行（窗口可能没起来或提前退出）"
        $失败++
    }
    $脚本错 = Get-Content (Join-Path $日志 "窗口$k.err.log") -Encoding UTF8 -ErrorAction SilentlyContinue |
        Select-String -Pattern "SCRIPT ERROR|Invalid call|Nonexistent function|Parse Error" | Select-Object -First 3
    if ($脚本错) {
        "[联机$k] 脚本报错："
        $脚本错 | ForEach-Object { "    " + $_.Line }
        $失败++
    }
}

if ($失败 -eq 0) {
    "联机测试通过（$窗口数 个窗口）"
} else {
    "联机测试未通过：$失败 项"
    exit 1
}
