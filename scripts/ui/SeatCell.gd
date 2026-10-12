class_name 座位格
extends Control
## 座次条上的一个座位：外格（黄框 / 队色框）+ 居中内芯（队色菱形）。
## 结构与三种外观都在 SeatCell.tscn 里（可所见即所得地改）——
## 三张贴图在场景里绑定，删掉任一张时编辑器都会有引用提示。

## 外框（自己那格是黄框，其余按队伍蓝 / 红；未分队时借蓝框调灰）
@export var 外格: TextureRect
## 居中那层小队色菱形
@export var 内格: TextureRect
## 自己那格用的黄框（SeatMain.png）
@export var 外观_主: Texture2D
## 蓝队框 / 菱形（SeatBlue.png）
@export var 外观_蓝: Texture2D
## 红队框 / 菱形（SeatRed.png）
@export var 外观_红: Texture2D


## 按队伍（GConst.RED / GConst.BLUE / GConst.TEAM_NONE）与「是不是自己」铺格。
## 未分队（队 < 0）时没有灰色的座位图，借蓝框调灰，且不画内芯
func 设置(队: int, 是我: bool) -> void:
	外格.self_modulate = Color.WHITE
	内格.visible = 队 >= 0
	if 是我:
		外格.texture = 外观_主
	elif 队 < 0:
		外格.texture = 外观_蓝
		外格.self_modulate = Color(0.6, 0.6, 0.64, 1.0)
	else:
		外格.texture = 外观_红 if 队 == GConst.RED else 外观_蓝
	if 队 >= 0:
		内格.texture = 外观_红 if 队 == GConst.RED else 外观_蓝