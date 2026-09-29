## 通用工具 —— 对应 AGrail.Util（C# 里是静态类，Godot 里用 class_name 静态方法）
class_name Util
extends RefCounted

## 对应 Team 枚举（C# AGrail.Team）
enum Team { Blue, Red }

## 整数除法。GDScript 对两个 int 用 `/` 会报 INTEGER_DIVISION 警告（小数部分被丢掉），
## 而本工程这些地方要的正是 C# 那种整数除法语义（技能 / 卡牌 id 的位段提取，例如 bb/10 取技能号）。
## 统一走这里：先按浮点除再取整，结果与整数除法完全一致（都是向零截断），且不触发警告。
static func idiv(a: int, b: int) -> int:
	return int(a / float(b))

static func get_other_team(team: int) -> int:
	return Team.Blue if team != Team.Blue else Team.Red

## 手牌里是否有 num 张满足「拥有指定技能」的牌
static func has_card_by_skill(skill_id: int, hands: Array, num: int = 1) -> bool:
	var n := 0
	for h in hands:
		var c := Card.get_card(int(h))
		if c != null and c.has_skill(Skill.get_skill(skill_id).skill_name if Skill.get_skill(skill_id) else ""):
			n += 1
	return n >= num

## 手牌里是否有 num 张指定属性的牌
static func has_card_by_element(element: int, hands: Array, num: int = 1) -> bool:
	var n := 0
	for h in hands:
		var c := Card.get_card(int(h))
		if c != null and c.element == element:
			n += 1
	return n >= num

## 手牌里是否有 num 张指定类型的牌
static func has_card_by_type(ctype: int, hands: Array, num: int = 1) -> bool:
	var n := 0
	for h in hands:
		var c := Card.get_card(int(h))
		if c != null and c.type == ctype:
			n += 1
	return n >= num

## 对应 C# HasCard(string condition, hands, num)
## "same"  = 同属性牌最多的一种达到 num 张
## "differ"= 不同属性数达到 num 种
static func has_card_condition(condition: String, hands: Array, num: int = 2) -> bool:
	var elements := [0, 0, 0, 0, 0, 0, 0]      # wind..darkness
	for h in hands:
		var c := Card.get_card(int(h))
		if c == null:
			continue
		var e := c.element
		if e != 0 and e - 1 < elements.size():
			elements[e - 1] += 1
	var best := 0
	match condition:
		"same":
			best = elements.max()
		"differ":
			for v in elements:
				if v != 0:
					best += 1
	return best >= num
