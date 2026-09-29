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
@export var SkillText: Label
@export var BtnClose: Button

## 立绘目录：<角色号>L.png（与参考工程 LoadAsset<Sprite>("hero_l", RoleID + "L") 一致）
const 立绘目录: String = "res://assets/textures/hero/large/"
## 派系图标目录：技 / 血 / 幻 / 咏 / 圣 .png
const 派系图目录: String = "res://assets/textures/battle/"


func _ready() -> void:
	BtnClose.pressed.connect(_on_close)
	visible = false


## 打开某名角色的技能说明
func 打开(角色号: int) -> void:
	HeroName.text = Data.role_name(角色号)
	Hero.texture = _贴图(立绘目录 + str(角色号) + "L.png")
	var 派系: String = Data.role_property(角色号)
	RoleProperty.texture = _贴图(派系图目录 + 派系 + ".png") if 派系 != "" else null
	RoleProperty.visible = RoleProperty.texture != null
	# 技能说明用数据表里该角色的那一段：这一段就是原客户端「角色技能」界面的原文，
	# 每条前头自带一个空格（数据源格式），这里逐行去掉，免得换行后看着参差不齐
	var 行列表: Array = []
	for 行文本: String in Data.role_skill_info(角色号).split("\n"):
		行列表.append(行文本.strip_edges())
	SkillText.text = "\n".join(行列表)
	visible = true


func _on_close() -> void:
	visible = false


func _贴图(路径: String) -> Texture2D:
	if not ResourceLoader.exists(路径):
		return null
	return load(路径) as Texture2D
