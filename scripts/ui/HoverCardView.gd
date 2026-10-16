class_name 悬停卡预览
extends VBoxContainer
## 悬停状态图标时的预览：一行状态名 + 一张卡面（只给人看：不可点、不置灰）。
## 结构在 HoverCardView.tscn 里（卡面是 Card.tscn 的实例）；本脚本只管塞数据与尺寸。

## 状态名单独写一行：光看卡面认不出「这是哪一版」（如【圣盾】的幻 / 圣 / 咏三版卡图是同一张）
@export var 状态名: Label
## 卡面视图（Card.tscn 的实例，挂 scripts/CardUI.gd）
@export var 卡牌: Control


## 预览压在鼠标与图标之间：只要有子控件吃鼠标，图标的 hover 就被掐断、提示一闪一闪
func _ready() -> void:
	_整树忽略鼠标(self)


## 铺一次预览：牌 + 状态名 + 卡面尺寸 + 状态名字号
func 设置(牌: GCard, 状态名文本: String, 尺寸: Vector2, 字号: int) -> void:
	状态名.text = 状态名文本
	状态名.add_theme_font_size_override("font_size", 字号)
	卡牌.set_anchors_preset(Control.PRESET_TOP_LEFT)
	卡牌.custom_minimum_size = 尺寸
	卡牌.size = 尺寸
	# 状态名比卡面宽时让卡面保持原宽、居中，不被拉长
	卡牌.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	# 「不可用」+「不置灰」= 正常亮度但不显示边框（预览只是给人看，不需要可选光晕）
	卡牌.call("设置卡牌", 牌, false, false)


## 把一棵子树里的 Control 全部设成「不拾取鼠标」（自己 + 所有后代）
func _整树忽略鼠标(节点: Node) -> void:
	if 节点 is Control:
		(节点 as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for 子: Node in 节点.get_children():
		_整树忽略鼠标(子)