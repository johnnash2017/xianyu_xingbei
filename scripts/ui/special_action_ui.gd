## 特殊行动窗口（购买 / 合成 / 提炼）—— 从参考工程 scenes/prefabs/ui/SpecialActionUI.tscn 搬过来。
## 参考工程里它由 UIManager + Agent.FSM 驱动；本工程直接把选择结果用信号交回战斗界面。
class_name 特殊行动窗口
extends Control

## 选中某种特殊行动，值为 GConst.SpecialAction.*
signal 选择了(行动号: int)
## 点了取消 / 返回
signal 取消了

## 节点名沿用参考工程（BtnSynthesis / Titile 这两个拼写是参照 scene 原样保留的）
@export var BtnBuy: Button
@export var BtnSynthesis: Button
@export var BtnExtract: Button
@export var BtnBack: Button
@export var Titile: Label


func _ready() -> void:
	BtnBuy.pressed.connect(选择了.emit.bind(GConst.SpecialAction.Buy))
	BtnSynthesis.pressed.connect(选择了.emit.bind(GConst.SpecialAction.Synthesize))
	BtnExtract.pressed.connect(选择了.emit.bind(GConst.SpecialAction.Extract))
	BtnBack.pressed.connect(取消了.emit)
	visible = false


## 打开窗口，并按可用性压灰三个按钮（判定口径见战斗界面的 _进入特殊行动）。
## 注意：Button 默认的 icon_disabled_color 是 Color(1,1,1,0.4) —— 不可用的按钮会整个变「半透明」，
## 看着像界面坏了。三个按钮在场景里都覆盖成了不透明的深灰（Color(0.5,0.5,0.5,1)），所以这里只管 disabled。
func 打开(可购买: bool, 可合成: bool, 可提炼: bool) -> void:
	BtnBuy.disabled = not 可购买
	BtnSynthesis.disabled = not 可合成
	BtnExtract.disabled = not 可提炼
	Titile.text = "选择要执行的行动"
	visible = true
