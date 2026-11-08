class_name 专属卡牌分组框
extends MarginContainer
## 专属卡牌分组框：外缩进 + 圆角描边面板 + 标题 + 技能列表。
##
## 结构全部在 [code]scenes/prefabs/ui/SkillGroupBox.tscn[/code] 里，可以直接在编辑器里调：
##  - 标题字号 / 颜色：看「边框/内容/标题」这个 Label；
##  - 标题和第一条技能之间的空隙：只由「内容」这层 VBoxContainer 的 separation 决定
##    （默认 -8：把标题 Label 自带的那截行距压掉；觉得还空就往更负调，觉得挤就调回 0）；
##  - 面板内边距 / 圆角 / 边框粗细：看「边框」PanelContainer 的 StyleBoxFlat；
##  - 整个框相对正文的缩进：看根节点 MarginContainer 的 margin_left；
##  - 技能说明本身的字号 / 行距 / 段距：看 SkillGroupItem.tscn。
## 示例技能只用于编辑器里预览间距，进游戏后由本脚本从技能容器里摘掉。

@export var 边框: PanelContainer
@export var 标题: Label
@export var 技能: VBoxContainer
## 编辑器里用来看间距的示例技能；进游戏后摘掉
@export var 示例技能: Control


func _ready() -> void:
	# 示例技能只给编辑器看：进游戏时直接从技能容器里摘掉（不是隐藏 —— 隐藏节点还留在
	# get_child_count() 里，会让「组内技能数」多一个）
	if 示例技能 != null:
		var 父: Node = 示例技能.get_parent()
		if 父 != null:
			父.remove_child(示例技能)
		示例技能.queue_free()
		示例技能 = null


## 标题文本。字号直接用场景里「标题」Label 的字号（默认 18），在编辑器里改那个 Label 即可
func 设置标题(文本: String) -> void:
	标题.text = 文本


## 边框颜色（命格色，和整框同色）。StyleBoxFlat 是 resource_local_to_scene，
## 每个分组框各一份，改颜色不会串到别的框
func 设描边(颜色: Color) -> void:
	var 样式: StyleBoxFlat = 边框.get_theme_stylebox("panel") as StyleBoxFlat
	if 样式 != null:
		样式.border_color = 颜色


## 加一条技能说明（一个技能一个 RichTextLabel，节点来自 SkillGroupItem.tscn）
func 加技能(节点: Control) -> void:
	技能.add_child(节点)
