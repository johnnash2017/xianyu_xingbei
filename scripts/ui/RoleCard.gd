class_name 角色卡
extends Button
## 选角界面的一张角色卡：整张立绘（无边框、无名字），立绘缺失时退回深色占位块。
## 结构与外观都在 RoleCard.tscn 里（可所见即所得地改）；本脚本只管「按角色铺外观」与「选中框」。

## 卡面立绘（260×363，按比例放大裁切填满）
@export var 立绘: TextureRect
## 立绘缺失（尚无素材的角色）时的深色占位块，避免格子出现空洞
@export var 占位: ColorRect
## 「已选定」的黄色描边框（选角里点过的立绘亮它；同一时刻只有一张亮着）
@export var 选中框: Panel


## 卡面上的立绘 / 占位块 / 选中框都不吃鼠标事件：它们是按钮的子节点，
## 留着 STOP 的话鼠标在卡面上一移动就在「按钮 ↔ 子图」之间反复判进出，
## 悬停说明跟着一收一弹 —— 表现就是「在同一张卡上挪鼠标也狂闪」。
func _ready() -> void:
	for 子: Node in [立绘, 占位, 选中框]:
		if 子 is Control:
			(子 as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE

## 铺一张角色卡的立绘；可交互 = false（还没轮到自己选 / 这轮已经锁定）时按钮禁用，压暗与否由 压暗 定
## （全角色预览里卡片不可点，但立绘要亮着看图，那时传 压暗 = false）
func 设置外观(贴图: Texture2D, 可交互: bool, 压暗: bool = true) -> void:
	立绘.texture = 贴图
	立绘.visible = 贴图 != null
	占位.visible = 贴图 == null
	立绘.modulate = Color(0.62, 0.62, 0.62, 1.0) if (压暗 and not 可交互) else Color.WHITE
	disabled = not 可交互


## 这张卡是不是当前选定的角色：亮起 / 熄灭黄色描边框
func 设置选中(值: bool) -> void:
	选中框.visible = 值
