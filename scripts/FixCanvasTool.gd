## 分辨率适配修正 —— 对应 FixCanvasTool（Assembly-CSharp 根命名空间）
## 原类要求同节点上有 CanvasScaler；转换后唯一挂载点是
## scenes/prefabs/ui/RoleChooseBar.tscn 的根节点 [node name="RoleChooseBar" type="Control"]，
## 即 Canvas + CanvasScaler 所在的根节点被映射成了 Control，故 extends Control。
extends Control

## 对应 C# CanvasScaler.referenceResolution（与 project.godot 的 1280x720 一致）
const REFERENCE_RESOLUTION := Vector2(1280, 720)

## 对应 C# private void Awake()
func _ready() -> void:
	FixResolution()

## 对应 C# public void FixResolution()
func FixResolution() -> void:
	var win := get_window()
	if win == null:
		return
	var ref_ratio := REFERENCE_RESOLUTION.x / REFERENCE_RESOLUTION.y
	# 对应 C# Screen.width / Screen.height
	var screen := Vector2(DisplayServer.window_get_size())
	if screen.x <= 0.0 or screen.y <= 0.0:
		screen = Vector2(win.size)
	if screen.y <= 0.0:
		return
	var screen_ratio := screen.x / screen.y
	# 对应 C# component.matchWidthOrHeight = 0f/1f。
	# 这里只在真的需要改的时候赋值：每个窗口预制体都挂了这个组件，
	# 无条件赋值既没意义，也会在控制台刷一堆「已匹配高度」的黄色警告。
	var target := Window.CONTENT_SCALE_ASPECT_KEEP_WIDTH if ref_ratio > screen_ratio \
		else Window.CONTENT_SCALE_ASPECT_KEEP_HEIGHT
	if win.content_scale_aspect != target:
		win.content_scale_aspect = target
