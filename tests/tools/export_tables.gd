@tool
extends SceneTree
## 开发工具：headless 重新导出数据表（等价于编辑器里的 Ctrl+Shift+T）。
## 用法（工程根目录）：
##   godot --headless --path . --script res://tests/tools/export_tables.gd
## 流程：设计表.xlsx → Table/Csv → Table/TableScripts/DataTables.gd。

const ExcelToCsv脚本: GDScript = preload("res://addons/excel_to_gd/ExcelToCsv.gd")
const CsvToGd脚本: GDScript = preload("res://addons/excel_to_gd/CsvToGd.gd")

const Excel路径: String = "res://Table/Design/设计表.xlsx"
const CSV目录: String = "res://Table/Csv"
const 输出路径: String = "res://Table/TableScripts/DataTables.gd"


func _init() -> void:
	var 开始: int = Time.get_ticks_msec()
	var excel: RefCounted = ExcelToCsv脚本.new()
	var 导出数: int = int(excel.call("转换工作簿到文件夹", Excel路径, CSV目录))
	print("[导表] Excel→CSV：%d 张工作表" % 导出数)
	if 导出数 < 0:
		push_error("[导表] Excel→CSV 失败")
		quit(1)
		return
	var csv: RefCounted = CsvToGd脚本.new()
	var 成功: bool = bool(csv.call("转换文件夹为数据表", CSV目录, 输出路径))
	print("[导表] CSV→DataTables：%s（耗时 %d ms）" % ["成功" if 成功 else "失败",
		Time.get_ticks_msec() - 开始])
	quit(0 if 成功 else 1)
