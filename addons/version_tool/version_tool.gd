@tool
extends EditorPlugin
## 版本号工具（编辑器插件）：注册导出插件（version_export_plugin.gd），在「项目 → 导出」的预设里
## 多出勾选框「版本号工具 / 导出后版本 增加0.0.1」，勾上则每次导出时自动把版本号末位 +1。
## 版本号读写集中在 VersionBump；它与登录界面底部、Steam 大厅隔离标记用的是同一个值
## （project.godot 的 application/config/version）。

const 导出插件脚本: GDScript = preload("res://addons/version_tool/version_export_plugin.gd")

var _导出插件: EditorExportPlugin = null


func _enter_tree() -> void:
	_导出插件 = 导出插件脚本.new()
	add_export_plugin(_导出插件)


func _exit_tree() -> void:
	if _导出插件 != null:
		remove_export_plugin(_导出插件)
		_导出插件 = null
