## 屏幕适配修正 —— 对应游戏里挂在各窗口根节点上的 UIEdgeFix（C# 类名 UIEdgeFix）。
## 原实现按 Screen.safeArea 调整窗口根节点的内边距，避免刘海/圆角遮挡。
## Godot 侧用 DisplayServer.get_display_safe_area()，窗口根为全屏 Control 时按比例内缩。
extends Control

## 对应 C# 的 roots 字段（参与适配的根节点列表）
var roots: Array[Node] = []

## 对应 C# Awake()：收集需要适配的根节点
func _ready() -> void:
	if roots.is_empty():
		roots.append(self)
	_fit()

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit()

## 对应 C# 的适配逻辑：把内容限制在安全区内
func _fit() -> void:
	var win := get_window()
	if win == null:
		return
	var win_size := Vector2(win.size)
	if win_size.x <= 0.0 or win_size.y <= 0.0:
		return
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or safe.size.y <= 0 or safe.size == Vector2i(win_size):
		return
	var content_scale := win.content_scale_size
	var factor := Vector2(win_size.x / maxf(content_scale.x, 1.0), win_size.y / maxf(content_scale.y, 1.0))
	var l := float(safe.position.x) / factor.x
	var t := float(safe.position.y) / factor.y
	var r := float(win_size.x - safe.position.x - safe.size.x) / factor.x
	var b := float(win_size.y - safe.position.y - safe.size.y) / factor.y
	for n in roots:
		if n is Control:
			var c := n as Control
			c.offset_left = l
			c.offset_top = t
			c.offset_right = -r
			c.offset_bottom = -b
