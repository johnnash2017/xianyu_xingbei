extends 自检用例
## 用例 81：多步询问「段条件读活状态」审计
##
## 背景：水影 502 的 bug —— 第二段的「跳过」用 `_有效水系牌(答案[0])` 判断第一段有没有弃出水系牌，
## 而那个函数要求牌**还在手里**；第一段的「答完」已经当场把牌弃掉了 → 永远判空 → 潜行下后半段永远不问。
##
## 这条用例把同类的「危险写法」变成可复查的清单：
##   - `跳过` 闭包里直接读**手牌 / 盖牌成员**（`hand_cards` / `has_hand_card` / `有手牌` / `cover_cards`）；
##   - `牌白` 闭包里读**自己的手牌**（`player.hand_cards`）——只有「答之前求值」才安全。
## 允许清单里的每一条都要写明为什么安全；新增条目必须人工复核，否则用例红。

const 角色目录: String = "res://scripts/battle/roles/"

## 允许清单：文件 → 该行（去掉首尾空白后）必须逐字匹配
const 允许_跳过: Dictionary = {
	"role_jianzhimoni.gd":
		'"跳过": func(_答案: Array) -> bool: return _异象否决 or dst.hand_cards.is_empty(),',
}

const 允许_牌白: Dictionary = {
	"role_shishenzhe.gd":
		'"牌白": func(_答案: Array) -> Array: return player.hand_cards.duplicate(),',
}

var 跳过命中: Array = []
var 牌白命中: Array = []


func _init() -> void:
	名称 = "分段状态校验审计"


func 跑() -> void:
	var 文件表: Array = []
	for 名: String in DirAccess.get_files_at(角色目录):
		if 名.ends_with(".gd"):
			文件表.append(名)
	文件表.sort()
	检(文件表.size() > 40, "角色脚本数量异常：%d" % 文件表.size())

	for 文件: String in 文件表:
		var 文本: String = FileAccess.get_file_as_string(角色目录 + 文件)
		var 行表: Array = 文本.split("\n")
		for i: int in range(行表.size()):
			var 行: String = (行表[i] as String).strip_edges()
			if 行.begins_with('"跳过"') and _读手牌状态(行):
				跳过命中.append("%s:%d  %s" % [文件, i + 1, 行])
			if 行.begins_with('"牌白"') and 行.contains("player.hand_cards"):
				牌白命中.append("%s:%d  %s" % [文件, i + 1, 行])

	# 跳过：只允许清单里那一处（目标是**别人**的手牌，不是自己已弃的牌）
	for 条: String in 跳过命中:
		var 段: PackedStringArray = 条.split(":")
		var 文件2: String = 段[0]
		var 行文: String = 条.substr(条.find("  ") + 2)
		检(允许_跳过.get(文件2, "") == 行文,
			"新增了「跳过」里直接读手牌/盖牌的段，请人工确认前一段没有先弃掉这些牌：\n%s" % 条)
	# 牌白：只允许「答之前求值」的那一处
	for 条2: String in 牌白命中:
		var 段2: PackedStringArray = 条2.split(":")
		var 文件3: String = 段2[0]
		var 行文2: String = 条2.substr(条2.find("  ") + 2)
		检(允许_牌白.get(文件3, "") == 行文2,
			"新增了「牌白」里读自己手牌的段，请人工确认它在答题之前求值：\n%s" % 条2)

	print("[分段审计] 跳过读手牌 %d 处（允许 %d），牌白读自己手牌 %d 处（允许 %d）" % [
		跳过命中.size(), 允许_跳过.size(), 牌白命中.size(), 允许_牌白.size()])


func _读手牌状态(行: String) -> bool:
	for 词: String in ["hand_cards", "has_hand_card", "有手牌", "cover_cards", "有盖牌"]:
		if 行.contains(词):
			return true
	return false
