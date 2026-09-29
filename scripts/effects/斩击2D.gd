## 3D 斩击的 2D 预制体脚本：预制体里已经摆好了 SubViewport + 相机 + 3D 斩击
##（视口容器 / 视口 / 特效位 / 特效，其中「特效」是 scenes/prefabs/effects/斩击3D/ 里对应元素那一份的实例），
## 对外接口与旧的 2D「斩击特效」完全一致：播放(起, 止, 飞行)。
##
## 叠加方式：SubViewport 用**黑色不透明**底、容器走**加法混合** —— 黑色不参与叠加，
## 辉光（glow）也不会被 alpha 吃掉，效果和界面能叠在一起发光。
## 例外：【暗灭】要表现黑色（黑底加法等于消失），它改用普通混合（blend_mode = 0）+ 视口开 transparent_bg。
class_name 斩击2D
extends Node2D

## 预制体里的 3D 斩击节点（在各预制体的检查器里绑好：视口容器/视口/特效位/特效）
@export var VFX: 特效发射器3D

## 预制体里垫在斩痕下面的背景光点（在各预制体的检查器里绑好：背景），命中时会被隐藏
@export var BG: Sprite2D

## 飞完全程的时长（秒）
@export var 飞行时长: float = 0.5

## 出场倍速：3D 特效的「出现」动画（斩痕淡入，原速 0.6 秒）播放多快。
## 调大就能一出手就看到完整斩痕（1.0 = 不加速，按原始淡入速度）
@export var 出场倍速: float = 6.0

## 命中后等多久才销毁（秒）—— 留给 3D 特效播「消失」动画与粒子拖尾
@export var 收尾时长: float = 1.2

## 显示缩放（1.0 = 视口原尺寸 512×512）—— 单张牌自己的缩放，在预制体上单独调
@export var 显示缩放: float = 0.75

## 全局缩放倍率：想用代码统一放大/缩小所有斩击，改这一个值就行，例如
##     斩击2D.全局缩放倍率 = 1.5
## 它是脚本级的静态值，改完对之后打出的所有斩击立即生效，最终大小 = 显示缩放 × 全局缩放倍率
static var 全局缩放倍率: float = 1.0

var _起: Vector2 = Vector2.ZERO
var _止: Vector2 = Vector2.ZERO
var _计时: float = 0.0
var _运行中: bool = false


## 起 / 止 = 屏幕坐标（一般取玩家面板中心）；飞行 = false 时原地炸开
func 播放(起: Vector2, 止: Vector2, 飞行: bool) -> void:
	_起 = 起
	_止 = 止 if 飞行 else 起
	global_position = 起
	var 总缩放: float = 显示缩放 * 全局缩放倍率
	scale = Vector2.ONE * 总缩放
	if 飞行:
		rotation = 起.direction_to(止).angle()
		# 向左飞时把画面上下翻一下，免得斩痕倒扣（与旧 2D 斩击同一个处理）
		scale.y = -总缩放 if 止.x < 起.x else 总缩放
	VFX.emitting = true            # 播 open：斩痕淡入 + 粒子开始发射
	# open 默认要 0.6 秒才淡入完整，飞行途中会一直是半透明的「残缺」样子；
	# 这里把「出现」这一段加速播完 —— 一出手就是完整斩痕，飞到位再慢慢消失
	VFX.anim.speed_scale = 出场倍速
	_计时 = 0.0
	_运行中 = true


func _process(delta: float) -> void:
	if not _运行中:
		return
	_计时 += delta
	var 进度: float = clampf(_计时 / 飞行时长, 0.0, 1.0)
	global_position = _起.lerp(_止, 进度)
	if 进度 >= 1.0:
		_命中()


## 到位：让 3D 特效播 close（斩痕淡出、粒子停止发射，已经喷出的拖尾飞完），再等 收尾时长 销毁自己
func _命中() -> void:
	_运行中 = false
	BG.visible = false             # 命中就把背景光点收掉，只留斩痕的消失动画
	VFX.anim.speed_scale = 1.0     # 消失这一段按原始速度播，别跟着出场一起加速
	VFX.emitting = false
	var t: Tween = create_tween()
	t.tween_interval(收尾时长)
	t.tween_callback(queue_free)
