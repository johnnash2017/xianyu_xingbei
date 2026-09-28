# 星杯传说 · 自检（headless，不开窗口）
#
# 作用：一条命令跑完 tests/用例/ 下的全部自检用例（数据素材、界面版面、音频），
#       不用每次现写临时脚本、也不用开窗口。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tests\跑自检.ps1
#   powershell -ExecutionPolicy Bypass -File tests\跑自检.ps1 -导入     # 增删素材/场景后先重导一次
#
# 参数：
#   -导入        先跑一次 --import（新增或删除素材、场景后需要）
#   -EnginePath  Godot 可执行文件路径
#   -ProjectPath Godot 工程目录（含 project.godot）

param(
    [switch]$导入,
    [string]$EnginePath = "D:\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
    [string]$ProjectPath = "d:\星杯传说工程\星杯传说2\星杯传说"
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

if ($导入) {
    "重导资源…"
    $导 = Join-Path $env:TEMP "星杯自检导入.txt"
    Start-Process -FilePath $EnginePath -ArgumentList @("--headless", "--path", $ProjectPath, "--import") `
        -RedirectStandardOutput $导 -RedirectStandardError "$导.err" -Wait -WindowStyle Hidden | Out-Null
    Get-Content $导, "$导.err" -Encoding UTF8 -ErrorAction SilentlyContinue |
        Select-String -Pattern "ERROR|SCRIPT ERROR" | Select-Object -First 5
    Remove-Item $导, "$导.err" -Force -ErrorAction SilentlyContinue
}

# 引擎输出是 UTF-8：先落盘再按 UTF-8 读，避免中文被按本地代码页解成乱码
$出 = Join-Path $env:TEMP "星杯自检.out.txt"
$错 = Join-Path $env:TEMP "星杯自检.err.txt"
$进程 = Start-Process -FilePath $EnginePath `
    -ArgumentList @("--headless", "--path", $ProjectPath, "res://tests/自检.tscn") `
    -RedirectStandardOutput $出 -RedirectStandardError $错 -PassThru -Wait -WindowStyle Hidden
Get-Content $出, $错 -Encoding UTF8 -ErrorAction SilentlyContinue |
    Select-String -Pattern "\[通过\]|\[失败\]|\[自检\]|SCRIPT ERROR|Parse Error"
Remove-Item $出, $错 -Force -ErrorAction SilentlyContinue

if ($进程.ExitCode -ne 0) {
    "自检未通过（退出码 $($进程.ExitCode)）"
    exit 1
}
"自检全部通过"
