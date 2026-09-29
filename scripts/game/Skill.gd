## 技能数据 —— 对应 AGrail.Skill（从 battle 包的 skillDB 文本资源解析）
class_name Skill
extends RefCounted

## 对应 AGrail.SkillType / SkillProperty / SkillCost 三个枚举
const TYPE_NAMES := ["主动", "响应", "独有技", "法术", "普通", "None"]
const PROPERTY_NAMES := ["无", "幻", "圣", "咏", "技", "血", "None"]
const COST_NAMES := ["None", "Morale", "Gem", "Crystal", "Grail", "Heal"]

const DB_PATH := "res://assets/data/skillDB.txt"

var skill_id: int = 0
var skill_name: String = ""
var skill_type: String = ""
var property: String = ""
var cost: String = ""
var description: String = ""
var children_skill: Array[int] = []

static var _dict: Dictionary = {}
static var _loaded := false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	if not FileAccess.file_exists(DB_PATH):
		push_warning("Skill: 找不到 " + DB_PATH)
		return
	var text := FileAccess.open(DB_PATH, FileAccess.READ).get_as_text()
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "":
			continue
		var cols := line.split("\t")
		if cols.size() < 7:
			continue
		var s := Skill.new()
		s.skill_id = int(cols[0])
		s.skill_name = cols[1]
		s.skill_type = cols[2]
		s.property = cols[3]
		s.cost = cols[4]
		s.description = cols[5]
		for part in cols[6].replace('"', "").split(","):
			var t := part.strip_edges()
			s.children_skill.append(int(t) if t.is_valid_int() else 0)
		_dict[s.skill_id] = s

static func get_skill(skill_id_v: int) -> Skill:
	_ensure_loaded()
	return _dict.get(skill_id_v, null)

static func all() -> Dictionary:
	_ensure_loaded()
	return _dict
