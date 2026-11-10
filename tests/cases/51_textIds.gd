extends 自检用例
## 文案 id 校验（P5）：扫角色 / 独有技脚本里的文案引用，核对表和序号真的存在。
## 覆盖两类：
##   1) GConst.提示原文(技能号, 序号)  —— 技能号支持数字、本文件 const、GConst.const；
##   2) GConst.文本("id")             —— 文本表必须存在该 id。
## 动态表达式（如 提示原文(_展示技能号(), 1)）无法静态解析，跳过不校验。

var 失败引用: Array[String] = []
var 提示引用数: int = 0
var 按钮引用数: int = 0
var 文本引用数: int = 0

func _init() -> void:
	名称 = "提示文案 id 校验"


func 跑() -> void:
	var 全局常量: Dictionary = _解析常量表(FileAccess.get_file_as_string("res://scripts/core/const.gd"))
	for 路径: String in _收集脚本():
		var 全文: String = FileAccess.get_file_as_string(路径)
		if 全文.is_empty():
			continue
		var 局部常量: Dictionary = _解析常量表(全文)
		_校验提示原文(全文, 局部常量, 全局常量)
		_校验按钮原文(全文, 局部常量, 全局常量)
		_校验文本(全文)
	检(失败引用.is_empty(),
		"文案引用不存在：\n%s" % "\n".join(失败引用))
	检(提示引用数 > 0, "应至少校验到一处 提示原文 引用")
	# 按钮文案已全部收进「按钮」列，角色脚本里可以一处 文本(id) 都没有：
	# 这里只校验「如果有引用必须都存在」，不再要求至少有一条。文本表现只留客户端通用句。


## 校验 提示原文(...) 的技能表行与序号
func _校验提示原文(全文: String, 局部常量: Dictionary, 全局常量: Dictionary) -> void:
	var re: RegEx = RegEx.new()
	# 第一个参数匹配「数字 / 本文件常量（含中文名）/ GConst.常量」；函数调用等动态写法跳过
	var 结果: int = re.compile("提示原文\\s*\\(\\s*([^,()\\s]+)\\s*,\\s*([0-9]+)")
	if 结果 != OK:
		return
	for m: RegExMatch in re.search_all(全文):
		var 技能表达式: String = m.get_string(1)
		var 序号: int = int(m.get_string(2))
		var 技能号: int = -1
		if 技能表达式.is_valid_int():
			技能号 = int(技能表达式)
		elif 技能表达式.begins_with("GConst."):
			技能号 = int(全局常量.get(技能表达式.trim_prefix("GConst."), -1))
		else:
			技能号 = int(局部常量.get(技能表达式, -1))
		提示引用数 += 1
		if 技能号 < 0:
			continue  # 动态 / 外部常量，交给运行时用例覆盖
		var 列表: Array[String] = GConst.技能提示列表(技能号)
		if 序号 < 0 or 序号 >= 列表.size():
			失败引用.append("提示原文(%d, %d)：技能 %d 只有 %d 条提示［%s］" % [
				技能号, 序号, 技能号, 列表.size(), 技能表达式])
		# 空条目不报错：「提示」第 0 条留空是允许的（客户端会回退到技能说明）


## 校验 按钮原文(...) 的技能表行与序号（表里那条不能是空串，否则按钮会变成空白）
func _校验按钮原文(全文: String, 局部常量: Dictionary, 全局常量: Dictionary) -> void:
	var re: RegEx = RegEx.new()
	var 结果: int = re.compile("按钮原文\\s*\\(\\s*([^,()\\s]+)\\s*,\\s*([0-9]+)")
	if 结果 != OK:
		return
	for m: RegExMatch in re.search_all(全文):
		var 技能表达式: String = m.get_string(1)
		var 序号: int = int(m.get_string(2))
		var 技能号: int = -1
		if 技能表达式.is_valid_int():
			技能号 = int(技能表达式)
		elif 技能表达式.begins_with("GConst."):
			技能号 = int(全局常量.get(技能表达式.trim_prefix("GConst."), -1))
		else:
			技能号 = int(局部常量.get(技能表达式, -1))
		按钮引用数 += 1
		if 技能号 < 0:
			continue  # 动态 / 外部常量，交给运行时用例覆盖
		var 列表: Array[String] = GConst.技能按钮列表(技能号)
		if 序号 < 0 or 序号 >= 列表.size():
			失败引用.append("按钮原文(%d, %d)：技能 %d 只有 %d 条按钮文案［%s］" % [
				技能号, 序号, 技能号, 列表.size(), 技能表达式])
		elif 列表[序号].is_empty():
			失败引用.append("按钮原文(%d, %d)：技能 %d 的按钮文案是空串" % [
				技能号, 序号, 技能号])


## 校验 文本("id") 的文本表条目
func _校验文本(全文: String) -> void:
	var re: RegEx = RegEx.new()
	var 结果: int = re.compile("文本\\s*\\(\\s*\"([^\"]+)\"")
	if 结果 != OK:
		return
	for m: RegExMatch in re.search_all(全文):
		var id: String = m.get_string(1)
		# 拼接出来的 id（如 文本("日志_末日预言_" + 动作)）不按字面前缀查：后缀各有一条真 id
		var 尾: String = 全文.substr(m.get_end())
		if 尾.strip_edges(true, false).begins_with("+") :
			continue
		文本引用数 += 1
		if not 数据表格.文本表.has(id):
			失败引用.append("文本(\"%s\")：文本表里没有这个 id" % id)


## 收集角色 / 独有技脚本路径
func _收集脚本() -> Array[String]:
	var 列表: Array[String] = []
	for 目录: String in ["res://scripts/battle/roles/", "res://scripts/battle/skills/"]:
		for 文件: String in DirAccess.get_files_at(目录):
			if 文件.ends_with(".gd"):
				列表.append(目录 + 文件)
	列表.sort()
	return 列表


## 解析 `const 名字: int = N`（角色脚本和 const.gd 共用）
func _解析常量表(全文: String) -> Dictionary:
	var 表: Dictionary = {}
	var re: RegEx = RegEx.new()
	if re.compile("const\\s+([^:\\s]+)\\s*:\\s*int\\s*=\\s*([0-9]+)") != OK:
		return 表
	for m: RegExMatch in re.search_all(全文):
		表[m.get_string(1)] = int(m.get_string(2))
	return 表
