# 查死代码.ps1 —— 扫出「全仓没人引用」的函数（只读，不改任何文件）
#
# 判定口径：把 scripts/ + tests/ 下所有 .gd、scenes/ 下所有 .tscn 拼成一份文本，
# 对每个 func 名做「词边界出现次数」统计；只出现 1 次（＝只有它自己的定义）就算无引用。
#   · 连 .tscn 一起扫，是为了cover「信号按名字连到脚本方法」这种情况
#   · 只漏报不误报：注释、日志里出现同名也算「有引用」
#   · 名字拼出来的调用（call("p_" + x)）扫不出来；本项目钩子都写字面量，影响不大
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tests\查死代码.ps1
#   powershell -ExecutionPolicy Bypass -File tests\查死代码.ps1 -详细
param(
	[switch]$详细,
	[string]$根目录 = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"

# 引擎 / 框架会自己调的，不算死代码
$回调名单 = @(
	"_init", "_ready", "_process", "_physics_process", "_input", "_unhandled_input",
	"_unhandled_key_input", "_gui_input", "_notification", "_enter_tree", "_exit_tree",
	"_draw", "_initialize", "_get_property_list", "_to_string"
)

function 读文件([string]$路径) {
	return [System.IO.File]::ReadAllText($路径, [System.Text.Encoding]::UTF8)
}

# ---------- 收集待扫文件 ----------
$脚本文件 = @(Get-ChildItem -Path (Join-Path $根目录 "scripts"), (Join-Path $根目录 "tests") `
		-Recurse -Include *.gd -File -ErrorAction SilentlyContinue)
$场景文件 = @(Get-ChildItem -Path (Join-Path $根目录 "scenes") `
		-Recurse -Include *.tscn -File -ErrorAction SilentlyContinue)

$全文本 = New-Object System.Text.StringBuilder
foreach ($f in $脚本文件) { [void]$全文本.AppendLine((读文件 $f.FullName)) }
foreach ($f in $场景文件) { [void]$全文本.AppendLine((读文件 $f.FullName)) }
$全文本 = $全文本.ToString()

# ---------- 逐个函数统计 ----------
$结果 = @()
$总计 = 0
foreach ($f in $脚本文件) {
	$文本 = 读文件 $f.FullName
	$定义们 = [regex]::Matches($文本, '(?m)^func ([^\s\(]+)\(')
	foreach ($m in $定义们) {
		$总计++
		$名 = $m.Groups[1].Value
		if ($回调名单 -contains $名) { continue }
		# 词边界：后面不能紧跟字母/数字/下划线/汉字（否则 在场牌 会命中 在场牌堆）
		$次数 = ([regex]::Matches($全文本, [regex]::Escape($名) + '(?![0-9A-Za-z_\u4e00-\u9fff])')).Count
		if ($次数 -le 1) {
			$结果 += [pscustomobject]@{ 文件 = $f.FullName.Substring($根目录.Length + 1); 函数 = $名 }
		}
	}
}

# ---------- 输出 ----------
Write-Output ("扫描脚本 {0} 个、场景 {1} 个；函数共 {2} 个" -f $脚本文件.Count, $场景文件.Count, $总计)
if ($结果.Count -eq 0) {
	Write-Output "没有发现无引用的函数。"
	exit 0
}

Write-Output ("无引用的函数：{0} 个" -f $结果.Count)
Write-Output ""

$按文件 = $结果 | Group-Object 文件 | Sort-Object Name
foreach ($组 in $按文件) {
	Write-Output ("{0}（{1} 个）" -f $组.Name, $组.Count)
	foreach ($项 in ($组.Group | Sort-Object 函数)) {
		Write-Output ("    {0}" -f $项.函数)
	}
	if (-not $详细) { continue }
}
if (-not $详细) {
	Write-Output ""
	Write-Output "（加 -详细 可看每个函数的全部位置；删之前请确认 .tscn 与本脚本都没引用）"
}
exit 0
