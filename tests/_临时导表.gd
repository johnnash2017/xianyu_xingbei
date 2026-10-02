extends SceneTree
## 临时脚本：命令行跑一遍导表（Excel→CSV→DataTables），用完即删。

func _init() -> void:
	var 转换器: ExcelToCsv = ExcelToCsv.new()
	var 导出数量: int = 转换器.转换工作簿到文件夹("res://Table/Design/设计表.xlsx", "res://Table/Csv")
	print("Excel→CSV 导出工作表数: %d" % 导出数量)
	if 导出数量 < 0:
		quit(1)
		return
	var 转表: CsvToGd = CsvToGd.new()
	var 成功: bool = 转表.转换文件夹为数据表("res://Table/Csv", "res://Table/TableScripts/DataTables.gd")
	print("CSV→DataTables: %s" % str(成功))
	quit(0 if 成功 else 1)
