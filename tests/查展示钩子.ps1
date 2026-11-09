# 查展示钩子.ps1 —— 检查「公开亮牌」有没有绕过统一入口（只读，不改任何文件）
#
# 为什么要这个：牌面要让全场看到时，必须同时做两件事 ——
#   ① 客户端摊牌（Card.Show 广播）
#   ② 服务端「展示手牌」钩子 p_show_hand（封印师的五系封印靠它结算）
# 手写广播很容易只做①，结果牌看得见、封印不触发（言灵术踩过一次）。
# 现在统一入口在 battle_engine.gd：
#   展示牌(pid, cards)            —— 非手牌来源（牌库 / 盖牌区 / 弃牌堆 / 场上）只亮
#   展示手牌(pid, cards)          —— 手牌公开亮出（亮牌 + 触发封印）
#   私下看牌(pid, cards)          —— 只给本人看
#   展示手牌并弃 / 展示手牌进盖牌 —— 亮完顺手移动
#
# 这个脚本列出「还在手写 Card.Show 广播」的位置，并标注同一函数里有没有展示钩子：
#   已带钩子 / 未带钩子。未带钩子的要逐个确认：牌是不是从手里亮出来的？
#   是 → 改成 engine.展示手牌；不是（盖牌区 / 牌库 / 别人的弃牌）→ 改成 engine.展示牌。
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File tests\查展示钩子.ps1
#   powershell -ExecutionPolicy Bypass -File tests\查展示钩子.ps1 -详细
param(
	[switch]$详细,
	[string]$根目录 = (Split-Path $PSScriptRoot -Parent)
)

$ErrorActionPreference = "Stop"

$脚本目录 = Join-Path $根目录 "scripts\battle"
$文件们 = Get-ChildItem -Path $脚本目录 -Recurse -Filter *.gd | Sort-Object FullName
# 统一入口自己就在做广播，不参与检查
$入口函数 = @('展示牌', '展示手牌', '私下看牌', '展示手牌并弃', '展示手牌进盖牌', '展示牌库顶')

$总记 = 0
$未带钩子数 = 0

foreach ($文件 in $文件们) {
	$行 = [System.IO.File]::ReadAllLines($文件.FullName, [System.Text.Encoding]::UTF8)
	$命中 = @()
	for ($i = 0; $i -lt $行.Count; $i++) {
		if ($行[$i] -notmatch 'CardMsgType\.Show') { continue }
		# 找所在函数（往上找 func，往下找到下一个 func）
		$起 = $i
		while ($起 -gt 0 -and $行[$起] -notmatch '^func ') { $起-- }
		$止 = $i
		while ($止 -lt $行.Count - 1 -and $行[$止 + 1] -notmatch '^func ') { $止++ }
		$函数体 = ($行[$起..$止] -join "`n")
		# 统一入口 / 老写法都算「有钩子」
		$有钩子 = ($函数体 -match '展示手牌|push_show_hand|take_from_hand\([^)]*,[^)]*,[^)]*\)|私下看牌')
		$函数名 = ($行[$起] -replace '^func\s+', '' -replace '\(.*', '')
		if ($入口函数 -contains $函数名) { continue }
		$命中 += [pscustomobject]@{
			行号   = $i + 1
			函数   = $函数名
			有钩子 = $有钩子
		}
	}
	if ($命中.Count -eq 0) { continue }
	$相对 = $文件.FullName.Substring($根目录.Length).TrimStart('\', '/')
	$未带 = @($命中 | Where-Object { -not $_.有钩子 })
	$总记 += $命中.Count
	$未带钩子数 += $未带.Count
	if ($未带.Count -gt 0) {
		Write-Host ("[未带钩子] " + $相对) -ForegroundColor Yellow
		foreach ($项 in $未带) {
			Write-Host ("    第 {0} 行  函数 {1}" -f $项.行号, $项.函数)
		}
	} elseif ($详细) {
		Write-Host ("[已带钩子] " + $相对) -ForegroundColor DarkGray
		foreach ($项 in $命中) {
			Write-Host ("    第 {0} 行  函数 {1}" -f $项.行号, $项.函数)
		}
	}
}

Write-Host ""
Write-Host ("手写 Card.Show 广播 {0} 处，其中同函数没有任何展示钩子的 {1} 处。" -f $总记, $未带钩子数)
if ($未带钩子数 -gt 0) {
	Write-Host "逐个确认牌源：手牌公开亮出 → engine.展示手牌；盖牌区/牌库/别人的弃牌 → engine.展示牌。"
} else {
	Write-Host "没有发现漏展示钩子的手写广播。"
}
