extends Node
## 资源索引（autoload 名：Art）
## 统一从 资源/ 目录按名取贴图与音效，带缓存；对照原客户端 data/Player.cpp 的 tapSource 表与 resource/ 目录结构。

const DIR_CARD: String = "res://资源/卡面/"
const DIR_ROLE: String = "res://资源/角色/"
## 选角大立绘（260x363，搬自参照工程 assets/textures/hero/middle）
const DIR_ROLE_BIG: String = "res://资源/角色大图/"
const DIR_STATUS: String = "res://资源/界面/status/"
const DIR_TAP: String = "res://资源/界面/tap/"
const DIR_BP: String = "res://资源/界面/bp/"
const DIR_UI: String = "res://资源/界面/"
const DIR_SFX: String = "res://资源/音效/"

## 角色「横置/形态」图标（逐行对照原客户端 data/Player.cpp 的 tapSource）
const ROLE_TAP: Dictionary = {
	5: "QianXing", 6: "LianMin", 9: "AnYing", 14: "ShenPan", 16: "QiDao",
	20: "BaiShi", 21: "JingPiLiJie", 23: "LiuXue", 24: "DiaoLing",
	25: "YingLingXingTai", 27: "XuSiBengFa", 28: "ReXueFeiTeng", 29: "HuanYing",
	30: "LieYan", 31: "ShiShen", 32: "ZhuFu", 33: "ShiShen", 34: "QiangWei",
	35: "AnYue", 36: "QianXing", 37: "AnYue",
}

## 基础效果卡名 → status 图标名（对照 资源/界面/status 下的文件名）
const STATUS_ICON: Dictionary = {
	"圣盾": "dun", "中毒": "du", "虚弱": "xu",
	"风之封印": "fengFeng", "水之封印": "shuiFeng", "火之封印": "huoFeng",
	"地之封印": "diFeng", "雷之封印": "leiFeng",
	"威力赐福": "wei", "迅捷赐福": "xun",
	"灵魂链接": "LianJie", "同生共死": "TongSheng", "永恒乐章": "YueZhang",
}

## 独有效果索引 → status 图标名（GConst.Exclusive 的顺序）
const EXCLUSIVE_ICON: Array[String] = ["token0", "TiaoXin", "LianJie", "TongSheng", "YueZhang"]

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
	return tex(card.texture_path())


func role_avatar(role_id: int) -> Texture2D:
	return tex("%s%d.png" % [DIR_ROLE, role_id])


## 选角用的大立绘（260x363）；参照工程没收录的角色回退到小立绘
func role_hero(role_id: int) -> Texture2D:
	var 大图: Texture2D = tex("%s%dM.jpg" % [DIR_ROLE_BIG, role_id])
	if 大图 == null:
		大图 = tex("%s%dM.png" % [DIR_ROLE_BIG, role_id])
	if 大图 == null:
		return role_avatar(role_id)
	return 大图


func role_tap(role_id: int) -> Texture2D:
	if not ROLE_TAP.has(role_id):
		return null
	return tex("%s%s.png" % [DIR_TAP, str(ROLE_TAP[role_id])])


func status_icon(card_name: String) -> Texture2D:
	if not STATUS_ICON.has(card_name):
		return null
	return tex("%s%s.png" % [DIR_STATUS, str(STATUS_ICON[card_name])])


func exclusive_icon(idx: int) -> Texture2D:
	if idx < 0 or idx >= EXCLUSIVE_ICON.size():
		return null
	return tex("%s%s.png" % [DIR_STATUS, EXCLUSIVE_ICON[idx]])


func token_icon(slot: int) -> Texture2D:
	if slot < 0 or slot >= TOKEN_ICON.size():
		return null
	return tex("%s%s.png" % [DIR_STATUS, TOKEN_ICON[slot]])


func ui(name: String) -> Texture2D:
	return tex("%s%s.png" % [DIR_UI, name])


func bp_icon(name: String) -> Texture2D:
	return tex("%s%s.png" % [DIR_BP, name])


# ============================================================
# 音效
# ============================================================
## 播放一次音效（文件名取自 资源/音效，如 "Hit" / "Hurt" / "Cure" / "Skill"）
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
