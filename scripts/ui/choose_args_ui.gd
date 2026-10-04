## 参数选择窗口（技能 / 卡牌 / 能量 / 治疗数）—— 搬自参考工程 scenes/prefabs/ui/ChooseArgsUI.tscn。
## 参考工程那版是个下拉框（Dropdown，选中即生效）；这里按需求改成**按钮列表**罗列所有选项，
## 并带一个「取消」按钮可以后撤一层。本工程特殊行动的第二层（选「用哪些星石」）走这个窗口。
class_name 参数选择窗口
extends Control

## 选中了某一项，参数就是该项的 args
signal 选择了(参数: Array)
## 点了取消（可以退回上一层）
signal 取消了

## 节点名：Title 标题、OptionsBox 选项按钮容器、BtnBack 取消（沿用参考工程的 Title / btnBack 叫法）
@export var Title: Label
@export var OptionsBox: VBoxContainer
@export var BtnBack: Button

## 每个选项按钮的尺寸（宽度会被容器拉满，这里主要定高度；按钮容器会按内容自己撑开面板）
const 选项按钮尺寸: Vector2 = Vector2(1000.0, 88.0)
## 选项按钮的字号（长文案如「我方 -1 宝石 -1 水晶，队友 +1 宝石 +1 水晶」要放得下）
const 选项字号: int = 36

## 当前渲染出来的选项按钮
var _选项按钮: Array[Button] = []


func _ready() -> void:
	BtnBack.pressed.connect(_on_back_pressed)
	visible = false


## 打开窗口：选项列表每一项是 {"text": 条目文字, "args": 选中后要提交的参数, "可用": 可选，默认 true}。
## 「可用」为 false 时该选项按钮置灰（如手里没风系攻击牌时的【风怒追击】）。
## 可取消 = false 时藏掉「取消」按钮（这类询问必须先选一项，如【百鬼夜行】的效果选择）
func 打开(标题文本: String, 选项列表: Array, 可取消: bool = true) -> void:
	Title.text = 标题文本
	BtnBack.visible = 可取消
	_清空选项()
	for 项: Variant in 选项列表:
		var d: Dictionary = 项
		_加选项按钮(str(d.get("text", "")), d.get("args", []), bool(d.get("可用", true)))
	visible = true


func _加选项按钮(文案: String, 参数: Array, 可用: bool = true) -> void:
	var b: Button = Button.new()
	b.text = 文案
	b.custom_minimum_size = 选项按钮尺寸
	b.add_theme_font_size_override("font_size", 选项字号)
	b.disabled = not 可用
	b.pressed.connect(_on_option_pressed.bind(参数))
	OptionsBox.add_child(b)
	_选项按钮.append(b)


func _清空选项() -> void:
	for b: Button in _选项按钮:
		if is_instance_valid(b):
			b.queue_free()
	_选项按钮.clear()


func _on_option_pressed(参数: Array) -> void:
	visible = false
	选择了.emit(参数)


func _on_back_pressed() -> void:
	visible = false
	取消了.emit()
