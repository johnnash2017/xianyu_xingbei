# 查配置键.ps1 —— 检查 GConst.技能指示器 里每个键「到底有没有代码在读」（只读，不改任何文件）
#
# 为什么要这个：这张表是 170 条技能交互配置，键写错了不会报错 ——
# 只是「静默不生效」（界面按默认值走）。这个脚本把两类问题挑出来：
#   ① 表里配了、但全仓没有任何代码读它 → 纯噪音，或者键名拼错
#   ② 每个键被多少条技能用到、代码在哪几行读
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tests\查配置键.ps1
#   powershell -ExecutionPolicy Bypass -File tests\查配置键.ps1 -详细
param(
	[switch]$详细,
	[string]$根目录 = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"

function 读文件([string]$路径) {
	return [System.IO.File]::ReadAllText($路径, [System.Text.Encoding]::UTF8)
}

$常量文件 = Join-Path $根目录 "scripts\core\const.gd"
$常量文本 = 读文件 $常量文件

# ---------- 1. 抠出 技能指示器 这一块 ----------
$块头 = $常量文本.IndexOf('const 技能指示器: Dictionary')
if ($块头 -lt 0) { Write-Error "没找到 const 技能指示器"; exit 1 }
$块尾 = $常量文本.IndexOf('static func', $块头)
if ($块尾 -lt 0) { $块尾 = $常量文本.Length }
$块 = $常量文本.Substring($块头, $块尾 - $块头)

# ---------- 2. 按「行首一个 tab + 键名 + : {」切出每一条技能 ----------
$条头们 = [regex]::Matches($块, '(?m)^\t(技能_[^\s:]+|\d+):\s*\{')
$条目 = @()
for ($i = 0; $i -lt $条头们.Count; $i++) {
	$起 = $条头们[$i].Index
	$止 = if ($i + 1 -lt $条头们.Count) { $条头们[$i + 1].Index } else { $块.Length }
	$条目 += [pscustomobject]@{ 名 = $条头们[$i].Groups[1].Value; 文 = $块.Substring($起, $止 - $起) }
}

# ---------- 3. 收集表里出现过的所有键（含嵌套的） ----------
$键们 = @([regex]::Matches($块, '"([^"\n]{1,14})"\s*:') | ForEach-Object { $_.Groups[1].Value })
$键们 = @($键们 | Sort-Object -Unique)

# ---------- 4. 其它脚本（不含 const.gd 自己）准备一份合并文本 ----------
$其它文件 = @(Get-ChildItem -Path (Join-Path $根目录 "scripts"), (Join-Path $根目录 "tests") `
		-Recurse -Include *.gd -File -ErrorAction SilentlyContinue |
		Where-Object { $_.FullName -ne (Resolve-Path $常量文件).Path })

$其它文本 = New-Object System.Text.StringBuilder
foreach ($f in $其它文件) { [void]$其它文本.AppendLine((读文件 $f.FullName)) }
$其它文本 = $其它文本.ToString()

$行缓存 = @{}
foreach ($f in $其它文件) { $行缓存[$f.FullName] = (读文件 $f.FullName) -split "`n" }

# ---------- 5. 逐个键统计 ----------
$无读 = @()
$有读 = @()
foreach ($键 in $键们) {
	$模式 = '"' + [regex]::Escape($键) + '"'
	$次 = ([regex]::Matches($其它文本, $模式)).Count
	$用在 = @()
	foreach ($e in $条目) { if ($e.文.Contains('"' + $键 + '"')) { $用在 += $e.名 } }
	$位置 = @()
	if ($次 -gt 0) {
		foreach ($f in $其它文件) {
			$行们 = $行缓存[$f.FullName]
			for ($i = 0; $i -lt $行们.Count; $i++) {
				if ($行们[$i].Contains('"' + $键 + '"')) {
					$位置 += ("{0}:{1}" -f $f.Name, ($i + 1))
					break
				}
			}
			if ($位置.Count -ge 5) { break }
		}
	}
	$项 = [pscustomobject]@{ 键 = $键; 条目数 = $用在.Count; 读取处 = $次; 位置 = ($位置 -join ', ') }
	if ($次 -eq 0) { $无读 += $项 } else { $有读 += $项 }
}

# ---------- 6. 输出 ----------
Write-Output ("技能指示器：{0} 条技能、{1} 个键；其它脚本 {2} 个" -f $条目.Count, $键们.Count, $其它文件.Count)
Write-Output ""

if ($无读.Count -gt 0) {
	Write-Output ("① 表里配了、但全仓没有代码读的键：{0} 个（噪音或拼错）" -f $无读.Count)
	foreach ($项 in ($无读 | Sort-Object 键)) {
		Write-Output ("    {0}（{1} 条技能用到）" -f $项.键, $项.条目数)
	}
} else {
	Write-Output "① 表里每个键都至少有一处代码在读。"
}
Write-Output ""

if ($详细) {
	Write-Output "② 全部键的读取情况："
	foreach ($项 in ($有读 | Sort-Object -Property @{ Expression = '条目数'; Descending = $true }, 键)) {
		Write-Output ("    {0,-12} 技能 {1,3} 条   读取 {2,2} 处   {3}" -f $项.键, $项.条目数, $项.读取处, $项.位置)
	}
} else {
	Write-Output "（加 -详细 可看每个键被多少条技能用到、代码在哪几行读）"
}
exit 0
