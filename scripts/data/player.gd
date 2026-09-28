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
var basic_status_list: Array[BasicStatus] = []
var tokens: Array = [null, null, null]
var ready: bool = false
var leader: bool = false
var online: bool = true
var face_source: String = ""        # 角色立绘路径
var tap_source: String = ""         # 形态图标路径


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
	face_source = "res://资源/角色/%d.png" % role
	if not ResourceLoader.exists(face_source):
		face_source = ""


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


## 是否拥有某个基础效果（按特技名判定）
func has_status_name(tag: String) -> bool:
	for s: BasicStatus in basic_status_list:
		if s.card != null and s.card.has_speciality_name(tag):
			return true
	return false


func get_energy() -> int:
	return gem + crystal
