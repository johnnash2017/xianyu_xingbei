@tool
extends EditorPlugin
## 版本号工具：在「项目 → 工具」里加一个「版本 +0.0.1」菜单项。
## 打包前点一下，把 project.godot 的 application/config/version 末位加一（1.0.0 → 1.0.1），
## 写完立即落盘。这样登录界面底部的版本号、以及 Steam 大厅隔离标记（由版本派生，见 SteamNet）
## 都会跟着变 —— 新包与旧包互相搜不到。
## 说明：只改末位那一节（形如 x.y.z 的 z）；末位不是数字时什么也不做，免得把非数字版本写坏。

const 菜单名: String = "版本 +0.0.1"
const 版本设置键: String = "application/config/version"


func _enter_tree() -> void:
	add_tool_menu_item(菜单名, _版本加一)


func _exit_tree() -> void:
	remove_tool_menu_item(菜单名)


func _版本加一() -> void:
	var 当前: String = str(ProjectSettings.get_setting(版本设置键, "0.0.0"))
	var 新版本: String = _末位加一(当前)
	if 新版本 == 当前:
		push_warning("[版本工具] 版本号「%s」末位不是数字，未改动" % 当前)
		return
	ProjectSettings.set_setting(版本设置键, 新版本)
	ProjectSettings.save()
	print("[版本工具] 版本号 %s → %s（已写入 project.godot，下次运行 / 打包生效）" % [当前, 新版本])


## 把版本号最后一节加一：1.0.0 → 1.0.1；末位不是数字则原样返回（由调用方提示）
func _末位加一(版本: String) -> String:
	var 各节: PackedStringArray = 版本.strip_edges().split(".")
	if 各节.is_empty():
		return 版本
	var 末: String = 各节[各节.size() - 1]
	if not 末.is_valid_int():
		return 版本
	各节[各节.size() - 1] = str(末.to_int() + 1)
	return ".".join(各节)
