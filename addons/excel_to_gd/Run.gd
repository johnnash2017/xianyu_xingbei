# 文件名: Run.gd
# 功能: 编辑器插件入口。菜单项"检查并转换表格"一键执行：
#       1) Excel 转 CSV：读取 Table/Design/设计表.xlsx 中名称以 ".csv" 结尾的
#          工作表，导出为同名 CSV 文件到 Table/Csv 文件夹（直接覆盖旧文件）；
#       2) CSV 转数据表：把 Table/Csv 文件夹下所有 CSV 转换为
#          Table/TableScripts/DataTables.gd。
# 说明: 导出规则按需求约定 —— 只导出名称以 ".csv" 结尾的工作表，其余忽略。
@tool
extends EditorPlugin

var Name: String = "检查并转换表格   Ctrl+Shift+T"

const Excel文件路径: String = "res://Table/Design/设计表.xlsx"
const CSV输出目录: String = "res://Table/Csv"
const 脚本输出路径: String = "res://Table/TableScripts/DataTables.gd"

func _enter_tree() -> void:
	add_tool_menu_item(Name, _检查并转换表格)

func _exit_tree() -> void:
	remove_tool_menu_item(Name)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.ctrl_pressed and event.shift_pressed and event.keycode == KEY_T:
			_检查并转换表格()
			get_viewport().set_input_as_handled()

func _检查并转换表格() -> void:
	print_rich("[b]===== Excel → CSV → 数据表 转换开始 =====[/b]")
	if not FileAccess.file_exists(Excel文件路径):
		print_rich("[color=red]找不到 Excel 文件: %s[/color]" % Excel文件路径)
		return

	# 第一步：Excel → CSV（只导出以 .csv 结尾的工作表，覆盖写入 Table/Csv）
	var 转换开始时刻: int = Time.get_ticks_msec()
	var Excel转换器: ExcelToCsv = ExcelToCsv.new()
	var 导出数量: int = Excel转换器.转换工作簿到文件夹(Excel文件路径, CSV输出目录)
	if 导出数量 < 0:
		print_rich("[color=red]Excel 转 CSV 失败，终止生成[/color]")
		return
	if 导出数量 == 0:
		print_rich("[color=yellow]未找到名称以 .csv 结尾的工作表，本次没有生成新 CSV[/color]")
	print("[性能分析] Excel 转 CSV 耗时: %.2f 秒" % ((Time.get_ticks_msec() - 转换开始时刻) / 1000.0))

	# 第二步：CSV → GDScript 数据表
	# 覆写前先关闭脚本编辑器中打开的 DataTables.gd，避免覆写触发编辑器重载时报
	# "Index p_gutter = -1" 等 TextEdit 内部错误（该文件为自动生成，无未保存手改内容）
	var 数据表已打开: bool = _数据表是否已打开()
	if 数据表已打开:
		EditorInterface.get_script_editor().close_file(脚本输出路径)
	var 转换器: CsvToGd = CsvToGd.new()
	var 成功: bool = 转换器.转换文件夹为数据表(CSV输出目录, 脚本输出路径)
	if not 成功:
		print_rich("[color=red]CSV 转数据表失败，终止测试[/color]")
		return
	# 导表成功后再把 DataTables.gd 重新打开，方便继续查看
	if 数据表已打开:
		_重新打开数据表脚本()
	print_rich("[color=green]生成成功 → %s[/color]" % 脚本输出路径)

# 判断 DataTables.gd 当前是否打开在脚本编辑器中
func _数据表是否已打开() -> bool:
	var 打开脚本列表: Array = EditorInterface.get_script_editor().get_open_scripts()
	for 脚本: Script in 打开脚本列表:
		if 脚本.resource_path == 脚本输出路径:
			return true
	return false

# 用磁盘上的最新内容重新打开 DataTables.gd（忽略资源缓存，避免显示旧内容）
func _重新打开数据表脚本() -> void:
	var 脚本: Script = ResourceLoader.load(脚本输出路径, "", ResourceLoader.CACHE_MODE_IGNORE) as Script
	if 脚本:
		EditorInterface.edit_script(脚本)
