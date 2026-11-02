class_name GCard
extends RefCounted
## 卡牌（对照客户端 data/Card.h）
## 由 Table/TableScripts/DataTables.gd 的「卡表」（设计表.xlsx 生成）逐行构造而来

var id: int = 0
var type: String = ""          # "attack" / "magic"
## 当前系别：earth / wind / fire / water / thunder / light / darkness / none。
## 配置了多个可选系别时（如「fire or water」），这里是**当前选中的那一个**，
## 默认取配置里第一个；所有通用系别逻辑都按它判断。
var element: String = ""
## 卡表「元素」列的原始配置（单系别如 "fire"；或关系如 "fire or water"）
var 元素配置: String = ""
## 可选系别（CardElement 枚举，按配置顺序）。size > 1 时卡牌在手牌里可以切换当前系别。
var 可选元素: Array[int] = []
var fate_pattern: String = ""  # 命格：血 / 技 / 幻 / 咏 / 圣
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
	c.元素配置 = str(row[int(列["元素"])]).strip_edges()
	c.可选元素 = _解析元素配置(c.元素配置)
	# 有多个可选系别时，默认取配置里的第一个（如 fire or water → fire）
	c.element = GConst.element_to_string(c.可选元素[0]) if not c.可选元素.is_empty() else c.元素配置
	c.fate_pattern = str(row[int(列["命格"])])
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


## 解析卡表「元素」列：支持单系别 "fire"，也支持或关系 "fire or water"。
## 顺序就是默认顺序（第一个作为当前系别）；"none"/空返回空数组。
static func _解析元素配置(配置: String) -> Array[int]:
	var out: Array[int] = []
	for 段: String in 配置.split(" or "):
		var e: int = GConst.element_from_string(段.strip_edges())
		if e > 0 and not out.has(e):
			out.append(e)
	return out


## 这张牌能不能在手牌里切换系别（配置了 2 个以上可选系别）
func 可切换元素() -> bool:
	return 可选元素.size() > 1


## 切换当前系别（只能切到配置里列出的系别）
func 设置当前元素(e: int) -> bool:
	if not 可选元素.has(e):
		return false
	element = GConst.element_to_string(e)
	return true


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
func fate_pattern_enum() -> int:
	return GConst.fate_pattern_from_string(fate_pattern)


## 卡名枚举值
func card_name_enum() -> int:
	return GConst.card_name_from_string(card_name)


## 普通应战：同系攻击牌，或暗系攻击牌可应战任意系。
## 只判卡面规则；「这张牌在不在手牌」由调用方检查。
static func 可普通应战(card: GCard, atk: GCard) -> bool:
	if card == null or atk == null or not card.is_attack():
		return false
	if atk.element_enum() == GConst.CardElement.Darkness:
		return false
	return card.element_enum() == atk.element_enum() or card.element_enum() == GConst.CardElement.Darkness


## 阴阳转换应战：同命格攻击牌，不能是光系；暗系攻击本身不可应战。
static func 可阴阳应战(card: GCard, atk: GCard) -> bool:
	if card == null or atk == null or not card.is_attack():
		return false
	if atk.element_enum() == GConst.CardElement.Darkness:
		return false
	if card.element_enum() == GConst.CardElement.Light:
		return false
	return card.fate_pattern_enum() == atk.fate_pattern_enum()


## 卡面贴图资源路径：按资源名交给 AssetIndex 解析（资源名如 shengDun，对应 assets/textures/card/*.png）
## 对应 C# 的 AssetBundleManager.LoadAsset<Sprite>("card", card.AssetPath)
func sprite_path() -> String:
	return AssetIndex.image(source)


## 是否带有某个技能（按技能号判断；号来自卡表「技能1/技能2」的引用）
func has_skill_id(skill_id: int) -> bool:
	return skill_ids.has(skill_id)
