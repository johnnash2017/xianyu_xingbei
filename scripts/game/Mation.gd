## 招式（Mation）数据 —— 对应 AGrail.Mation
## 原实现从 battle 包的 MationDB 文本资源解析（制表符分隔，字段：ID/名称/标签/描述行…），
## 查表键是 `角色ID * 100 + n`（n = 0..9）。
##
## ⚠️ 数据缺陷说明（已在最终报告中记录，不是移植错误）：
## APK 里 battle 包的 MationDB 是 **UTF-16LE（带 BOM）** 文本，但 AssetBundle 内每个 UTF-16
## code unit 的高字节已经被破坏（例如 U+51FB「击」变成 U+1298，高字节从 0x51 变成 0x12），
## 原始字节见 `_re/textassets/_probe_MationDB.bin`。因此**中文招式名/描述无法还原**；
## 表结构（制表符列、行数 228、ID 号段）是完整的。
## 本加载器按 UTF-16LE 正确解码，保证 ID / 列数 / 描述拼接逻辑与 C# 一致。
class_name Mation
extends RefCounted

const DB_PATH := "res://assets/data/MationDB.txt"

var MationID: int = 0
var MationName: String = ""
var MationTag: String = ""
var MationDesc: String = ""

static var _dict: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	if not FileAccess.file_exists(DB_PATH):
		push_warning("Mation: 找不到 " + DB_PATH)
		return
	var text := _decode(FileAccess.get_file_as_bytes(DB_PATH))
	if text == "":
		push_warning("Mation: 数据表为空 " + DB_PATH)
		return
	_loaded = true
	for raw_line in text.replace("\r", "").split("\n"):
		var line := raw_line.strip_edges()
		if line == "":
			continue
		var cols := line.split("\t")
		if cols.size() < 4:
			continue
		var m := Mation.new()
		## 对应 C# `uint.Parse(array2[0])`
		var id_txt := cols[0].lstrip("\ufeff").strip_edges()
		m.MationID = int(id_txt) if id_txt.is_valid_int() else 0
		m.MationName = cols[1]
		m.MationTag = cols[2]
		var desc := ""
		for i in range(3, cols.size()):
			if cols[i] != "":
				desc += cols[i] + "\n"
		m.MationDesc = desc
		_dict[m.MationID] = m

## 按字节特征区分 UTF-16(LE/BE) / UTF-8
static func _decode(raw: PackedByteArray) -> String:
	if raw.size() >= 2:
		if raw[0] == 0xFF and raw[1] == 0xFE:
			return _utf16_to_string(raw, 2, true)
		if raw[0] == 0xFE and raw[1] == 0xFF:
			return _utf16_to_string(raw, 2, false)
	if _has_nul(raw):
		# 无 BOM 的 UTF-16LE：ASCII 字符后跟一个 00
		return _utf16_to_string(raw, 0, true)
	return raw.get_string_from_utf8()

static func _has_nul(raw: PackedByteArray) -> bool:
	var n: int = mini(raw.size(), 64)
	for i in range(n):
		if raw[i] == 0:
			return true
	return false

## 手写 UTF-16 解码：Godot 的 PackedByteArray.get_string_from_utf16() 对这份导出文本
## 会在中途停住，所以自己按 code unit 解。
static func _utf16_to_string(raw: PackedByteArray, start: int, little_endian: bool) -> String:
	var out := ""
	var i: int = start
	while i + 1 < raw.size():
		var u: int = (raw[i] | (raw[i + 1] << 8)) if little_endian else ((raw[i] << 8) | raw[i + 1])
		i += 2
		if u == 0:
			continue
		if u >= 0xD800 and u <= 0xDBFF and i + 1 < raw.size():
			var lo: int = (raw[i] | (raw[i + 1] << 8)) if little_endian else ((raw[i] << 8) | raw[i + 1])
			if lo >= 0xDC00 and lo <= 0xDFFF:
				i += 2
				u = 0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00)
		out += String.chr(u)
	return out

## 对应 C# public static Dictionary<uint, Mation> GetMation(uint RID)
## 取该角色 ID*100 + 0..9 的招式。
static func get_mation(rid: int) -> Dictionary:
	_ensure_loaded()
	var out: Dictionary = {}
	for num in range(0, 10):
		var key: int = rid * 100 + num
		if _dict.has(key):
			out[key] = _dict[key]
	return out

static func all() -> Dictionary:
	_ensure_loaded()
	return _dict

## 兜底查询：原数据里部分角色的招式号段并不严格等于 RID*100（例如 101/102/103 属于 RID=1），
## 需要「取该角色全部招式」的 UI 用这个。
static func get_mation_loose(rid: int) -> Dictionary:
	_ensure_loaded()
	var out: Dictionary = {}
	for key in _dict.keys():
		var k: int = int(key)
		if k > rid * 100 and k < rid * 100 + 100:
			out[k] = _dict[key]
	return out
