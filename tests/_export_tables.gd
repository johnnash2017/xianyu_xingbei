extends SceneTree
## DATA 任务用的导表脚本（设计表.xlsx → Table/Csv/*.csv → Table/TableScripts/DataTables.gd）。
## 只调用工程自带 addons/excel_to_gd 的转换器，不手改生成文件。
##
## 用法：
##   godot --headless --path <工程> --script res://tests/_export_tables.gd
## 可选参数（放在 -- 之后）：
##   --csv-dir=user://xxx   导出 CSV 的目录（默认 res://Table/Csv）
##   --out=user://xxx.gd    生成的 DataTables.gd（默认 res://Table/TableScripts/DataTables.gd）
## 临时验证时用 user:// 目录，避免覆盖仓库文件。

const ExcelToCsv脚本: GDScript = preload("res://addons/excel_to_gd/ExcelToCsv.gd")
const CsvToGd脚本: GDScript = preload("res://addons/excel_to_gd/CsvToGd.gd")

const Excel文件: String = "res://Table/Design/设计表.xlsx"


func _initialize() -> void:
	var csv目录: String = "res://Table/Csv"
	var 输出脚本: String = "res://Table/TableScripts/DataTables.gd"
	for 参数: String in OS.get_cmdline_user_args():
		if 参数.begins_with("--csv-dir="):
			csv目录 = 参数.trim_prefix("--csv-dir=")
		elif 参数.begins_with("--out="):
			输出脚本 = 参数.trim_prefix("--out=")

	var 导出器: ExcelToCsv = ExcelToCsv脚本.new()
	var 导出数量: int = 导出器.转换工作簿到文件夹(Excel文件, csv目录)
	print("[导表] Excel → CSV：%d 个文件（%s）" % [导出数量, csv目录])
	if 导出数量 < 0:
		print("[导表] 失败：Excel 转 CSV")
		quit(1)
		return

	var 转换器: CsvToGd = CsvToGd脚本.new()
	var 成功: bool = 转换器.转换文件夹为数据表(csv目录, 输出脚本)
	print("[导表] CSV → DataTables：%s（%s）" % ["成功" if 成功 else "失败", 输出脚本])
	quit(0 if 成功 else 1)
