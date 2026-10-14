class_name GPlayer
extends RefCounted
## 客户端玩家视图（对照客户端 data/Player.h）
## 只保存「界面需要展示」的状态；权威数值由服务端/战斗引擎维护。

## 基础效果（角色面前的一张牌）
class BasicStatus extends RefCounted:
	var type: int = 0
	var card: GCard = null
	func _init(t: int, c: GCard) -> void:
		type = t
		card = c

## 指示物
class Token extends RefCounted:
	var token_name: String = ""
	var max_num: int = 0
	var num: int = 0
	var type: int = 0
	func _init(n: String, mx: int, n0: int, t: int = 0) -> void:
		token_name = n
		max_num = mx
		num = n0
		type = t

var id: int = 0
var pos: int = 0
var nickname: String = ""
var role_name: String = "角色"
var hand_cards_max: int = GConst.HAND_CARDS_MAX
var hand_cards_num: int = 0
var cross_num: int = 0        # 当前治疗值
var cross_max: int = GConst.CROSS_MAX
var gem: int = 0
var crystal: int = 0
var energy_max: int = GConst.ENERGY_MAX
var color: int = GConst.TEAM_NONE   # 1 红 / 0 蓝 / -1 未分队
var role_id: int = 0
var tap: bool = false               # 横置/锁定
var specials: Array[bool] = [false, false, false, false, false]  # 独有效果 ex_cards
## 与 specials 一一对应：每张专属牌是谁放的（-1＝没记）；【挑衅】靠它只放行放牌者那个头像
var specials_from: Array[int] = [-1, -1, -1, -1, -1]
var basic_status_list: Array[BasicStatus] = []
var tokens: Array = [null, null, null]
var ready: bool = false
var leader: bool = false
var online: bool = true
## 到房主那一跳的往返延迟（毫秒）；未测出时是哨兵值 GConst.PING_未测（0ms 是合法值）
var ping: int = GConst.PING_未测


func _init(pid: int = 0, c: int = GConst.TEAM_NONE, nick: String = "") -> void:
	id = pid
	color = c
	nickname = nick


func set_team(c: int) -> void:
	color = c


func set_nickname(n: String) -> void:
	nickname = n


func set_role(role: int) -> void:
	role_id = role
	role_name = Data.role_name(role)


func set_hand_cards_max(v: int) -> void:
	hand_cards_max = v


func set_cross_num(v: int) -> void:
	cross_num = v


func set_cross_max(v: int) -> void:
	cross_max = v


func set_gem(v: int) -> void:
	gem = v


func set_crystal(v: int) -> void:
	crystal = v


func set_energy_max(v: int) -> void:
	energy_max = v


func set_tap(v: bool) -> void:
	tap = v


func set_special(idx: int, on: bool) -> void:
	if idx >= 0 and idx < GConst.EXCLUSIVE_NUM:
		specials[idx] = on


func get_special(idx: int) -> bool:
	if idx >= 0 and idx < GConst.EXCLUSIVE_NUM:
		return specials[idx]
	return false


func set_special_from(idx: int, from_id: int) -> void:
	if idx >= 0 and idx < GConst.EXCLUSIVE_NUM:
		specials_from[idx] = from_id


## 某张专属牌是谁放的（没挂或没记 → -1）
func get_special_from(idx: int) -> int:
	if idx >= 0 and idx < GConst.EXCLUSIVE_NUM:
		return specials_from[idx]
	return -1


func set_token(idx: int, token) -> void:
	if idx >= 0 and idx < 3:
		tokens[idx] = token


func get_token(idx: int) -> Variant:
	if idx >= 0 and idx < 3:
		return tokens[idx]
	return null


func add_basic_status(t: int, c: GCard) -> void:
	basic_status_list.append(BasicStatus.new(t, c))


func remove_basic_status(c: GCard) -> void:
	for i: int in range(basic_status_list.size() - 1, -1, -1):
		if basic_status_list[i].card == c:
			basic_status_list.remove_at(i)
			return


func clean_basic_status() -> void:
	basic_status_list.clear()


## 是否拥有某个基础效果（按该效果牌带的技能号判定）
func has_status_skill(技能号: int) -> bool:
	for s: BasicStatus in basic_status_list:
		if s.card != null and s.card.has_skill_id(技能号):
			return true
	return false


func get_energy() -> int:
	return gem + crystal
