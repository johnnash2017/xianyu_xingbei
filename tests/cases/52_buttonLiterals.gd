extends 自检用例
## 52 号：按钮文案禁止写死。
##
## 选项字典里的 `label` / `text` 必须从技能表「按钮」列取（按钮原文 / 按钮文本），
## 不允许直接写中文字面量 —— 否则改文案又要翻代码，和表里的字还会分叉。
##
## 扫描范围：角色脚本、独有技 helper、客户端 battle_mobile.gd。
## 基础规则菜单（治疗抵挡 / 购买 / 合成 / 提炼 / 星石组合 / 基础效果牌面）已经收进文本表，
## 所以这里可以零白名单地要求「选项里不出现中文字面量」。
## 限制：只查「值写在同一行」的写法；跨行写法扫不到，新增时请保持 label/text 与值同行。

const 目录列表: Array[String] = [
	"res://scripts/battle/roles/",
	"res://scripts/battle/skills/",
]
const 客户端文件: String = "res://scripts/ui/battle_mobile.gd"

var 违规: Array[String] = []
var 选项字段数: int = 0
var 按钮引用数: int = 0


func _init() -> void:
	名称 = "按钮文案禁止写死"


func 跑() -> void:
	for 路径: String in _收集():
		_扫文件(路径)
	检(违规.is_empty(),
		"选项按钮文案被写死，应从技能表「按钮」列取：\n%s" % "\n".join(违规))
	# 防止用例空跑：扫到的字段/引用数量应保持在一个量级上
	检(选项字段数 > 150, "应扫到 150 个以上 label/text 选项字段，实际 %d（扫描口径失效？）" % 选项字段数)
	检(按钮引用数 > 100, "应扫到 100 处以上 按钮原文/按钮文本 引用，实际 %d" % 按钮引用数)


func _收集() -> Array[String]:
	var 列表: Array[String] = []
	for 目录: String in 目录列表:
		for 文件: String in DirAccess.get_files_at(目录):
			if 文件.ends_with(".gd"):
				列表.append(目录 + 文件)
	列表.append(客户端文件)
	列表.sort()
	return 列表


func _扫文件(路径: String) -> void:
	var 全文: String = FileAccess.get_file_as_string(路径)
	if 全文.is_empty():
		return
	var 键正则: RegEx = RegEx.new()
	if 键正则.compile("\"(label|text)\"\\s*:") != OK:
		return
	var 行号: int = 0
	for 行: String in 全文.split("\n"):
		行号 += 1
		if 行.strip_edges().begins_with("#"):
			continue
		按钮引用数 += _计数(行, "按钮原文(") + _计数(行, "按钮文本(")
		for m: RegExMatch in 键正则.search_all(行):
			选项字段数 += 1
			var 值: String = _紧随的字面量(行, m.get_end())
			if 值.is_empty():
				continue
			if _含汉字(值):
				违规.append("%s:%d  %s" % [
					路径.trim_prefix("res://"), 行号, 行.strip_edges()])


## 从 pos 起跳过空白，若紧跟一个字符串字面量就返回它的内容，否则返回空串
func _紧随的字面量(文本: String, pos: int) -> String:
	var i: int = pos
	while i < 文本.length() and (文本[i] == " " or 文本[i] == "\t"):
		i += 1
	if i >= 文本.length() or 文本[i] != "\"":
		return ""
	i += 1
	var 起: int = i
	while i < 文本.length():
		if 文本[i] == "\\":
			i += 2
			continue
		if 文本[i] == "\"":
			return 文本.substr(起, i - 起)
		i += 1
	return ""


func _含汉字(文本: String) -> bool:
	for i: int in range(文本.length()):
		var c: int = 文本.unicode_at(i)
		if c >= 0x4e00 and c <= 0x9fff:
			return true
	return false


func _计数(文本: String, 片段: String) -> int:
	var n: int = 0
	var i: int = 文本.find(片段)
	while i >= 0:
		n += 1
		i = 文本.find(片段, i + 片段.length())
	return n
