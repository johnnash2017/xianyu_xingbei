## 提示语表 —— 对应 AGrail.StateHint
## 原实现把 battle 包的 hint 文本用 Newtonsoft.Json 反序列化成
## Dictionary<string, Dictionary<string,string>>；Godot 侧用内建 JSON。
class_name StateHint
extends RefCounted

const HINT_PATH := "res://assets/data/hint.txt"

static var _hint: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(HINT_PATH):
		push_warning("StateHint: 找不到 " + HINT_PATH)
		return
	var text := FileAccess.open(HINT_PATH, FileAccess.READ).get_as_text()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		_hint = parsed
	else:
		push_error("StateHint: hint 表解析失败")

## 对应 C# public static string GetHint(StateEnum state, int additional = 0)
static func get_hint_by_enum(state: int, additional: int = 0) -> String:
	return _lookup(StateEnum.name_of(state), additional)

## 对应 C# public static string GetHint(uint state, int additional = 0)
## state 是技能 ID，表键是技能名
static func get_hint(state: int, additional: int = 0) -> String:
	var skill = Skill.get_skill(state)
	var keyname: String = str(skill.skill_name) if skill != null else str(state)
	return _lookup(keyname, additional)

## 对应 C# public static string GetHint(string keyname, int additional = 0)
static func get_hint_by_name(keyname: String, additional: int = 0) -> String:
	return _lookup(keyname, additional)

static func _lookup(keyname: String, additional: int) -> String:
	_ensure_loaded()
	var key: String = str(additional)
	if _hint.has(keyname) and _hint[keyname] is Dictionary and _hint[keyname].has(key):
		return str(_hint[keyname][key])
	push_error("hint not found: " + keyname + key)
	return "是否响应" + keyname + "?"
