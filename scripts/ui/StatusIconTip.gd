class_name 状态图标预览
extends VBoxContainer
## 悬停状态图标 / 指示物时的预览：把图标原图放大 + 一行说明。
## 面板上那枚图标只有 28px，还套着「描边 + 马赛克」材质，认不清；这里直接摆原贴图（不套任何材质），
## 所以比面板上清楚得多。结构在 StatusIconTip.tscn 里（大图 + 文字），本脚本只管塞数据与尺寸。

## 大图：原贴图，不带描边/马赛克材质（要的就是「看得清」）
@export var 图标: TextureRect
## 说明文字：状态名 / 独有效果说明 / 「黄魂 3/5」这类
@export var 文本: RichTextLabel


## 预览压在鼠标与图标之间：只要子控件吃鼠标，图标的 hover 就被掐断、提示一闪一闪
func _ready() -> void:
	_整树忽略鼠标(self)


## 铺一次预览：贴图 + 说明 + 大图边长 + 字号
func 设置(贴图: Texture2D, 说明: String, 边长: float, 字号: int) -> void:
	图标.texture = 贴图
	图标.custom_minimum_size = Vector2(边长, 边长)
	图标.size = Vector2(边长, 边长)
	文本.text = 说明
	文本.add_theme_font_size_override("normal_font_size", 字号)
	文本.add_theme_font_size_override("bold_font_size", 字号)


## 把一棵子树里的 Control 全部设成「不拾取鼠标」（自己 + 所有后代）
func _整树忽略鼠标(节点: Node) -> void:
	if 节点 is Control:
		(节点 as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for 子: Node in 节点.get_children():
		_整树忽略鼠标(子)
