@tool
extends EditorExportPlugin
## 导出期版本号选项：在「项目 → 导出」的预设里多出一个勾选框
## 「版本号工具 / 导出后版本 +0.0.1」。勾上后，每次导出开始（_export_begin）就把
## project.godot 的版本号末位 +1 并落盘；导出产物读到的就是自增后的新号。
## 由 version_tool.gd 通过 add_export_plugin 注册。
##
## 为什么用勾选框而不是弹窗：Godot 导出流程里 _export_begin 是同步调用，
## 在里面弹模态框会卡住编辑器主线程（界面不再响应），「导出前弹确认」无法可靠实现。
## 勾选框是官方支持的导出选项（_get_export_options），由用户在导出对话框里勾选。

const 选项名: String = "版本号工具/导出后版本 增加0.0.1"


func _get_name() -> String:
	return "版本号工具"


func _supports_platform(_platform: EditorExportPlatform) -> bool:
	return true


## 声明本插件给导出对话框加的那个勾选框（默认不勾）
func _get_export_options(_platform: EditorExportPlatform) -> Array[Dictionary]:
	return [{
		"option": {"name": 选项名, "type": TYPE_BOOL},
		"default_value": false,
	}]


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	if not bool(get_option(选项名)):
		return
	var 新版本: String = VersionBump.加一()
	if 新版本 == "":
		push_warning("[版本号工具] 导出前自增失败：版本号末位不是数字，未改动")
		return
	print("[版本号工具] 导出开始，版本号已自增为 %s（本次导出产物读到的即新号）" % 新版本)
