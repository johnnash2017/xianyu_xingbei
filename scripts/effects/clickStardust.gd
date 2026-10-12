## 全游戏鼠标点击星屑 —— 挂在 autoload（ClickDust），任何界面里按鼠标都会在指针处迸出一小簇星屑。
## 用 CanvasLayer（layer 128）承载，永远画在最上层；粒子是一次性的，放完自毁。
## 星屑本体是特效目录里的预制体（scenes/prefabs/effects/clickStardust.tscn），
## 要调粒子的贴图 / 数量 / 速度 / 大小 / 颜色，直接改那个场景即可，本脚本只负责在指针处放一台。
## 与其它界面效果一样只做表现：不消费输入，按钮照常响应。
extends Node

## 星屑预制体（一次性爆发、同一帧全部出膛）
const 星屑预制: PackedScene = preload("res://scenes/prefabs/effects/clickStardust.tscn")
## 按住不松时每隔这么久再迸一簇（秒）：连起来就是「一直按着、持续冒星屑」
const 连发间隔: float = 0.08
## 点击处的小震荡波（节点 + 着色器材质在 ClickShockwave.tscn 里；复用受击那枚着色器，
## 但参数比受击小得多，只是点一下的涟漪）：
## 时长（秒）、最大半径 / 波带厚度 / 波内位移强度（按屏幕高算的 UV 单位）
const 震荡波预制: PackedScene = preload("res://scenes/prefabs/effects/ClickShockwave.tscn")
const 震荡波时长: float = 0.26
const 震荡波半径: float = 0.12
const 震荡波波宽: float = 0.025
const 震荡波强度: float = 0.007

var _层: CanvasLayer = null
## 指针当前所在（跟随鼠标移动事件更新），按住连发时星屑就从这里冒出
var _指针位置: Vector2 = Vector2.ZERO
## 距离下一次连发还剩多久
var _连发计时: float = 0.0


func _ready() -> void:
	_层 = CanvasLayer.new()
	# 画在所有界面之上（战斗界面自身的根 CanvasLayer 默认是 0 层）
	_层.layer = 128
	add_child(_层)


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var 按键: InputEventMouseButton = event as InputEventMouseButton
		if 按键.button_index != MOUSE_BUTTON_LEFT and 按键.button_index != MOUSE_BUTTON_RIGHT:
			return
		# 按下先立即迸一簇、并叠一圈小震荡波，之后由 _process 按住连发（连发只冒星屑）
		if 按键.pressed:
			_指针位置 = 按键.position
			_连发计时 = 0.0
			_迸星屑(_指针位置)
			_迸震荡波(_指针位置)
	elif event is InputEventMouseMotion:
		_指针位置 = (event as InputEventMouseMotion).position


## 按住鼠标左 / 右键期间，按 连发间隔 持续在指针处迸星屑
func _process(delta: float) -> void:
	if not (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)):
		_连发计时 = 0.0
		return
	_连发计时 += delta
	while _连发计时 >= 连发间隔:
		_连发计时 -= 连发间隔
		_迸星屑(_指针位置)
		_迸震荡波(_指针位置)


## 在指针处放一台一次性粒子发射器，星屑向外四散、上飘并淡出，放完自毁
func _迸星屑(位置: Vector2) -> void:
	var 粒子: GPUParticles2D = 星屑预制.instantiate() as GPUParticles2D
	粒子.position = 位置
	_层.add_child(粒子)
	粒子.restart()
	粒子.emitting = true
	await get_tree().create_timer(粒子.lifetime + 0.2).timeout
	粒子.queue_free()


## 在点击处叠一圈小震荡波：一块铺满屏幕的透明 ColorRect 挂着扭曲着色器，
## 从点击点向外扩散一圈波前后淡出并自毁（与受击震荡波同一套做法，只是参数更小）
func _迸震荡波(中心: Vector2) -> void:
	var 视口: Vector2 = get_viewport().get_visible_rect().size
	if 视口.x <= 0.0 or 视口.y <= 0.0:
		return
	var 波: ColorRect = 震荡波预制.instantiate()
	var 材质: ShaderMaterial = 波.material as ShaderMaterial
	_层.add_child(波)
	波.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	材质.set_shader_parameter("center_uv", 中心 / 视口)
	材质.set_shader_parameter("aspect", 视口.x / 视口.y)
	材质.set_shader_parameter("radius", 震荡波半径)
	材质.set_shader_parameter("band", 震荡波波宽)
	材质.set_shader_parameter("strength", 震荡波强度)
	材质.set_shader_parameter("progress", 0.0)
	材质.set_shader_parameter("fade", 1.0)
	var t: Tween = 波.create_tween()
	t.set_parallel(true)
	t.tween_method(_设波进度.bind(材质), 0.0, 1.0, 震荡波时长)
	# 前 40% 保持不透明（波还没走远），之后再淡出
	t.tween_method(_设波淡出.bind(材质), 1.0, 0.0, 震荡波时长 * 0.6).set_delay(震荡波时长 * 0.4)
	t.chain().tween_callback(波.queue_free)


func _设波进度(值: float, 材质: ShaderMaterial) -> void:
	材质.set_shader_parameter("progress", 值)


func _设波淡出(值: float, 材质: ShaderMaterial) -> void:
	材质.set_shader_parameter("fade", 值)
