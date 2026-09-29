## 箭头飞行特效 —— 对应 AGrail.Arrow
## Unity 侧是挂在 ParticleSystem 上的 MonoBehaviour（[RequireComponent(typeof(ParticleSystem))]）；
## 转换后的 scenes/prefabs/battlemobile/Arrow.tscn 根节点是 Node2D（粒子系统未转换过来），
## 因此这里 extends Node2D，并用「子节点兜底 + 定时器兜底」模拟粒子的生命周期。
extends Node2D

## 对应 C# private ParticleSystem particle;
var _particle: Node2D = null

## 对应 C# Update()：粒子播完后自毁；这里用一次性定时器代替（无需每帧轮询）
var _life_timer: SceneTreeTimer = null

func _ready() -> void:
	_particle = _find_particle()
	if _particle == null:
		# 转换后的 Arrow.tscn 里只有根节点，**没有粒子节点**（Unity 的 ParticleSystem 没转过来）：
		# 打出攻击牌指向目标时看不到任何箭头飞行动画（battle_audit D-6）。
		# 这里按 Unity 预设补一个：沿 +Y 发射、lifetime 1s、初始不发射；
		# 飞行速度由 SetParms 用 particle.startSpeed = 距离 / lifetime 换算（speed_scale）。
		var p := CPUParticles2D.new()
		p.name = "Particle"
		p.emitting = false
		p.one_shot = true
		p.amount = 8
		p.lifetime = 1.0
		p.direction = Vector2(0.0, 1.0)
		p.spread = 2.0
		p.gravity = Vector2.ZERO
		p.initial_velocity_min = 1.0
		p.initial_velocity_max = 1.0
		# 尺寸取 Unity 预设的 startSize = 12×该曲线（很快缩到 15%，再线性缩到 0）
		p.scale_amount_min = 6.0
		p.scale_amount_max = 12.0
		p.scale_amount_curve = _尺寸曲线()
		add_child(p)
		_particle = p


## Unity 侧 ParticleSystem 的 startSize 是一条曲线：t=0 满尺寸 → t≈0.05 缩到 15% → t=1 缩到 0
func _尺寸曲线() -> Curve:
	var c: Curve = Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(0.05, 0.15))
	c.add_point(Vector2(1.0, 0.0))
	return c

## 对应 C# GetComponent<ParticleSystem>()
func _find_particle() -> Node2D:
	for c in get_children():
		if c is GPUParticles2D or c is CPUParticles2D:
			return c
	return null

func _find_node(nm: String) -> Node:
	var n := find_child(nm, true, false)
	if n == null:
		push_warning("%s: 找不到节点 %s" % [name, nm])
	return n

## 对应 C# Awake()
## Unity 里 particle 是 GetComponent 拿到的；Godot 里已经在 _ready 里查找过了。

## 对应 C# Update() 中的 Object.Destroy(gameObject)
func _destroy_when_finished() -> void:
	queue_free()

## 对应 C# public void SetParms(Vector3 src, Vector3 dst)
## Quaternion.FromToRotation(Vector3.up, dir) -> 用方向角换算 Node2D.rotation
## particle.startSpeed = magnitude / particle.startLifetime -> 粒子 lifetime 固定为 1s，speed = 距离
func SetParms(src: Vector3, dst: Vector3) -> void:
	var dir := dst - src
	var dist := dir.length()
	global_position = Vector2(src.x, src.y)
	# 粒子沿本地 +Y 发射，把 +Y 转到 dir 即可（Godot 2D 的 y 也是向下，与传入坐标同系）
	var dir2 := Vector2(dir.x, dir.y)
	if dir2.length() > 0.0001:
		rotation = dir2.angle() - PI * 0.5
	if _particle != null:
		var lifetime := 1.0
		if _particle is GPUParticles2D:
			lifetime = (_particle as GPUParticles2D).lifetime
			(_particle as GPUParticles2D).speed_scale = dist / maxf(lifetime, 0.001)
			(_particle as GPUParticles2D).emitting = true
		elif _particle is CPUParticles2D:
			lifetime = (_particle as CPUParticles2D).lifetime
			(_particle as CPUParticles2D).speed_scale = dist / maxf(lifetime, 0.001)
			(_particle as CPUParticles2D).emitting = true
		# 对应 C# Update 里 particle.isStopped 时 Destroy
		_life_timer = get_tree().create_timer(lifetime)
		_life_timer.timeout.connect(_destroy_when_finished)
	else:
		# 转换后的 Arrow.tscn 没有粒子节点：退化为「固定时长后自毁」，
		# 时长沿用 Unity 侧 startLifetime 的默认值（1s）。
		_life_timer = get_tree().create_timer(1.0)
		_life_timer.timeout.connect(_destroy_when_finished)
