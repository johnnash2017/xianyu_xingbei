## 弃牌动效的 2D 预制体脚本：一张卡背从角色身上飞向画面中心（弃牌堆所在处），
## 边飞边淡出，到位时销毁自己。
## 对外接口与 给牌2D 一致：播放(起, 止)。弃多张时由调用方实例化多份、用「延迟时长」错开
## （见 battle_mobile._弃牌特效）。
## 预制体里画的是通用卡背（白边 + 深色卡面 + 中间菱形），与 给牌.tscn 同一套画法。
## 预制体根节点是 **CanvasGroup**：整张牌的多层先合成一张再整体变透明，否则淡出时
## 描边 / 卡面 / 菱形会各自变透明、互相透出来（所以淡出用的是 self_modulate）。
class_name 弃牌2D
extends Node2D

## 从起点飞完全程的时长（秒）
@export var 飞行时长: float = 0.6
## 起飞前的等待（秒）：弃多张时靠它错开，一张接一张飞
@export var 延迟时长: float = 0.0
## 起飞点相对角色中心的散布范围（±像素）
@export var 起点散开: float = 36.0
## 落点相对画面中心的散布范围（±像素）：同一次弃牌的多张不会叠在同一点
@export var 终点散开: float = 70.0
## 飞行途中的旋转（弧度）：从 起始角度 转到 结束角度
@export var 起始角度: float = -0.3
@export var 结束角度: float = 0.5
## 淡出从飞行的哪个进度开始（0.35 = 飞了三成半后开始变淡）
@export var 淡出起点: float = 0.35
## 显示缩放（1.0 = 预制体里画的大小）
@export var 显示缩放: float = 1.0

var _起: Vector2 = Vector2.ZERO
var _止: Vector2 = Vector2.ZERO
## 计时：负数表示还在「延迟」里等起飞
var _计时: float = 0.0
var _运行中: bool = false


## 起 / 止 = 屏幕坐标（起一般取玩家面板中心，止取画面中心）
func 播放(起: Vector2, 止: Vector2) -> void:
	# 起点在角色身上散开一点、落点也在画面中心附近随机偏一段，让多张牌各飞各的
	_起 = 起 + Vector2(randf_range(-起点散开, 起点散开), randf_range(-起点散开, 起点散开) * 0.7)
	_止 = 止 + Vector2(randf_range(-终点散开, 终点散开), randf_range(-终点散开, 终点散开) * 0.6)
	global_position = _起
	rotation = 起始角度
	scale = Vector2.ONE * 显示缩放
	# 淡出走 self_modulate（不是 modulate）：预制体根是 CanvasGroup，整张牌（白边 / 卡面 / 纹）
	# 先合成一张再一起变透明 —— 用 modulate 会逐层变透明，描边会从卡面底下透出来
	self_modulate = Color(1.0, 1.0, 1.0, 1.0)
	_计时 = -延迟时长
	_运行中 = true
	# 还在排队等起飞时先别露脸，免得起点堆着一摞卡背
	visible = 延迟时长 <= 0.0


func _process(delta: float) -> void:
	if not _运行中:
		return
	_计时 += delta
	if _计时 < 0.0:
		return
	visible = true
	var 进度: float = clampf(_计时 / maxf(飞行时长, 0.01), 0.0, 1.0)
	# 位移用缓出：出手快、越飞越慢，像牌从手里甩出去
	var t: float = 1.0 - pow(1.0 - 进度, 2.0)
	global_position = _起.lerp(_止, t)
	rotation = lerpf(起始角度, 结束角度, 进度)
	# 飞过半程后渐渐淡出（用 smoothstep 让淡出两头都平滑）；self_modulate 对整张合成好的牌生效
	self_modulate.a = 1.0 - smoothstep(淡出起点, 1.0, 进度)
	if 进度 >= 1.0:
		queue_free()
