class_name GCard
extends RefCounted
## 卡牌（对照客户端 data/Card.h）
## 由 数据/cardDB.txt 的一行构造而来

var id: int = 0
var type: String = ""          # "attack" / "magic"
var element: String = ""       # earth / wind / fire / water / thunder / light / darkness
var property: String = ""      # 血 / 技 / 幻 / 咏 / 圣
var card_name: String = ""     # 卡名：地裂斩 / 圣盾 / 中毒 …
var source: String = ""        # 原始卡面路径，如 card/shengDunDi.png
var description: String = ""   # 说明文本（# 已替换为换行）
var has_speciality: int = 0
var speciality_list: Array[String] = []


static func from_row(cells: PackedStringArray) -> GCard:
	var c: GCard = GCard.new()
	c.id = int(cells[0])
	c.type = cells[1]
	c.element = cells[2]
	c.property = cells[3]
	c.card_name = cells[4]
	c.source = cells[5]
	c.description = cells[6].replace("#", "\n")
	c.has_speciality = int(cells[7]) if cells.size() > 7 else 0
	for i: int in range(c.has_speciality):
		var idx: int = 8 + i
		if idx < cells.size() and cells[idx] != "":
			c.speciality_list.append(cells[idx])
	return c


## 是否攻击牌
func is_attack() -> bool:
	return type == "attack"


## 是否法术牌
func is_magic() -> bool:
	return type == "magic"


## 元素枚举值
func element_enum() -> int:
	return GConst.element_from_string(element)


## 命格枚举值
func property_enum() -> int:
	return GConst.property_from_string(property)


## 卡名枚举值
func card_name_enum() -> int:
	return GConst.card_name_from_string(card_name)


## 卡面贴图资源路径（原始路径为 camelCase，实际文件为全小写）
func texture_path() -> String:
	if source == "":
		return ""
	var file_name: String = source.get_file().to_lower()
	return "res://资源/卡面/%s" % file_name


## 是否带有某个特技标签
func has_speciality_name(tag: String) -> bool:
	return speciality_list.has(tag)
