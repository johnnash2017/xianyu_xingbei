## 卡牌数据 —— 对应 AGrail.Card
## 原实现从 battle 包的 cardDB 文本资源解析（制表符分隔）。
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

const DB_PATH := "res://assets/data/cardDB.txt"

var id: int = 0
var type: int = CardType.MAGIC
var element: int = CardElement.NONE
var property: int = 0
var card_name: String = ""
var asset_path: String = ""
var description: String = ""
var skill_num: int = 0
var skill_names: PackedStringArray = PackedStringArray()

static var _dict: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DB_PATH):
		push_warning("Card: 找不到 " + DB_PATH)
		return
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	var text := f.get_as_text()
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "":
			continue
		var cols := line.split("\t")
		if cols.size() < 8:
			continue
		var c := Card.new()
		c.id = int(cols[0])
		c.type = _index_of(TYPE_NAMES, cols[1].to_lower())
		c.element = _index_of(ELEMENT_NAMES, cols[2].to_lower())
		c.property = _index_of(PROPERTY_NAMES, cols[3])
		c.card_name = cols[4]
		c.asset_path = cols[5]
		c.description = cols[6]
		c.skill_num = int(cols[7])
		for i in range(8, mini(8 + c.skill_num, cols.size())):
			c.skill_names.append(cols[i])
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

func has_skill(skill_name: String) -> bool:
	return skill_names.has(skill_name)

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
