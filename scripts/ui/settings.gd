extends Control
## 设置浮层 —— 调背景音乐 / 效果音音量（对照参考工程 OptionsUI，只保留当前工程支持的两项）。
## 由 UI.切换设置() 挂到界面层最上面，盖在当前界面之上；点「关闭」收起。
## 界面结构全在 scenes/Settings.tscn 里（所见即所得地改），本脚本只绑节点 + 跑逻辑。

@export var 总音量滑杆: HSlider
@export var 音乐滑杆: HSlider
@export var 音效滑杆: HSlider
@export var 关闭按钮: Button
## 退出房间：玩家和观战者都能用，只在房间里时才显示（登录 / 房间列表里没房间可退）
@export var 退出房间按钮: Button


func _ready() -> void:
	# 先按当前音量摆好滑杆，再挂监听（否则初始化赋值会立刻触发一次回调）
	总音量滑杆.value = Audio.总音量
	音乐滑杆.value = Audio.音乐音量
	音效滑杆.value = Audio.音效音量
	总音量滑杆.value_changed.connect(Audio.设置总音量)
	音乐滑杆.value_changed.connect(Audio.设置音乐音量)
	音效滑杆.value_changed.connect(Audio.设置音效音量)
	关闭按钮.pressed.connect(UI.关闭设置)
	退出房间按钮.pressed.connect(_on_exit_room_pressed)
	退出房间按钮.visible = Logic.in_room


## 退出房间：收起设置浮层 → 通知服务端离房 → 回房间列表。
## 与准备室的「返回大厅」是同一套动作；观战者同样适用（服务端会把它从观战名单里摘掉）
func _on_exit_room_pressed() -> void:
	UI.关闭设置()
	Logic.leave_room()
	UI.goto_lobby()


## 收起时把音量写进本地配置（拖动过程只实时生效，不频繁落盘）
func _exit_tree() -> void:
	Audio.保存音量设置()
