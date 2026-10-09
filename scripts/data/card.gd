class_name GCard
extends RefCounted
## 卡牌（对照客户端 data/Card.h）
## 由 Table/TableScripts/DataTables.gd 的「卡表」（设计表.xlsx 生成）逐行构造而来

var id: int = 0
var type: String = ""          # "attack" / "magic"
var element: String = ""       # earth / wind / fire / water / thunder / light / darkness
var property: String = ""      # 血 / 技 / 幻 / 咏 / 圣
var card_name: String = ""     # 卡名：地裂斩 / 圣盾 / 中毒 …
var source: String = ""        # 卡面资源名，如 shengDun（交给 AssetIndex 解析成 assets 下的图）
var description: String = ""   # 说明文本（# 已替换为换行）
var skill_num: int = 0
var skill_ids: Array[int] = []   # 「技能1/技能2」列引用的技能号（技能表「脚本号」列的值，代码按号判断）
var skill_names: PackedStringArray = PackedStringArray()   # 由引用解析出的技能名（印在卡面底部两格）
var is_virtual: bool = false   # 「虚拟牌」列：1 = 虚拟牌（无卡面的特殊牌，如五系束缚/挑衅/灵魂链接/同生共死/永恒乐章）


## 从「卡表」的一行构造（row 是该行除 id 外的各列，与 表元数据["卡表"]["列索引"] 对齐）
static func from_row(card_id: int, row: Array) -> GCard:
	var 列: Dictionary = 数据表格.表元数据["卡表"]["列索引"]
	var c: GCard = GCard.new()
	c.id = card_id
	c.type = str(row[int(列["类型"])])
	c.element = str(row[int(列["元素"])])
	c.property = str(row[int(列["派系"])])
	c.card_name = str(row[int(列["卡名"])])
	c.source = str(row[int(列["资源名"])])
	c.description = str(row[int(列["说明"])]).replace("#", "\n")
	c.skill_num = int(row[int(列["技能数"])])
	# 「技能1/技能2」列写的是技能表的 id（形如「技能#地之封印」）：
	# 先按 id 查到技能行，取出它的「脚本号」列作为技能号（代码判断技能就用这个号）
	for i: int in range(c.skill_num):
		var 键: String = "技能%d" % (i + 1)
		if not 列.has(键):
			break
		var 引用: String = str(row[int(列[键])]).strip_edges()
		if 引用 == "":
			continue
		var 号: int = GConst.技能号(引用)
		c.skill_ids.append(号)
		c.skill_names.append(GConst.skill_name(号))
	c.is_virtual = int(row[int(列["虚拟牌"])]) != 0
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


## 是否带有某个技能（按技能号判断；号来自卡表「技能1/技能2」的引用）
func has_skill_id(skill_id: int) -> bool:
	return skill_ids.has(skill_id)
