## 3D 魔弹的 2D 预制体脚本（与 斩击2D.gd 参数功能一致，但**独立**一份，后面魔弹要改功能就改这里，不动斩击）。
## 预制体里已经摆好了 SubViewport + 相机 + 3D 魔弹（视口容器 / 视口 / 特效位 / 特效，
## 其中「特效」是 scenes/prefabs/effects/魔弹3D/魔弹.tscn 的实例），
## 对外接口与旧特效一致：播放(起, 止, 飞行)。
##
## 叠加方式与斩击相同：SubViewport 用**黑色不透明**底、容器走**加法混合**。
class_name 魔弹2D
extends Node2D

## 预制体里的 3D 魔弹节点（在预制体的检查器里绑好：视口容器/视口/特效位/特效）
@export var VFX: 特效控制器3D

## 预制体里垫在魔弹下面的背景光点（本预制体暂未放背景节点，命中隐藏背景 也先关着）
@export var BG: Sprite2D

## 飞完全程的时长（秒）
@export var 飞行时长: float = 0.5

## 出场倍速：3D 魔弹自身的动画/材质流动速度（1.0 = 原速）
@export var 出场倍速: float = 1.0

## 命中后整体淡到全透明所用的时间（秒）
@export var 透明时长: float = 0.25

## 命中后缩小的快慢：每秒缩掉多少缩放值（1.0 = 一秒缩掉 1.0 的缩放）。
## 实际用时 = 当前缩放 / 缩小速度
@export var 缩小速度: float = 6.0

## 命中时是否把「背景」收掉（本预制体还没有背景节点，先关着）
@export var 命中隐藏背景: bool = false

## 命中后等多久才销毁（秒）
@export var 收尾时长: float = 1.2

## 显示缩放（1.0 = 视口原尺寸 1600×512）—— 单独调魔弹大小
@export var 显示缩放: float = 0.75

## 全局缩放倍率：想用代码统一放大/缩小所有魔弹，改这一个值就行，例如
##     魔弹2D.全局缩放倍率 = 1.5
## 它是脚本级的静态值，改完对之后打出的所有魔弹立即生效，最终大小 = 显示缩放 × 全局缩放倍率
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
		# 向左飞时把画面上下翻一下，免得魔弹倒扣（与斩击同一个处理）
		scale.y = -总缩放 if 止.x < 起.x else 总缩放
	VFX.speed_scale = 出场倍速
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


## 到位：整体快速缩小 + 淡到透明（时长/速度见 透明时长、缩小速度），再等 收尾时长 销毁自己
func _命中() -> void:
	_运行中 = false
	if 命中隐藏背景:
		BG.visible = false
	var 缩小时长: float = absf(scale.x) / maxf(缩小速度, 0.01)
	var 淡出色: Color = modulate
	淡出色.a = 0.0
	var t: Tween = create_tween()
	t.set_parallel(true)
	t.tween_property(self, "scale", Vector2.ZERO, 缩小时长)
	t.tween_property(self, "modulate", 淡出色, maxf(透明时长, 0.01))
	t.set_parallel(false)
	t.tween_interval(收尾时长)
	t.tween_callback(queue_free)
