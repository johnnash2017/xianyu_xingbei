# 查一遍.ps1 —— 依次跑完三个只读巡检，省得记三条命令（不改任何文件）
#
#   powershell -ExecutionPolicy Bypass -File tests\查一遍.ps1
#   powershell -ExecutionPolicy Bypass -File tests\查一遍.ps1 -详细
#
# 三个巡检各干什么、什么时候跑：
#   查死代码   —— 全仓没人引用的函数；**删函数之前先跑这个**
#   查配置键   —— 技能指示器里「配了没人读」的键；改配置表前后跑
#   查协议字段 —— proto_schema 里「只发不收 / 只收不发」的字段；**删字段之前先跑这个**
#
# 注意：三个子脚本都用 `exit` 结束，所以这里必须起子进程调用，
# 不能在同进程里 dot-source（那样第一个脚本就把本脚本退掉了）。
param(
	[switch]$详细
)

$ErrorActionPreference = "Continue"
$根目录 = Split-Path $PSScriptRoot -Parent

$巡检们 = @(
	@{ 标题 = "① 死代码（全仓没人引用的函数）"; 文件 = "查死代码.ps1" },
	@{ 标题 = "② 配置键（技能指示器里配了没人读的键）"; 文件 = "查配置键.ps1" },
	@{ 标题 = "③ 协议字段（只发不收 / 只收不发）"; 文件 = "查协议字段.ps1" }
)

$开始 = Get-Date
$失败 = @()

foreach ($项 in $巡检们) {
	Write-Output ("=" * 60)
	Write-Output $项.标题
	Write-Output ("=" * 60)

	$脚本 = Join-Path $PSScriptRoot $项.文件
	if (-not (Test-Path $脚本)) {
		Write-Output ("！没找到 {0}，跳过" -f $项.文件)
		$失败 += $项.文件
		Write-Output ""
		continue
	}

	$调用 = @("-ExecutionPolicy", "Bypass", "-File", $脚本)
	if ($详细) { $调用 += "-详细" }
	# 子进程调用：三个子脚本都以 exit 结束，必须隔离进程
	& powershell @调用
	if ($LASTEXITCODE -ne 0) { $失败 += $项.文件 }
	Write-Output ""
}

Write-Output ("=" * 60)
$用时 = [int]((Get-Date) - $开始).TotalSeconds
if ($失败.Count -gt 0) {
	Write-Output ("跑完了，但有 {0} 个巡检返回非 0：{1}" -f $失败.Count, ($失败 -join '、'))
	exit 1
}
Write-Output ("三个巡检都跑完了（用时 {0} 秒）。结论只能当线索，删任何东西前先想清对端。" -f $用时)
exit 0
