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
	return 标签
