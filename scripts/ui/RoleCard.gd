class_name 角色卡
extends Button
## 选角界面的一张角色卡：整张立绘（无边框、无名字），立绘缺失时退回深色占位块。
## 结构与外观都在 RoleCard.tscn 里（可所见即所得地改）；本脚本只管「按角色铺外观」。

## 卡面立绘（260×363，按比例放大裁切填满）
@export var 立绘: TextureRect
## 立绘缺失（尚无素材的角色）时的深色占位块，避免格子出现空洞
@export var 占位: ColorRect


## 铺一张角色卡的立绘；可交互 = false（还没轮到自己选）时立绘压暗、按钮禁用
func 设置外观(贴图: Texture2D, 可交互: bool) -> void:
	立绘.texture = 贴图
	立绘.visible = 贴图 != null
	占位.visible = 贴图 == null
	立绘.modulate = Color.WHITE if 可交互 else Color(0.62, 0.62, 0.62, 1.0)
	disabled = not 可交互