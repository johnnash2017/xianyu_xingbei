## 给牌动效的 2D 预制体脚本：一张卡背（不公开牌面）沿贝塞尔弧线从交牌人飘到收牌人，
## 到位后缩小 + 淡出并销毁自己。对外接口与 斩击2D 一致：播放(起, 止)。
## 交多张时由调用方实例化多份、用「延迟时长」错开（见 battle_mobile._给牌特效）。
## 预制体里画的是通用卡背（白边 + 深色卡面 + 中间菱形），要换美术直接改预制体即可。
class_name 给牌2D
extends Node2D

## 飞完全程的时长（秒）
@export var 飞行时长: float = 0.75
## 起飞前的等待（秒）：交多张时靠它错开，一张接一张飞
@export var 延迟时长: float = 0.0
## 弧线拱高的基准值 = 起止直线距离 × 这个比例（实际拱高在此基础上随机浮动，方向也随机）
@export var 弧高比例: float = 0.22
## 显示缩放（1.0 = 预制体里画的大小）
@export var 显示缩放: float = 1.0
## 到位后缩小 + 淡出所用的时长（秒）
@export var 淡出时长: float = 0.2
## 飞行途中的旋转（弧度）：从 起始角度 转到 结束角度，像把牌甩过去
@export var 起始角度: float = -0.35
@export var 结束角度: float = 0.2

var _起: Vector2 = Vector2.ZERO
var _止: Vector2 = Vector2.ZERO
## 二次贝塞尔的控制点（起止中点往侧上方拱）
var _控制: Vector2 = Vector2.ZERO
## 计时：负数表示还在「延迟」里等起飞
var _计时: float = 0.0
var _运行中: bool = false


## 起 / 止 = 屏幕坐标（一般取玩家面板中心）
func 播放(起: Vector2, 止: Vector2) -> void:
	_起 = 起
	_止 = 止
	_控制 = _算控制点(起, 止)
	global_position = 起
	rotation = 起始角度
	scale = Vector2.ONE * 显示缩放
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
	global_position = _贝塞尔(_起, _控制, _止, 进度)
	rotation = lerpf(起始角度, 结束角度, 进度)
	if 进度 >= 1.0:
		_到位()


## 二次贝塞尔取点：B(t) = (1-t)²·起 + 2(1-t)t·控制 + t²·止
func _贝塞尔(起: Vector2, 控制: Vector2, 止: Vector2, t: float) -> Vector2:
	var u: float = 1.0 - t
	return u * u * 起 + 2.0 * u * t * 控制 + t * t * 止


## 控制点：起止中点沿法线拱起。拱的方向、拱高、沿路径的前后位置都随机 ——
## 这样同一次给牌的多张弧线形状与扭曲方向都不一样
func _算控制点(起: Vector2, 止: Vector2) -> Vector2:
	var 方向: Vector2 = 止 - 起
	var 法线: Vector2 = 方向.orthogonal().normalized()
	# 往哪一侧拱（上下 / 左右）随机
	if randf() < 0.5:
		法线 = -法线
	var 拱高: float = 方向.length() * 弧高比例 * randf_range(0.6, 1.4)
	# 控制点再沿路径前后偏一点：偏出来的是不对称的弧，看着更「扭」
	var 前后: Vector2 = 方向 * randf_range(-0.2, 0.2)
	return (起 + 止) * 0.5 + 法线 * 拱高 + 前后


## 到位：缩小 + 淡出（与斩击2D 的收尾同一套写法），完事销毁自己
func _到位() -> void:
	_运行中 = false
	var 淡出色: Color = modulate
	淡出色.a = 0.0
	var t: Tween = create_tween()
	t.set_parallel(true)
	t.tween_property(self, "scale", Vector2.ZERO, 淡出时长)
	t.tween_property(self, "modulate", 淡出色, 淡出时长)
	t.set_parallel(false)
	t.tween_callback(queue_free)
