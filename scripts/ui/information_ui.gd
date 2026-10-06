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


## 技能文本里正文行的前缀（data_interface._拼技能文本 给每条技能正文加的「　　」）；
## 拿它区分「四个一级标题」（无前缀）与「技能正文」（有前缀）
const 正文前缀: String = "　　"
## 详情窗技能正文的字号（与 InfomationUI.tscn 的 SkillText normal_font_size 一致）
const 详情窗正文字号: int = 18
## 选角提示框技能正文的字号（原 36 的一半）
const 提示框正文字号: int = 18
## 选角提示框里角色名的字号（原 72 的一半）
const 提示框姓名行字号: int = 36
## 选角提示框里「普通技 / 独有技 / 专属技 / 必杀技」这些分段标题的字号（原 54 的一半）
const 提示框标题字号: int = 27


## 给一段拼好的技能说明上色并排版：
##  - 一级标题按 正文字号 的 1.5 倍放大；
##  - 正文整行用 [indent] 缩进（用 [indent] 而非前缀空格，自动换行的续行也跟着缩进，不再和标题同列）；
##  - 行首的【类型】套 BBCode 颜色。
## 行与行之间的间距不在这里处理：改由 RichTextLabel 的 paragraph_separation 主题常量统一给
## （见 InfomationUI.tscn 的 SkillText 与 SkillTooltip.tscn）。不再往文本里插空行——空行本身会占掉
## 一整行高，反而没法把间距压小（这正是之前怎么调都不变的原因）。
## 详情窗和选角提示都用它，省得两处各写一遍。正文字号 0＝除上色外不做排版；
## 标题字号 >0 时用它替代默认的「正文字号 × 1.5」来放大一级标题（选角提示框据此把分段标题做小）
static func 上色(技能文本: String, 正文字号: int = 0, 标题字号: int = 0) -> String:
	var 用标题字号: int = 标题字号 if 标题字号 > 0 else int(正文字号 * 1.5)
	var 行列表: Array[String] = []
	for 行文本: String in 技能文本.split("\n"):
		if 行文本.begins_with(正文前缀):
			# 正文：去掉「　　」前缀，改用 [indent] 整体缩进；正文字号 >0 时整行套 [font_size]
			var 正文行: String = "[indent]%s[/indent]" % _染类型(行文本.substr(正文前缀.length()))
			if 正文字号 > 0:
				正文行 = "[font_size=%d]%s[/font_size]" % [正文字号, 正文行]
			行列表.append(正文行)
		elif 用标题字号 > 0:
			# 一级标题（普通技 / 独有技 / 专属技 / 必杀技）：放大字号
			行列表.append("[font_size=%d]%s[/font_size]" % [用标题字号, 行文本])
		else:
			行列表.append(_染类型(行文本))
	return "\n".join(行列表)


## 行首（可带缩进）是「【类型】」时给这截连同方括号一起上色（BBCode）；别的行原样返回
static func _染类型(行文本: String) -> String:
	var 缩进: String = 行文本.substr(0, 行文本.length() - 行文本.lstrip("　 ").length())
	var 正文: String = 行文本.substr(缩进.length())
	for 类型: String in GConst.技能类型颜色:
		var 前缀: String = "【%s】" % 类型
		if 正文.begins_with(前缀):
			return "%s[color=#%s]%s[/color]%s" % [
				缩进, (GConst.技能类型颜色[类型] as Color).to_html(false), 前缀, 正文.substr(前缀.length())]
	return 行文本


## 打开某名角色的技能说明
func 打开(角色号: int) -> void:
	HeroName.text = Data.role_name(角色号)
	Hero.texture = _贴图(立绘目录 + str(角色号) + "L.png")
	var 派系: String = Data.role_property(角色号)
	RoleProperty.texture = Art.role_property_icon(派系)
	RoleProperty.visible = RoleProperty.texture != null
	SkillText.text = 上色(Data.role_skill_info(角色号), 详情窗正文字号)
	visible = true


func _on_close() -> void:
	visible = false


func _贴图(路径: String) -> Texture2D:
	if not ResourceLoader.exists(路径):
		return null
	return load(路径) as Texture2D
