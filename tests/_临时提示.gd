extends SceneTree
## 临时：确认 富文本提示按钮 会返回一个开了 bbcode 的 RichTextLabel 当提示（跑完即删）

func _init() -> void:
	var 按钮: 富文本提示按钮 = 富文本提示按钮.new()
	按钮.tooltip_text = "[color=#ff0000]红[/color]正常"
	var 提示: Object = 按钮._make_custom_tooltip(按钮.get_tooltip())
	if 提示 == null:
		print("没有返回自定义提示控件")
		quit(1)
		return
	print("提示控件=", 提示.get_class(), " bbcode=", 提示.bbcode_enabled, " 文本=", 提示.text)
	quit()
