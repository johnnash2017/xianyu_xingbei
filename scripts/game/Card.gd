## 卡牌数据 —— 对应 AGrail.Card
## 数据来自 Table/TableScripts/DataTables.gd 的「卡表」（由 设计表.xlsx 生成）
class_name Card
extends RefCounted

enum CardType { MAGIC, ATTACK, UNIQUE }
enum CardElement { NONE, WIND, WATER, FIRE, EARTH, THUNDER, LIGHT, DARKNESS }

const PROPERTY_NAMES := ["无", "幻", "圣", "咏", "技", "血"]
const CARD_NAMES := ["圣盾", "虚弱", "中毒", "魔弹", "地裂斩", "风神斩", "火焰斩",
	"水涟斩", "雷光斩", "圣光", "暗灭", "五行束缚", "同生共死", "挑衅",
	"灵魂链接", "永恒乐章"]
const ELEMENT_NAMES := ["none", "wind", "water", "fire", "earth", "thunder", "light", "darkness"]
const TYPE_NAMES := ["magic", "attack", "unique"]

var id: int = 0
var type: int = CardType.MAGIC
var element: int = CardElement.NONE
var property: int = 0
var card_name: String = ""
var asset_path: String = ""
var description: String = ""
var skill_num: int = 0
var skill_ids: Array[int] = []                             # 「技能1/技能2」列引用的技能号（技能表#N 的 N）
var skill_names: PackedStringArray = PackedStringArray()   # 由引用解析出的技能名（仅作显示/调试用）

static var _dict: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	# 键是「卡表#编号」，值是除 id 以外的各列
	for key: String in 数据表格.卡表.keys():
		var row: Array = 数据表格.卡表[key]
		if row.size() < 7:
			continue
		var c: Card = Card.new()
		c.id = int(key.get_slice("#", 1))
		c.type = _index_of(TYPE_NAMES, str(row[0]).to_lower())
		c.element = _index_of(ELEMENT_NAMES, str(row[1]).to_lower())
		c.property = _index_of(PROPERTY_NAMES, str(row[2]))
		c.card_name = str(row[3])
		c.asset_path = str(row[4])
		c.description = str(row[5])
		c.skill_num = int(str(row[6]))
		# 「技能1/技能2」列写的是 技能表#N 引用：展开成技能号（代码判断技能就用这个号）
		var 技能列: Dictionary = 数据表格.表元数据["技能表"]["列索引"]
		var 名列: int = int(技能列["技能名"])
		for i: int in range(7, mini(7 + c.skill_num, row.size())):
			var 引用: String = str(row[i]).strip_edges()
			if 引用 == "":
				continue
			c.skill_ids.append(int(引用.get_slice("#", 1)))
			var 技能行: Array = 数据表格.技能表.get(引用, [])
			if not 技能行.is_empty():
				c.skill_names.append(str(技能行[名列]).strip_edges())
		_dict[c.id] = c

static func _index_of(arr: Array, v: String) -> int:
	var i := arr.find(v)
	return i if i >= 0 else 0

static func get_card(card_id: int) -> Card:
	_ensure_loaded()
	if _dict.has(card_id):
		return _dict[card_id]
	push_warning("Can not find card id %d" % card_id)
	return null

static func all() -> Dictionary:
	_ensure_loaded()
	return _dict

## 这张牌是否带指定技能号（技能表的编号，见 卡表「技能1/技能2」的引用）
func has_skill_id(skill_id: int) -> bool:
	return skill_ids.has(skill_id)


## 卡名枚举值（与 GCard.card_name_enum 一致）
func card_name_enum() -> int:
	return GConst.card_name_from_string(card_name)

func type_name() -> String:
	return TYPE_NAMES[type] if type < TYPE_NAMES.size() else "magic"

## 对应 C# 里 AssetBundleManager.LoadAsset<Sprite>("card", card.AssetPath)
## cardDB 里的 AssetPath 有 "shengDun"、"card/moDan" 两种写法，统一交给 AssetIndex 解析
func sprite_path() -> String:
	return AssetIndex.image(asset_path)

func element_name() -> String:
	return ELEMENT_NAMES[element] if element < ELEMENT_NAMES.size() else "none"

func property_name() -> String:
	return PROPERTY_NAMES[property] if property < PROPERTY_NAMES.size() else "无"
