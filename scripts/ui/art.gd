extends Node
## 资源索引（autoload 名：Art）
## 统一从 assets/media/ 目录按名取贴图与音效，带缓存；对照原客户端 data/Player.cpp 的 tapSource 表与 resource/ 目录结构。

## 选角大立绘（260x363）
const DIR_ROLE_BIG: String = "res://assets/textures/hero/middle/"
## 战斗小图标目录（派系图 + 状态图标，搬自参照工程 assets/textures/battle）
const DIR_BATTLE: String = "res://assets/textures/battle/"
const DIR_TAP: String = "res://assets/textures/hero/tap/"
const DIR_SFX: String = "res://assets/media/sfx/"

## 基础效果卡名 → 状态图标名（assets/textures/battle 下的文件名）
const STATUS_ICON: Dictionary = {
	"圣盾": "dun", "中毒": "du", "虚弱": "xu",
	"风之封印": "fengFeng", "水之封印": "shuiFeng", "火之封印": "huoFeng",
	"地之封印": "diFeng", "雷之封印": "leiFeng",
	"威力赐福": "wei", "迅捷赐福": "xun",
	"灵魂链接": "LianJie", "同生共死": "TongSheng", "永恒乐章": "YueZhang",
}

## 派系名（角色表「派系」列：技 / 血 / 幻 / 咏 / 圣）→ 派系图标文件名（assets/textures/battle 下）
const PROPERTY_ICON: Dictionary = {
	"技": "skill", "血": "blood", "幻": "illusion", "咏": "chant", "圣": "holy",
}

## 独有效果索引 → status 图标名（GConst.Exclusive 的顺序，对照原客户端 widget/PlayerItem.cpp 的 StatusItem）
const EXCLUSIVE_ICON: Array[String] = ["ShuFu", "TiaoXin", "LianJie", "TongSheng", "YueZhang"]

## 指示物槽位 → status 图标名
const TOKEN_ICON: Array[String] = ["token0", "token1", "token2"]

var _cache: Dictionary = {}
var _sfx: AudioStreamPlayer = null


func _ready() -> void:
	_sfx = AudioStreamPlayer.new()
	_sfx.name = "SfxPlayer"
	add_child(_sfx)


# ============================================================
# 贴图
# ============================================================
## 通用贴图加载（带缓存；路径不存在返回 null）
func tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			t = res
	_cache[path] = t
	return t


func card_face(card: GCard) -> Texture2D:
	if card == null:
		return null
	return tex(card.sprite_path())


## 选角用的大立绘（260x363）
func role_hero(role_id: int) -> Texture2D:
	var 大图: Texture2D = tex("%s%dM.jpg" % [DIR_ROLE_BIG, role_id])
	if 大图 == null:
		大图 = tex("%s%dM.png" % [DIR_ROLE_BIG, role_id])
	return 大图


func role_tap(role_id: int) -> Texture2D:
	# 形态图资源名配在「角色表」的「形态图」列（原客户端 data/Player.cpp 的 tapSource）
	var 形态名: String = Data.role_tap(role_id)
	if 形态名 == "":
		return null
	return tex("%s%s.png" % [DIR_TAP, 形态名])


## 角色派系图标（技 / 血 / 幻 / 咏 / 圣）；没派系就返回 null
func role_property_icon(property_name: String) -> Texture2D:
	var 图标名: String = str(PROPERTY_ICON.get(property_name, ""))
	if 图标名 == "":
		return null
	return tex("%s%s.png" % [DIR_BATTLE, 图标名])


## 状态类小图标（基础效果 / 独有效果 / 指示物）：按名交给 AssetIndex（实际在 assets/textures/battle/）
func status_icon(card_name: String) -> Texture2D:
	if not STATUS_ICON.has(card_name):
		return null
	return tex(AssetIndex.image(str(STATUS_ICON[card_name])))


func exclusive_icon(idx: int) -> Texture2D:
	if idx < 0 or idx >= EXCLUSIVE_ICON.size():
		return null
	return tex(AssetIndex.image(EXCLUSIVE_ICON[idx]))


func token_icon(slot: int) -> Texture2D:
	if slot < 0 or slot >= TOKEN_ICON.size():
		return null
	return tex(AssetIndex.image(TOKEN_ICON[slot]))


# ============================================================
# 音效
# ============================================================
## 播放一次音效（文件名取自 assets/media/sfx，如 "Hit" / "Hurt" / "Cure" / "Skill"）
func play_sfx(file_name: String) -> void:
	if _sfx == null or file_name == "":
		return
	var path: String = "%s%s.wav" % [DIR_SFX, file_name]
	if _cache.has(path):
		var cached: Variant = _cache[path]
		if cached == null:
			return
		_sfx.stream = cached
		_sfx.play()
		return
	if not ResourceLoader.exists(path):
		_cache[path] = null
		return
	var s: Resource = load(path)
	if s is AudioStream:
		_cache[path] = s
		_sfx.stream = s
		_sfx.play()
	else:
		_cache[path] = null
