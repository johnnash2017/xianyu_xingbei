class_name GCard
extends RefCounted
## 卡牌（对照客户端 data/Card.h）
## 由 Table/TableScripts/DataTables.gd 的「卡面表」（设计表.xlsx 生成）逐行构造而来

var id: int = 0
var type: String = ""          # "attack" / "magic"
var element: String = ""       # earth / wind / fire / water / thunder / light / darkness
var property: String = ""      # 血 / 技 / 幻 / 咏 / 圣
var card_name: String = ""     # 卡名：地裂斩 / 圣盾 / 中毒 …
var source: String = ""        # 卡面资源名，如 shengDun（交给 AssetIndex 解析成 assets 下的图）
var description: String = ""   # 说明文本（# 已替换为换行）
var skill_num: int = 0
var skill_ids: Array[int] = []   # 「技能1/技能2」列引用的技能号（技能表#N 的 N，代码按号判断）
var skill_names: PackedStringArray = PackedStringArray()   # 由引用解析出的技能名（印在卡面底部两格）


static func from_row(cells: PackedStringArray) -> GCard:
	var c: GCard = GCard.new()
	c.id = int(cells[0])
	c.type = cells[1]
	c.element = cells[2]
	c.property = cells[3]
	c.card_name = cells[4]
	c.source = cells[5]
	c.description = cells[6].replace("#", "\n")
	c.skill_num = int(cells[7]) if cells.size() > 7 else 0
	for i: int in range(c.skill_num):
		var idx: int = 8 + i
		if idx < cells.size() and cells[idx].strip_edges() != "":
			var 技能号: int = int(cells[idx].strip_edges().get_slice("#", 1))
			c.skill_ids.append(技能号)
			c.skill_names.append(GConst.skill_name(技能号))
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


## 卡面贴图资源路径：按资源名交给 AssetIndex 解析（资源名如 shengDun，对应 assets/textures/card/*.png）
## 对应 C# 的 AssetBundleManager.LoadAsset<Sprite>("card", card.AssetPath)
func sprite_path() -> String:
	return AssetIndex.image(source)


## 是否带有某个技能（按技能号判断；号来自卡面表/卡表「技能1/技能2」的引用）
func has_skill_id(skill_id: int) -> bool:
	return skill_ids.has(skill_id)
