class_name 富文本提示按钮
extends Button
## 悬浮提示改用 RichTextLabel 渲染。
## Godot 默认的 tooltip 是纯文本 Label，而技能说明里的类型是 BBCode 上色的，
## 用默认渲染会把 [color=#xxxxxx] 原样显示出来。
## 另外 _make_custom_tooltip 只在「持有 tooltip 的那个控件」上生效 —— 写在场景脚本里没用，
## 所以做成这个按钮子类：动态建按钮时 new 它，tooltip_text 照常写。

## 提示内容用预制体 scenes/prefabs/battlemobile/SkillTooltip.tscn：
## 里面挂的是插件 label_font_auto_sizer 的 RichLabelAutoSizer，字号、框子大小都在那儿调
const 提示场景: PackedScene = preload("res://scenes/prefabs/battlemobile/SkillTooltip.tscn")


func _make_custom_tooltip(文本: String) -> Object:
	var 标签: RichLabelAutoSizer = 提示场景.instantiate()
	# 提示框是先建控件、后布局：布局前尺寸是 0，插件会误判「内容放不下」一路缩字号，
	# 所以布局尺寸一变就让它重新算一次
	标签.resized.connect(func() -> void: 标签.call_deferred("_check_line_count"))
	标签.text = 文本
	# 提示框不接收鼠标：它常常盖在角色卡上（被夹回屏幕内之后更是如此），
	# 别让它挡住下面卡片的鼠标信号
	标签.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 引擎按光标位置摆这个 Popup，靠近屏幕右 / 下边时会顶出可视区 —— 等它摆好后再夹回来
	标签.ready.connect(_把提示框夹回可视区.bind(标签), CONNECT_ONE_SHOT)
	return 标签


## 提示框超出可视区右 / 下边界时整体往回挪，保证整框留在屏幕内
func _把提示框夹回可视区(标签: Control) -> void:
	# 延后一帧：引擎是在把提示框弹出来之后才定好位置的，此刻读到的才是最终位置
	标签.get_tree().process_frame.connect(_夹一次.bind(标签), CONNECT_ONE_SHOT)


func _夹一次(标签: Control) -> void:
	if not is_instance_valid(标签) or not 标签.is_inside_tree():
		return
	标签.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 提示框挂在引擎建的 Popup（子窗口）里；往上找到那个 Window（中间可能夹着容器节点）
	var 节点: Node = 标签.get_parent()
	while 节点 != null and not (节点 is Window):
		节点 = 节点.get_parent()
	var 弹层: Window = 节点 as Window
	if 弹层 == null:
		return
	var 屏: Vector2 = get_viewport().get_visible_rect().size
	var 尺寸: Vector2 = 弹层.size
	var 位置: Vector2 = 弹层.position
	位置.x = clampf(位置.x, 0.0, maxf(屏.x - 尺寸.x, 0.0))
	位置.y = clampf(位置.y, 0.0, maxf(屏.y - 尺寸.y, 0.0))
	弹层.position = 位置
