extends Control
## 设置浮层 —— 调背景音乐 / 效果音音量（对照参考工程 OptionsUI，只保留当前工程支持的两项）。
## 由 UI.切换设置() 挂到界面层最上面，盖在当前界面之上；点「关闭」收起。
## 界面结构全在 scenes/Settings.tscn 里（所见即所得地改），本脚本只绑节点 + 跑逻辑。

@export var 音乐滑杆: HSlider
@export var 音效滑杆: HSlider
@export var 关闭按钮: Button


func _ready() -> void:
	# 先按当前音量摆好滑杆，再挂监听（否则初始化赋值会立刻触发一次回调）
	音乐滑杆.value = Audio.音乐音量
	音效滑杆.value = Audio.音效音量
	音乐滑杆.value_changed.connect(Audio.设置音乐音量)
	音效滑杆.value_changed.connect(Audio.设置音效音量)
	关闭按钮.pressed.connect(UI.关闭设置)


## 收起时把音量写进本地配置（拖动过程只实时生效，不频繁落盘）
func _exit_tree() -> void:
	Audio.保存音量设置()
