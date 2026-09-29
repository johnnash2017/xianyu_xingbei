## 卡牌粒子特效 —— 预制体本身就是一台粒子发射器（根节点就是 GPUParticles2D，脚本挂在根上），
## 出手时由 battle_mobile 实例化并调用 播放()。【魔弹】【圣光】用这套；斩击类见 斩击2D.gd（3D 素材转 2D）。
##
## 两种用法：
##   飞行 = true ：整台发射器从出牌者飞向目标；因为 local_coords = false，
##                 喷出的粒子会留在原地被甩在身后 —— 看起来就是一道拖尾
##   飞行 = false：在目标身上原地炸开（【圣光】抵挡 —— 引擎广播的 src 与 dst 是同一人）
class_name 粒子特效
extends GPUParticles2D

## 飞完全程的时长（秒）
@export var 飞行时长: float = 0.30


## 起 / 止 = 屏幕坐标（一般取玩家面板中心）
func 播放(起: Vector2, 止: Vector2, 飞行: bool) -> void:
	global_position = 起 if 飞行 else 止
	if 飞行:
		rotation = 起.direction_to(止).angle() - PI * 0.5
	restart()
	emitting = true
	if not 飞行:
		_延时自毁()
		return
	var t: Tween = create_tween()
	t.tween_property(self, "global_position", 止, 飞行时长)
	t.finished.connect(_延时自毁)


## 让粒子把剩下的部分放完再自毁
func _延时自毁() -> void:
	emitting = false
	await get_tree().create_timer(lifetime + 0.15).timeout
	queue_free()
