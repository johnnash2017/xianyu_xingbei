# 查协议字段.ps1 —— 检查 proto_schema 里每个字段「有没有人发 / 有没有人读」（只读，不改任何文件）
#
# 为什么需要：协议字段是两端约定，删错一个就是「界面永远收不到」（曾经差点删掉
# option_switch_desc —— 它确实没被客户端读，但有测试在防它过协议）。
# 这个脚本把「发/读」两侧的引用数摆出来，删任何字段之前先看一眼。
#
# 口径：
#   发（写）＝其它脚本里出现  "字段名":       （构造字典时写下这个键）
#   读      ＝ 其它脚本里出现  .get("字段名"  （从字典里取值）
#   tests/ 也算在内 —— 被测试用到的字段不能删。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tests\查协议字段.ps1
#   powershell -ExecutionPolicy Bypass -File tests\查协议字段.ps1 -详细
param(
	[switch]$详细,
	[string]$根目录 = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"

function 读文件([string]$路径) {
	return [System.IO.File]::ReadAllText($路径, [System.Text.Encoding]::UTF8)
}

$模式文件 = Join-Path $根目录 "scripts\core\proto_schema.gd"
$模式文本 = 读文件 $模式文件

# ---------- 1. 逐个消息块抠字段 ----------
# 消息头有两种写法：SUB 里的 "Command": {  和 TABLE 里的 GConst.Msg.LoginReq: {
# 块尾统一认「下一行以单个 tab + } 开头的那个闭括号」，避免把后面 TABLE 的字段算进来。
$字段表 = @()
$消息头 = @([regex]::Matches($模式文本, '(?m)^\t(?:"([A-Za-z]+)"|GConst\.Msg\.([A-Za-z0-9_]+)):\s*\{'))
foreach ($h in $消息头) {
	$消息名 = if ($h.Groups[1].Success) { $h.Groups[1].Value } else { "Msg." + $h.Groups[2].Value }
	$尾 = [regex]::Match($模式文本.Substring($h.Index), '(?m)^\t\}')
	if (-not $尾.Success) { continue }
	$块 = $模式文本.Substring($h.Index, $尾.Index)
	$字段们 = [regex]::Matches($块, '(?m)^\t\t(\d+):\s*\{"n":\s*"([^"]+)"')
	foreach ($f in $字段们) {
		$字段表 += [pscustomobject]@{ 消息 = $消息名; 字段号 = [int]$f.Groups[1].Value; 字段 = $f.Groups[2].Value }
	}
}

if ($字段表.Count -eq 0) { Write-Error "没在 proto_schema.gd 里解析到字段（格式变了？）"; exit 1 }

# ---------- 2. 其它脚本（含 tests）准备文本 ----------
$其它文件 = @(Get-ChildItem -Path (Join-Path $根目录 "scripts"), (Join-Path $根目录 "tests") `
		-Recurse -Include *.gd -File -ErrorAction SilentlyContinue |
		Where-Object { $_.FullName -ne (Resolve-Path $模式文件).Path })

$行缓存 = @{}
$总文本 = New-Object System.Text.StringBuilder
foreach ($f in $其它文件) {
	$文 = 读文件 $f.FullName
	$行缓存[$f.FullName] = $文 -split "`n"
	[void]$总文本.AppendLine($文)
}
$总文本 = $总文本.ToString()

# ---------- 3. 统计每个字段的发 / 读 ----------
$结果 = @()
foreach ($项 in $字段表) {
	# 太通用的短名字（id / text / args …）到处都是，统计没意义，跳过
	if ($项.字段.Length -lt 4) { continue }
	# 「写」认两种写法：字典字面量 "字段":  和 下标赋值 xxx["字段"] =
	$写 = ([regex]::Matches($总文本, '"' + [regex]::Escape($项.字段) + '"\s*:|\[\s*"' + [regex]::Escape($项.字段) + '"\s*\]\s*=')).Count
	# 「读」认两种写法：xxx.get("字段" 和 xxx["字段"]
	$读 = ([regex]::Matches($总文本, '(\.get\(\s*"|\[\s*")' + [regex]::Escape($项.字段) + '"')).Count
	$位置 = "-"
	if ($读 -eq 0) {
		$命中 = @()
		foreach ($f in $其它文件) {
			$行们 = $行缓存[$f.FullName]
			for ($i = 0; $i -lt $行们.Count; $i++) {
				if ($行们[$i].Contains('"' + $项.字段 + '"')) {
					$命中 += ("{0}:{1}" -f $f.Name, ($i + 1))
					break
				}
			}
			if ($命中.Count -ge 3) { break }
		}
		$位置 = $命中 -join ', '
	}
	$结果 += [pscustomobject]@{
		消息 = $项.消息; 字段号 = $项.字段号; 字段 = $项.字段; 写 = $写; 读 = $读; 位置 = $位置
	}
}

# ---------- 4. 输出 ----------
Write-Output ("proto_schema：{0} 个消息、解析到 {1} 个字段（长度 >= 4 的 {2} 个参与统计）；其它脚本 {3} 个" -f `
		$消息头.Count, $字段表.Count, $结果.Count, $其它文件.Count)
Write-Output ""

$没人读 = @($结果 | Where-Object { $_.读 -eq 0 })
$没人发 = @($结果 | Where-Object { $_.写 -eq 0 })

if ($没人读.Count -gt 0) {
	Write-Output ("① 有定义、但没有任何代码从字典里读的字段：{0} 个" -f $没人读.Count)
	foreach ($项 in ($没人读 | Sort-Object 消息, 字段号)) {
		Write-Output ("    {0}.{1}（字段 {2}）  写入 {3} 处   出现位置：{4}" -f `
				$项.消息, $项.字段, $项.字段号, $项.写, $项.位置)
	}
} else {
	Write-Output "① 每个字段都至少有一处代码在读。"
}
Write-Output ""

if ($没人发.Count -gt 0) {
	Write-Output ("② 有定义、但没有任何代码写进字典的字段：{0} 个" -f $没人发.Count)
	foreach ($项 in ($没人发 | Sort-Object 消息, 字段号)) {
		Write-Output ("    {0}.{1}（字段 {2}）" -f $项.消息, $项.字段, $项.字段号)
	}
} else {
	Write-Output "② 每个字段都至少有一处代码在写。"
}

if ($详细) {
	Write-Output ""
	Write-Output "③ 全部字段："
	foreach ($项 in ($结果 | Sort-Object 消息, 字段号)) {
		Write-Output ("    {0,-14} {1,-18} 字段 {2,3}   写 {3,3}   读 {4,3}" -f `
				$项.消息, $项.字段, $项.字段号, $项.写, $项.读)
	}
}

Write-Output ""
Write-Output "说明：这里只统计「字面量」的发/读。以下几种情况扫不出来，所以「没人读」不等于能删："
Write-Output "  · 遍历字典（for k in d）或动态拼键名"
Write-Output "  · 客户端只把整包转给别的模块再取用"
Write-Output "  · 字段只用于「过协议」本身（有测试在防它，例如 option_switch_desc）"
Write-Output "删字段前先搜 tests\ 与 .tscn，并想清楚对端（服务端/客户端）是不是在用。"
exit 0
