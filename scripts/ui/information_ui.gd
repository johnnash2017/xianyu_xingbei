## 英雄详情窗（技能说明）—— 从参考工程 scenes/prefabs/ui/InfomationUI.tscn + scripts/InformationUI.gd 搬过来。
## 参考工程里由 UIManager 推窗口、参数传一个 RoleBase；本工程改成 打开(角色号) 直接给角色号，
## 立绘 / 角色名 / 派系图标 / 技能说明都从本工程的数据表里取。
## 触发时机对照参考工程 PlayerStatusMobile.onClick：头像「点不动」时（不是该选目标的时机）就弹这个窗。
class_name 英雄详情窗口
extends Control

## 节点名沿用参考工程（Root/Hero/NameBG 那一套，去掉了转换后没内容的翻转 NameBG 背景与星级）
@export var Hero: TextureRect
@export var RoleProperty: TextureRect
@export var HeroName: Label
@export var SkillText: RichTextLabel
@export var BtnClose: Button

## 立绘目录：<角色号>L.png（与参考工程 LoadAsset<Sprite>("hero_l", RoleID + "L") 一致）
const 立绘目录: String = "res://assets/textures/hero/large/"


func _ready() -> void:
	BtnClose.pressed.connect(_on_close)
	visible = false


## 技能正文行首的「【类型】」按类型上色（连同方括号一起）；只认这四种，其余原样
const 技能类型颜色: Dictionary = {
	"被动": "4a9eff",   # 蓝
	"响应": "8a4fdd",   # 深紫
	"法术": "ff5ad2",   # 洋红
	"启动": "ffab40",   # 橙
}


## 给一段拼好的技能说明上色（一级标题、说明续行原样；正文行首的【类型】套 BBCode 颜色）
## 详情窗和选角提示都用它，省得两处各写一遍
static func 上色(技能文本: String) -> String:
	var 行列表: Array[String] = []
	for 行文本: String in 技能文本.split("\n"):
		行列表.append(_染类型(行文本))
	return "\n".join(行列表)


## 行首（可带缩进）是「【类型】」时给这截连同方括号一起上色（BBCode）；别的行原样返回
static func _染类型(行文本: String) -> String:
	var 缩进: String = 行文本.substr(0, 行文本.length() - 行文本.lstrip("　 ").length())
	var 正文: String = 行文本.substr(缩进.length())
	for 类型: String in 技能类型颜色:
		var 前缀: String = "【%s】" % 类型
		if 正文.begins_with(前缀):
			return "%s[color=#%s]%s[/color]%s" % [
				缩进, 技能类型颜色[类型], 前缀, 正文.substr(前缀.length())]
	return 行文本


## 打开某名角色的技能说明
func 打开(角色号: int) -> void:
	HeroName.text = Data.role_name(角色号)
	Hero.texture = _贴图(立绘目录 + str(角色号) + "L.png")
	var 派系: String = Data.role_property(角色号)
	RoleProperty.texture = Art.role_property_icon(派系)
	RoleProperty.visible = RoleProperty.texture != null
	SkillText.text = 上色(Data.role_skill_info(角色号))
	visible = true


func _on_close() -> void:
	visible = false


func _贴图(路径: String) -> Texture2D:
	if not ResourceLoader.exists(路径):
		return null
	return load(路径) as Texture2D
