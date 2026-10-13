# 星杯传说 · 局域网联机版 —— 多开启动脚本
#
# 作用：一次拉起多个客户端窗口，并给每个窗口分配独立槽位与摆位（对照「多开与局域网实现说明.md」第二节）。
# 做法：
#   1. 读取屏幕可用区域（已扣除任务栏）
#   2. 按窗口数算出最接近正方形的网格（列数取开方向上取整）
#   3. 把网格参数写进「该窗口自己那份配置」，窗口启动时会自行按槽位算位置与尺寸
#   4. 用 --slot=N 把槽位钉死传给进程（最稳，窗口与槽位永远一一对应）
#   5. 声音：多开时只有当前聚焦的那个窗口出声，失焦的窗口由 audio.gd 自动静音
#   6. 用 --count=N 告诉每个窗口本批一共几个：自动开局建房时按它挑房间人数（六开就该开 6 人房，
#      否则会沿用上次记下的人数，被建成 2v2 那种 4 人房）
#
# 用法示例：
#   .\启动多开.ps1 -Count 6
#   .\启动多开.ps1 -Count 4 -Width 640
#   .\启动多开.ps1 -Count 6 -Names 阿一,小逸,水叔,稻,羊
#   .\启动多开.ps1 -Count 4 -Auto             # 自动开局：各窗口自己完成「进入游戏 → 建房/进房 → 准备」
#   .\启动多开.ps1 -Count 6 -DryRun          # 只计算不启动（预演）
#   .\启动多开.ps1 -KeepConsole              # 保留脚本控制台（排查用；默认会隐藏，避免堆黑框）
#
# 重复运行：脚本开跑前会先把「上一批」窗口（带 --slot= 的本工程进程）关掉再重开，
# 所以按快捷键（F9 / F10 / F11）连点也不会越开越多；编辑器里跑出来的实例不带 --slot=，不会被误杀。
#
# 参数：
#   -Count        窗口数量（1~8）
#   -Width        固定窗口宽度（像素），0 表示等比铺满格子
#   -Names        给尚未初始化的槽位批量起名（已有配置不覆盖）
#   -EnginePath   Godot 可执行文件路径（留空自动探测：.vscode/settings.json → PATH → 常见 Steam 安装）
#   -ProjectPath  Godot 工程目录（含 project.godot；留空取脚本上一级，即本工程）
#   -Auto         自动开局（给游戏加 --auto：进游戏后自动建房/进同一间房/准备）
#   -DryRun       只计算并打印，不实际启动
#   -KeepConsole  保留脚本控制台窗口（默认隐藏）

param(
    [int]$Count = 4,
    [int]$Width = 0,
    [string]$Names = "",
    [string]$EnginePath = "",
    [string]$ProjectPath = "",
    [switch]$Auto,
    [switch]$DryRun,
    [switch]$KeepConsole
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ---------- 路径自适应 ----------
# 工程目录：脚本就放在工程的 tests/ 里，默认取它的上一级；可用 -ProjectPath 覆盖
if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
    $ProjectPath = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}
# 引擎可执行文件：按「显式参数 → 工程/工作区的 .vscode/settings.json → PATH → 常见 Steam 安装」依次探测，不再写死绝对路径
function Resolve-GodotExe {
    foreach ($根 in @((Join-Path $PSScriptRoot ".."), (Join-Path $PSScriptRoot "..\.."))) {
        $cfg = Join-Path $根 ".vscode\settings.json"
        if (Test-Path $cfg) {
            try {
                $json = Get-Content -LiteralPath $cfg -Raw -Encoding UTF8 | ConvertFrom-Json
                $路径 = $json.'godotTools.editorPath.godot4'
                if ($路径 -and (Test-Path $路径)) { return (Resolve-Path $路径).Path }
            } catch { }
        }
    }
    # 工程内/工作区的便携版 Godot：同级或 tools\ 下的 godot*.exe
    foreach ($目录 in @((Join-Path $PSScriptRoot ".."), (Join-Path $PSScriptRoot "..\.."),
                        (Join-Path $PSScriptRoot "..\tools"), (Join-Path $PSScriptRoot "tools"))) {
        if (-not (Test-Path $目录)) { continue }
        $命中 = Get-ChildItem -LiteralPath $目录 -Filter "godot*.exe" -File -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($命中) { return $命中.FullName }
    }
    foreach ($名 in @("godot4", "godot")) {
        $cmd = Get-Command $名 -ErrorAction SilentlyContinue
        if ($cmd) { return $cmd.Source }
    }
    $常见 = "D:\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
    if (Test-Path $常见) { return $常见 }
    return ""
}
if ([string]::IsNullOrWhiteSpace($EnginePath)) {
    $EnginePath = Resolve-GodotExe
}
if (-not $DryRun -and -not (Test-Path $EnginePath)) {
    throw "找不到 Godot 引擎可执行文件：请用 -EnginePath 指定，或在 .vscode/settings.json 里配好 godotTools.editorPath.godot4。"
}

# 隐藏这次运行的控制台窗口：重复按快捷键（F9 / F10 / F11）时不再堆一堆「黑框」。
# 想看到脚本输出（排查用）时加 -KeepConsole。
if (-not $KeepConsole -and -not $DryRun) {
    try {
        if (-not ("Win.Console" -as [type])) {
            Add-Type -Namespace Win -Name Console -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool ShowWindow(System.IntPtr hWnd, int nCmdShow);
[DllImport("kernel32.dll")] public static extern System.IntPtr GetConsoleWindow();
'@ -ErrorAction SilentlyContinue
        }
        [Win.Console]::ShowWindow([Win.Console]::GetConsoleWindow(), 0) | Out-Null
    } catch { }
}

if ($Count -lt 1) { $Count = 1 }
if ($Count -gt 8) { $Count = 8 }

# ---------- 0. 先关掉上一批 ----------
# 重复按快捷键（F9 / F10 / F11）时，先把上一次多开出来的窗口关掉再重开，
# 否则窗口会越开越多、控制台也越堆越多（就是那一个个「黑框」）。
# 只认带 --slot= 的进程：那是本脚本拉起来的窗口；编辑器里跑出来的实例没有这个参数，不会被误杀。
$引擎名 = [System.IO.Path]::GetFileName($EnginePath)
function Get-本工程多开窗口 {
    try {
        return @(Get-CimInstance Win32_Process -Filter "Name='$引擎名'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine.Contains($ProjectPath) -and $_.CommandLine.Contains("--slot=") })
    } catch {
        return @()
    }
}
$旧窗口 = Get-本工程多开窗口
if ($旧窗口.Count -gt 0) {
    Write-Host ("关闭上一批窗口 {0} 个…" -f $旧窗口.Count)
    foreach ($p in $旧窗口) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
    # 等它们真的退出（槽位端口随之释放），最多等 3 秒
    for ($i = 0; $i -lt 30; $i++) {
        if ((Get-本工程多开窗口).Count -eq 0) { break }
        Start-Sleep -Milliseconds 100
    }
}

# ---------- 1. 屏幕可用区域（扣除任务栏）----------
Add-Type -AssemblyName System.Windows.Forms
$work = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
if ($null -eq $work -or $work.Width -le 0) {
    # 取不到就退回整屏并按经验扣一条任务栏高度
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $work = New-Object System.Drawing.Rectangle($bounds.X, $bounds.Y, $bounds.Width, ($bounds.Height - 48))
}

# ---------- 2. 网格 ----------
# 按窗口数选宫格，尽量铺满屏幕且接近方形：列数取「窗口数的平方根向上取整」，
# 行数＝装下这些窗口所需的行数（6 个 → 3 列 × 2 行、4 个 → 2×2、8 个 → 3×3 最后一格留空）。
# 窗口数超过格子数时（只在少数取值上出现，如 7 个 → 3×3 正好够），多出来的窗口
# 由 config.gd 在同一格内、原窗口下方错开一段叠上去（尺寸不缩，靠标题栏区分）
$cols = [int][Math]::Ceiling([Math]::Sqrt([double]$Count))
$rows = [int][Math]::Ceiling([double]$Count / [double]$cols)
$cellW = [int]($work.Width / $cols)
$cellH = [int]($work.Height / $rows)

Write-Host "屏幕可用区域: $($work.Width)x$($work.Height)  网格: ${cols}列 x ${rows}行  格子: ${cellW}x${cellH}"

# ---------- 3. 槽位配置文件 ----------
# user:// 目录（Godot 的 app_userdata，按工程名分目录）
$projectName = "星杯传说"
$userDir = Join-Path $env:APPDATA "Godot\app_userdata\$projectName"
if (-not (Test-Path $userDir)) {
    New-Item -ItemType Directory -Force -Path $userDir | Out-Null
}

function Get-SlotConfigPath([int]$slot) {
    # 第一个槽位沿用单开存档，保证单开行为与改造前一致
    if ($slot -eq 0) { return (Join-Path $userDir "config.cfg") }
    return (Join-Path $userDir ("config_{0}.cfg" -f ($slot + 1)))
}

function Set-SlotLayout([int]$slot, [string]$nickname) {
    $path = Get-SlotConfigPath $slot
    $lines = @()
    if (Test-Path $path) {
        # 显式按 UTF-8 读取，避免中文昵称被 ANSI 误读后写坏
        $lines = @([System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8))
    }

    $hasNick = ($lines | Select-String -Pattern '^\s*nickname\s*=' -Quiet)
    # 解析已有内容（行级处理，保留其它键）
    $out = New-Object System.Collections.Generic.List[string]
    $hasUser = $false
    $inLayout = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*\[user\]\s*$') {
            $hasUser = $true
            $out.Add("[user]")
            if ($nickname -ne "" -and -not $hasNick) {
                $out.Add(('nickname="{0}"' -f $nickname))
            }
            continue
        }
        if ($line -match '^\s*\[layout\]\s*$') {
            $inLayout = $true
            continue
        }
        if ($inLayout) {
            if ($line -match '^\s*\[') { $inLayout = $false }
            else { continue }   # 丢弃旧的 layout 段，下面统一重写
        }
        $out.Add($line)
    }

    if (-not $hasUser) {
        $out.Add("[user]")
        if ($nickname -ne "" -and -not $hasNick) {
            $out.Add(('nickname="{0}"' -f $nickname))
        }
    }
    # 摆位参数（cols/rows）不写在这里：同一批窗口必须共用一份，写在下面 shared.cfg 的 [shared] 段，
    # 否则某个槽位的历史值不同，就会把同批窗口摆成不同大小/互相重叠
    [System.IO.File]::WriteAllLines($path, $out, (New-Object System.Text.UTF8Encoding $false))
    return $path
}

function Set-SharedLayout([int]$cols, [int]$rows, [int]$count) {
    $path = Join-Path $userDir "shared.cfg"
    $lines = @()
    if (Test-Path $path) {
        # 显式按 UTF-8 读取，避免中文被 ANSI 误读后写坏
        $lines = @([System.IO.File]::ReadAllLines($path, [System.Text.Encoding]::UTF8))
    }

    $out = New-Object System.Collections.Generic.List[string]
    $hasShared = $false
    $inShared = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*\[shared\]\s*$') {
            $hasShared = $true
            $out.Add("[shared]")
            $out.Add("layout_cols=$cols")
            $out.Add("layout_rows=$rows")
            $out.Add("layout_count=$count")
            $inShared = $true
            continue
        }
        if ($inShared) {
            if ($line -match '^\s*\[') { $inShared = $false }
            elseif ($line -match '^\s*layout_(cols|rows|count)\s*=') { continue }   # 旧的宫格键丢掉：上面已按本次多开数重写
            # 段里其它键（如上次开房记下的人数 / 选角）原样保留，不能被多开脚本清掉
        }
        $out.Add($line)
    }
    if (-not $hasShared) {
        $out.Add("[shared]")
        $out.Add("layout_cols=$cols")
        $out.Add("layout_rows=$rows")
        $out.Add("layout_count=$count")
    }

    [System.IO.File]::WriteAllLines($path, $out, (New-Object System.Text.UTF8Encoding $false))
    return $path
}

# ---------- 3.5 共享摆位参数 ----------
# 所有窗口读同一份宫格（config.gd 的 _apply_layout 从 shared.cfg 的 [shared] 段读 layout_cols/rows）
$sharedCfg = Set-SharedLayout $cols $rows $Count
Write-Host "共享摆位: ${cols}列 x ${rows}行 → $sharedCfg"

# ---------- 4. 启动 ----------
# 昵称支持「逗号分隔」的字符串形式（-Names 阿一,小逸,水叔）
$nameList = @()
if ($Names -ne "") {
    $nameList = @($Names -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
}

for ($k = 0; $k -lt $Count; $k++) {
    $nick = ""
    if ($k -lt $nameList.Count) { $nick = $nameList[$k] }
    $nickDisp = "（沿用配置）"
    if ($nick -ne "") { $nickDisp = $nick }
    $cfg = Set-SlotLayout $k $nick
    # 与 config.gd 的 _apply_layout 保持一致：先按「格数」取模落到宫格，超出的窗口再在同一格内错位叠加
    $格数 = $cols * $rows
    $格号 = $k % $格数
    $组内序 = [int][Math]::Floor($k / $格数)
    $col = $格号 % $cols
    $row = [int][Math]::Floor($格号 / $cols)
    $叠 = ""
    if ($组内序 -gt 0) { $叠 = " 同格第$($组内序 + 1)个（错位叠加）" }

    if ($DryRun) {
        Write-Host ("[预演] 槽位 {0}: 第{1}列第{2}行{3}  配置={4}  昵称={5}" -f $k, $col, $row, $叠, $cfg, $nickDisp)
        continue
    }

    Write-Host ("启动槽位 {0}（第{1}列第{2}行{3}）昵称={4}" -f $k, $col, $row, $叠, $nickDisp)
    # --slot 用「--」分隔传成用户参数，避免被引擎当作自身参数；-Auto 再加个 --auto 让窗口自己开局
    # 声音：多开时只有当前聚焦的窗口出声，其余窗口由 audio.gd 按焦点自动静音
    # 槽位是显式指定的、不会互相抢，所以一口气全拉起来（不逐个等待，启动更快）
    # --count 让窗口知道本批一共几个：自动开局建房时按它挑房间人数（否则会沿用上次记下的人数）
    $用户参数 = @("--path", $ProjectPath, "--", "--slot=$k", "--count=$Count")
    if ($Auto) { $用户参数 += "--auto" }
    Start-Process -FilePath $EnginePath -ArgumentList $用户参数
}

if (-not $DryRun) {
    Write-Host ""
    Write-Host "已拉起 $Count 个窗口。"
    Write-Host "联机方式：任一窗口点「创建房间」当房主，其余窗口点「加入 127.0.0.1」；跨机则填房主局域网 IP 或点「搜索局域网房间」。"
}
