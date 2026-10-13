@tool
class_name VersionBump
extends RefCounted
## 版本号读写：唯一来源是 project.godot 的 application/config/version。
## 登录界面（enter.gd）、SteamNet 的大厅隔离标记都从 Cfg.游戏版本() 读它；
## 本类只负责「末位 +1」并落盘，供手动菜单与导出插件共用。

const 版本设置键: String = "application/config/version"


## 读当前版本号（读不到就用 0.0.0）
static func 当前版本() -> String:
	return str(ProjectSettings.get_setting(版本设置键, "0.0.0"))


## 末位 +1 并写回 project.godot；成功返回新版本号，末位不是数字则返回空串（未改动）
static func 加一() -> String:
	var 旧: String = 当前版本()
	var 新: String = 末位加一(旧)
	if 新 == 旧:
		return ""
	ProjectSettings.set_setting(版本设置键, 新)
	ProjectSettings.save()
	return 新


## 把版本号最后一节加一：1.0.0 → 1.0.1；末位不是数字则原样返回（由调用方判断未改动）
static func 末位加一(版本: String) -> String:
	var 各节: PackedStringArray = 版本.strip_edges().split(".")
	if 各节.is_empty():
		return 版本
	var 末: String = 各节[各节.size() - 1]
	if not 末.is_valid_int():
		return 版本
	各节[各节.size() - 1] = str(末.to_int() + 1)
	return ".".join(各节)
