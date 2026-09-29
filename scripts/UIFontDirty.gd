## 字体图集脏标记 —— 对应 AGrail.UIFontDirty
##
## Unity 侧订阅 Font.textureRebuilt，在字体图集重建后手工对同字体的 Text 调
## FontTextureChanged() 重排版。Godot 的字体图集（FontFile / MSDF）由引擎自动管理，
## 既没有等价事件，也不需要手工重排，因此本类在 Godot 侧只保留同名接口与状态字段，
## 行为退化为空操作（不再需要 LateUpdate 里的全场景 Text 扫描）。
##
## 该脚本在转换后的 tscn 里被声明为 ext_resource（id=5_UIFontDirtygd）但没有挂到任何节点；
## 它不依赖任何 UI 能力，故取最通用的 Node 作为基类（可挂到任意节点）。
extends Node

## 对应 C# private bool isDirty;
var isDirty: bool = false
## 对应 C# private Font dirtyFont;
var dirtyFont: Variant = null

## 对应 C# private void Awake() 里 Font.textureRebuilt += ...
func _ready() -> void:
	# Godot 没有 Font.textureRebuilt 等价事件
	set_process(false)

## 对应 C# private void LateUpdate()
func _process(_delta: float) -> void:
	if not isDirty:
		return
	isDirty = false
	# 对应 C# Object.FindObjectsOfType<Text>() 后对 text.font == dirtyFont 的调 FontTextureChanged()
	# Godot 侧由引擎自动重排，这里只清状态。
	dirtyFont = null
