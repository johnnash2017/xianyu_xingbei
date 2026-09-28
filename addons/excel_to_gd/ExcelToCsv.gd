# 文件名: ExcelToCsv.gd
# 功能: 解析 .xlsx 工作簿（本质是 ZIP + XML），把名称以 .csv 结尾的工作表
#       原样导出为同名 CSV 文件，供 CsvToGd 进一步生成数据表脚本。
# 说明: 工作表的行布局需与旧 CSV 一致：第 1 行显示名、第 2 行列 key、
#       第 3 行类型定义、其后为数据行。单元格内容（shared string / 数字 /
#       枚举文本 / list 长文本等）原样输出。
# 导出规则（与 CsvToGd 校验口径对齐）：
#       - 每行统一补齐到表列宽（取前 3 行中最宽的列数），保证行尾空列不丢失；
#       - XML 中完全为空而被省略的行，按 Excel 行号补成空行，保留视觉分隔；
#       - 换行统一使用 CRLF，文件带 UTF-8 BOM，与旧 CSV 完全一致。
class_name ExcelToCsv
extends RefCounted

# 与 Table/Csv 下手工维护的 .import 一致的"跳过导入"配置：
# importer="skip" 表示该 CSV 不做任何导入（不生成 Translation 等资源），
# 否则新建的 CSV 会被 Godot 当作翻译资源导入。
const 跳过导入配置: String = "[remap]\n\nimporter=\"skip\"\n"

# ==================== 内部状态 ====================
var _zip读取器: ZIPReader = null
var _待清理路径: String = ""  # 文件被占用时用临时副本的路径，读取完成后需删除
var _共享字符串: PackedStringArray = PackedStringArray()  # xl/sharedStrings.xml 文本池
var _工作表: Array[Dictionary] = []  # 每项: { "名称": String, "路径": String }

# ==================== 公共接口 ====================
# 将 xlsx 中所有以 ".csv" 结尾的工作表导出为同名 CSV 文件
# 成功返回导出文件数量；文件打开/解析失败返回 -1
func 转换工作簿到文件夹(xlsx文件路径: String, csv输出文件夹: String) -> int:
	var 磁盘路径: String = xlsx文件路径
	if 磁盘路径.begins_with("res://"):
		磁盘路径 = ProjectSettings.globalize_path(磁盘路径)

	# 打开工作簿（被 Excel 等程序占用时，自动改用临时副本绕过文件锁）
	if not _打开工作簿(磁盘路径):
		push_error("ExcelToCsv: 无法打开 Excel 文件: %s" % xlsx文件路径)
		return -1

	# 解析共享字符串与工作表清单
	if not _解析共享字符串():
		_关闭工作簿()
		return -1
	if not _解析工作表清单():
		_关闭工作簿()
		return -1

	# 确保输出目录存在
	_确保目录存在(csv输出文件夹)

	# 逐个导出以 .csv 结尾的工作表
	var 导出数量: int = 0
	var 汇总列表: Array[String] = []
	for 表信息: Dictionary in _工作表:
		var 工作表名: String = str(表信息["名称"]).strip_edges()
		if not 工作表名.to_lower().ends_with(".csv"):
			continue

		var 工作表XML文本: String = _读取压缩文本(str(表信息["路径"]))
		if 工作表XML文本.is_empty():
			push_error("ExcelToCsv: 工作表内容为空: %s" % 工作表名)
			continue

		var 行数据: Array = _解析工作表行(工作表XML文本)
		var csv文本: String = _生成CSV文本(行数据)
		var 输出路径: String = csv输出文件夹.path_join(工作表名)
		if not _写CSV文件(输出路径, csv文本):
			continue
		_写跳过导入配置(输出路径 + ".import")
		导出数量 += 1
		汇总列表.append(工作表名.get_basename())
	_关闭工作簿()
	if 导出数量 > 0:
		print("[增量生成] 导出 %d 个 CSV 文件（%s）" % [导出数量, "；".join(汇总列表)])
	return 导出数量

# ==================== 工作簿打开/关闭 ====================
# 打开 xlsx（本质为 ZIP 包）。直接打开失败时（如文件正被 Excel 占用），
# 用 PowerShell + .NET FileShare.ReadWrite 把文件按二进制复制到用户目录临时文件，
# 再从临时副本读取，绕过 Windows 文件锁。
func _打开工作簿(磁盘路径: String) -> bool:
	# 首次直接尝试
	_zip读取器 = ZIPReader.new()
	if _zip读取器.open(磁盘路径) == OK:
		return true

	# 短暂等待后重试一次（Excel 可能正在保存）
	OS.delay_msec(50)
	_zip读取器 = ZIPReader.new()
	if _zip读取器.open(磁盘路径) == OK:
		return true

	# 仍失败：通过临时副本读取（.NET FileShare.ReadWrite 可绕过 Excel 的独占锁）
	var 临时系统路径: String = OS.get_user_data_dir().path_join(
		"_excel_%s_%d.xlsx" % [磁盘路径.get_file().get_basename(), Time.get_ticks_usec()]
	)
	var ps脚本: String = (
		"$src = '%s'; $dst = '%s'; " +
		"try { " +
		"  $in = [System.IO.File]::Open($src, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite); " +
		"  $out = [System.IO.File]::Open($dst, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None); " +
		"  $in.CopyTo($out); $out.Close(); $in.Close(); " +
		"  exit 0; " +
		"} catch { exit 1; }"
	) % [磁盘路径.replace("'", "''"), 临时系统路径.replace("'", "''")]
	var 退出码: int = OS.execute("powershell.exe", ["-NoProfile", "-Command", ps脚本], [], true)
	if 退出码 != 0:
		DirAccess.remove_absolute(临时系统路径)
		return false

	var 临时读取器: ZIPReader = ZIPReader.new()
	if 临时读取器.open(临时系统路径) != OK:
		DirAccess.remove_absolute(临时系统路径)
		return false
	_zip读取器 = 临时读取器
	_待清理路径 = 临时系统路径
	return true

# 关闭工作簿并清理临时副本
func _关闭工作簿() -> void:
	if _zip读取器 != null:
		_zip读取器.close()
		_zip读取器 = null
	if not _待清理路径.is_empty():
		DirAccess.remove_absolute(_待清理路径)
		_待清理路径 = ""

# ==================== 共享字符串 ====================
func _解析共享字符串() -> bool:
	var xml文本: String = _读取压缩文本("xl/sharedStrings.xml")
	if xml文本.is_empty():
		return true  # 无共享字符串（可能全部内联）时合法

	var 解析器: XMLParser = XMLParser.new()
	if 解析器.open_buffer(xml文本.to_utf8_buffer()) != OK:
		push_error("ExcelToCsv: 解析 sharedStrings.xml 失败")
		return false

	_共享字符串.clear()
	var 当前字符串: String = ""
	var 在文本内: bool = false
	while 解析器.read() == OK:
		match 解析器.get_node_type():
			XMLParser.NODE_ELEMENT:
				if 解析器.get_node_name().to_lower() == "t":
					在文本内 = true
			XMLParser.NODE_TEXT:
				if 在文本内:
					当前字符串 += 解析器.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				var 结束名: String = 解析器.get_node_name().to_lower()
				if 结束名 == "t":
					在文本内 = false
				elif 结束名 == "si":
					_共享字符串.append(当前字符串)
					当前字符串 = ""
	return true

# ==================== 工作表清单 ====================
# 读取 xl/workbook.xml 中的 <sheet> 与 xl/_rels/workbook.xml.rels 的关系映射
func _解析工作表清单() -> bool:
	# 1) 关系映射: rId -> 工作表文件路径（相对 xl/ 目录）
	var 关系映射: Dictionary = {}
	var 关系XML: String = _读取压缩文本("xl/_rels/workbook.xml.rels")
	if not 关系XML.is_empty():
		var 解析器: XMLParser = XMLParser.new()
		if 解析器.open_buffer(关系XML.to_utf8_buffer()) == OK:
			while 解析器.read() == OK:
				if 解析器.get_node_type() == XMLParser.NODE_ELEMENT:
					if 解析器.get_node_name().to_lower() == "relationship":
						var 类型: String = _获取属性(解析器, "type").to_lower()
						if 类型.contains("worksheet"):
							var 关系id: String = _获取属性(解析器, "id")
							var 目标: String = _获取属性(解析器, "target")
							关系映射[关系id] = _解析工作表路径(目标)

	# 2) 遍历 workbook.xml 的 sheet
	var 工作簿XML: String = _读取压缩文本("xl/workbook.xml")
	if 工作簿XML.is_empty():
		push_error("ExcelToCsv: 缺少 xl/workbook.xml")
		return false

	_工作表.clear()
	var 解析器: XMLParser = XMLParser.new()
	if 解析器.open_buffer(工作簿XML.to_utf8_buffer()) != OK:
		push_error("ExcelToCsv: 解析 workbook.xml 失败")
		return false

	while 解析器.read() == OK:
		if 解析器.get_node_type() == XMLParser.NODE_ELEMENT:
			if 解析器.get_node_name().to_lower() == "sheet":
				var 工作表名: String = _获取属性(解析器, "name")
				# r:id 属性名为 "r:id"，命名空间前缀可能是 r 或空
				var 关系id: String = ""
				for i: int in range(解析器.get_attribute_count()):
					if 解析器.get_attribute_name(i).to_lower().ends_with(":id") or 解析器.get_attribute_name(i).to_lower() == "id":
						关系id = 解析器.get_attribute_value(i)
				if 关系映射.has(关系id):
					_工作表.append({"名称": 工作表名, "路径": 关系映射[关系id]})
				else:
					push_warning("ExcelToCsv: 找不到工作表 %s 的文件路径" % 工作表名)
	return not _工作表.is_empty() or true

# 把 workbook.xml.rels 里的 target 解析为 zip 包内路径
func _解析工作表路径(目标: String) -> String:
	var 标准化: String = 目标.replace("\\", "/")
	if 标准化.begins_with("/"):
		return 标准化.substr(1)          # 包内绝对路径
	return "xl/" + 标准化                # 相对 xl/ 目录（标准写法）

# ==================== 单元格解析 ====================
# 解析单个工作表 XML，返回按 Excel 行号连续排列的行数组。
# 对齐规则（保证 CsvToGd 校验通过）：
#   1) 每行统一补齐到表列宽（前 3 行中最宽列数），避免行尾空列被截断；
#   2) XML 中完全为空而被省略的行，按行号补成空行，保留视觉分隔。
func _解析工作表行(工作表XML文本: String) -> Array:
	var 行号到行: Dictionary = {}   # key: Excel 行号(int) -> 该行单元格数组
	var 最大行号: int = 0            # 出现过的最大 Excel 行号
	var 表列宽: int = 0              # 全表统一列宽（由前 3 行中最宽列决定）
	var 解析器: XMLParser = XMLParser.new()
	if 解析器.open_buffer(工作表XML文本.to_utf8_buffer()) != OK:
		push_error("ExcelToCsv: 解析工作表失败")
		return []

	# 行内状态
	var 当前行号: int = 0         # 当前行的 Excel 行号（取自 row 的 r 属性）
	var 当前行: Dictionary = {}   # key: 列号 -> 值文本
	var 最大列: int = 0
	var 在行内: bool = false
	var 当前列号: int = 0
	var 单元格类型: String = ""
	var 在值内: bool = false
	var 值缓冲: String = ""
	var 内联模式: bool = false
	var 内联缓冲: String = ""

	while 解析器.read() == OK:
		match 解析器.get_node_type():
			XMLParser.NODE_ELEMENT:
				var 节点名: String = 解析器.get_node_name().to_lower()
				match 节点名:
					"row":
						当前行 = {}
						最大列 = 0
						在行内 = true
						# 读取 Excel 行号（r 属性）；异常缺失时按上一行 +1 兜底
						var 行号文本: String = _获取属性(解析器, "r")
						当前行号 = 行号文本.to_int() if 行号文本.is_valid_int() else 最大行号 + 1
					"c":
						单元格类型 = _获取属性(解析器, "t")
						当前列号 = _列名转索引(_解析列字母(_获取属性(解析器, "r")))
						内联模式 = false
						内联缓冲 = ""
					"v":
						在值内 = true
						值缓冲 = ""
					"is":
						内联模式 = true
						内联缓冲 = ""
			XMLParser.NODE_TEXT:
				if 在值内:
					值缓冲 += 解析器.get_node_data()
				elif 内联模式:
					内联缓冲 += 解析器.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				var 结束名: String = 解析器.get_node_name().to_lower()
				match 结束名:
					"v":
						在值内 = false
						var 解析值: String = _解析单元格值(值缓冲, 单元格类型, 内联缓冲)
						当前行[当前列号] = 解析值
						if 当前列号 > 最大列:
							最大列 = 当前列号
						单元格类型 = ""
					"is":
						# 内联字符串（t="inlineStr"）没有 <v> 节点，值在 </is> 处写回
						内联模式 = false
						当前行[当前列号] = _解析单元格值("", 单元格类型, 内联缓冲)
						if 当前列号 > 最大列:
							最大列 = 当前列号
						单元格类型 = ""
					"row":
						if 在行内:
							在行内 = false
							var 整行: Array = []
							for 列号: int in range(1, 最大列 + 1):
								整行.append(str(当前行.get(列号, "")))
							行号到行[当前行号] = 整行
							if 当前行号 > 最大行号:
								最大行号 = 当前行号
							# 前 3 行（显示名/列key/类型）中最宽的即全表列宽
							if 当前行号 <= 3 and 整行.size() > 表列宽:
								表列宽 = 整行.size()

	# 兜底：前 3 行都缺失时（异常表），按所有行中最大宽度处理
	if 表列宽 == 0:
		for 单行: Array in 行号到行.values():
			if 单行.size() > 表列宽:
				表列宽 = 单行.size()

	# 从第 1 行到最大行号连续生成：缺行补空行、每行统一补到表列宽
	var 行数据: Array = []
	for 行号: int in range(1, 最大行号 + 1):
		var 整行: Array = []
		if 行号到行.has(行号):
			整行 = 行号到行[行号]
		if 整行.size() < 表列宽:
			for 补空计数: int in range(整行.size(), 表列宽):
				整行.append("")
		elif 整行.size() > 表列宽:
			整行.resize(表列宽)  # 超出表宽的列不属于数据表，裁剪
		行数据.append(整行)
	return 行数据

# 把 "A"/"BC" 这类列字母转成从 1 开始的列号
func _列名转索引(列名: String) -> int:
	var 索引: int = 0
	for 字符: String in 列名.to_upper():
		索引 = 索引 * 26 + (字符.unicode_at(0) - 64)
	return 索引

# 从单元格引用（如 "A1"/"BC12"）中截取列字母部分
func _解析列字母(引用: String) -> String:
	var 字母: String = ""
	for 字符: String in 引用:
		if 字符.is_valid_int():
			break
		字母 += 字符
	return 字母

# 按单元格类型把 <v> 文本还原为显示值
#   s: 共享字符串索引；inlineStr: 内联文本；其余（数字/bool/str）原样输出
func _解析单元格值(值文本: String, 类型: String, 内联文本: String) -> String:
	if 类型 == "s":
		if 值文本.is_valid_int():
			var 索引: int = 值文本.to_int()
			if 索引 >= 0 and 索引 < _共享字符串.size():
				return _共享字符串[索引].strip_edges()
		return ""
	if 类型 == "inlineStr":
		return 内联文本.strip_edges()
	return 值文本

# ==================== CSV 输出 ====================
# 行数组 -> CSV 文本（最后带换行）
func _生成CSV文本(行数据: Array) -> String:
	var 输出行: PackedStringArray = PackedStringArray()
	for 行: Array in 行数据:
		var 单元格文本: PackedStringArray = PackedStringArray()
		for 值: Variant in 行:
			单元格文本.append(_转义CSV单元格(str(值)))
		输出行.append(",".join(单元格文本))
	if 输出行.is_empty():
		return ""
	return "\r\n".join(输出行) + "\r\n"

func _转义CSV单元格(值: String) -> String:
	if 值.contains(",") or 值.contains("\"") or 值.contains("\n") or 值.contains("\r"):
		return "\"" + 值.replace("\"", "\"\"") + "\""
	return 值

# 写文件（UTF-8 BOM，与手工维护的旧 CSV 保持一致）
func _写CSV文件(文件路径: String, 文本: String) -> bool:
	var 文件: FileAccess = FileAccess.open(文件路径, FileAccess.WRITE)
	if 文件 == null:
		push_error("ExcelToCsv: 无法写入 CSV 文件: %s" % 文件路径)
		return false
	文件.store_string("\uFEFF" + 文本)
	文件.close()
	return true

# 为 CSV 生成配套的 .import 文件（importer="skip"），让新产生的 CSV 也跳过导入，
# 不会被 Godot 识别为翻译资源（Translation）；与手工维护的旧文件配置一致。
func _写跳过导入配置(导入文件路径: String) -> void:
	var 导入文件: FileAccess = FileAccess.open(导入文件路径, FileAccess.WRITE)
	if 导入文件 == null:
		push_error("ExcelToCsv: 无法写入导入配置: %s" % 导入文件路径)
		return
	导入文件.store_string(跳过导入配置)
	导入文件.close()

# ==================== 工具方法 ====================
func _确保目录存在(文件夹: String) -> void:
	if DirAccess.open(文件夹) == null:
		# Godot 4.7 起 make_dir_recursive 改为实例方法，静态创建目录用 _absolute 版本
		DirAccess.make_dir_recursive_absolute(文件夹)

func _读取压缩文本(条目路径: String) -> String:
	# 条目可能不存在（如整表都用内联字符串时没有 xl/sharedStrings.xml），
	# 先判断再读取，避免 ZIPReader 打印 "File does not exist in zip archive"
	if not _zip读取器.file_exists(条目路径):
		return ""
	var 字节: PackedByteArray = _zip读取器.read_file(条目路径)
	if 字节.is_empty():
		return ""
	return 字节.get_string_from_utf8()

func _获取属性(解析器: XMLParser, 属性名: String) -> String:
	for i: int in range(解析器.get_attribute_count()):
		if 解析器.get_attribute_name(i).to_lower() == 属性名.to_lower():
			return 解析器.get_attribute_value(i)
	return ""
