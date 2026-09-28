@tool
extends EditorContextMenuPlugin
## 文件系统面板右键菜单插件：在右键菜单中添加"设置别名…"项（带 Ctrl+Alt+A 快捷键提示）。
## 使用 Godot 官方的 EditorContextMenuPlugin API（Godot 4.4+），
## 点击后把选中的路径列表通过信号交给主插件处理。
## 相比直接 hack 内置菜单，这样不会触发 FileSystemDock 的菜单 id 越界报错。

## 点击"设置别名…"时触发，参数为右键选中的路径列表
signal 设置别名请求(paths: PackedStringArray)

## 菜单项上显示的快捷键（Ctrl+Alt+A）
var _alias_shortcut: Shortcut

func _init() -> void:
	_alias_shortcut = Shortcut.new()
	var event: InputEventKey = InputEventKey.new()
	event.keycode = KEY_A
	event.ctrl_pressed = true
	event.alt_pressed = true
	_alias_shortcut.events = [event]
	# 菜单项被激活（点击，或菜单打开时按快捷键）时触发回调
	add_menu_shortcut(_alias_shortcut, _on_activated)

func _popup_menu(paths: PackedStringArray) -> void:
	if paths.is_empty():
		return
	add_context_menu_item_from_shortcut("设置别名…", _alias_shortcut, _get_rename_icon())

## 使用与文件系统"重命名"菜单项相同的图标
func _get_rename_icon() -> Texture2D:
	var theme: Theme = EditorInterface.get_editor_theme()
	if theme != null and theme.has_icon("Rename", "EditorIcons"):
		return theme.get_icon("Rename", "EditorIcons")
	return null

func _on_activated(paths: Array) -> void:
	var p: PackedStringArray = PackedStringArray()
	for path: Variant in paths:
		p.append(str(path))
	设置别名请求.emit(p)
