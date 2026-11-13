class_name GPlayer
extends RefCounted
## 客户端玩家视图（对照客户端 data/Player.h）
## 只保存「界面需要展示」的状态；权威数值由服务端/战斗引擎维护。

## 基础效果（角色面前的一张牌）
class BasicStatus extends RefCounted:
	var type: int = 0
	var card: GCard = null
	## 这张基础效果牌的**实例号**（-1＝没记，退回按牌面）。同牌面可能有多份副本，
	## 点选 / 带走 / 悬停都要按它认人，不然克隆牌会被当成同牌面的另一张。
	var 实例号: int = -1
	func _init(t: int, c: GCard, 实例: int = -1) -> void:
		type = t
		card = c
		实例号 = 实例

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
var no_heal: bool = false      # 本回合无法获得治疗（神威）
## 禁止基础效果生效（结界师【虚空境】）：客户端把面前的基础效果图标置灰
var no_basic: bool = false
var cross_max: int = GConst.CROSS_MAX
var gem: int = 0
var crystal: int = 0
var energy_max: int = GConst.ENERGY_MAX
## 盖牌上限（角色表「指示物」列槽 2 的上限）：查看盖牌时按它摆空槽；0＝这个角色没有盖牌区
var cover_cards_max: int = 0
var color: int = GConst.TEAM_NONE   # 1 红 / 0 蓝 / -1 未分队
var role_id: int = 0
var tap: bool = false               # 横置/锁定
## 梦想剑 4503 当前档位（0=未启用 / 1=无视圣盾 / 2=无法应战 / 3=强制命中）
var dream_tier: int = 0
## 本回合「下一次主动攻击只能攻击这名玩家」（-1＝无限制；0 是合法座位号）：剑之子【剑残影】10804 的回合级标记。
## 服务端在 base_v_attack 里按它校验；客户端据此把其余敌方头像置灰（见 battle_mobile._玩家可选）
var attack_lock: int = -1
## 血色剑灵【血蔷薇庭院】独立状态：状态图标区显示庭院图标，不占横置形态
var xue_qiang_wei: bool = false
## 圣弓专属技正反面：0=【圣煌辉光炮】、1=【圣煌余辉】、2=已移除
var sheng_huang_side: int = 0
## 额外回合的加伤来源技能 / 数值（如剑守誓言 10803）：非 0 时状态区显示对应状态图标。
## 只在「当前这个额外回合属于这名玩家」时有值，额外回合结束服务端清掉。
var extra_turn_cause: int = 0
var extra_turn_bonus: int = 0
## 角色状态标记：技能号列表（与 state_mark_counts 一一对应），客户端按技能号取图标 / 说明 / 计数
var state_marks: Array[int] = []
var state_mark_counts: Array[int] = []
var specials: Array[bool] = [false, false, false, false, false]  # 独有效果 ex_cards
## 与 specials 一一对应：每张专属牌是谁放的（-1＝没记）；【挑衅】靠它只放行放牌者那个头像
var specials_from: Array[int] = [-1, -1, -1, -1, -1]
var basic_status_list: Array[BasicStatus] = []
## 面朝上的盖牌（所有人可见，如结界师【结界】）：牌面 id 列表
var cover_opens: Array[int] = []
## 公开信息：这名玩家手牌里的魔刃/异刃（1005/1006）；头像旁显示状态，所有人可见
var hand_blades: Array[int] = []
## 【律法】标记（星坠女巫）：1=繁星 / 2=影月 / 3=蚀日
var laws: Array[int] = []
## 【Trick or Treat】比分（捣蛋萝莉）：[红队弃牌数, 蓝队弃牌数]；空＝没有这个状态
var trick_score: Array[int] = []
## 面前每一张基础效果「在查看者眼里其实是什么牌」：与 basic_status_list 等长，0＝看不到。
## 目前只有捣蛋萝莉【Surprise!】面朝下放的【Tricky】——只有放牌的人自己拿得到（悬停提示用）
var basic_hidden: Array[int] = []
## 盖牌此刻能不能当手牌用（服务端 BattleRole.盖牌可当手牌()）：
## 精灵射手【精灵祝福形态】、神秘学者【真言术】选言灵之后这类窗口 —— 客户端据此让盖牌区的牌可点
var cover_as_hand: bool = false

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


func add_basic_status(t: int, c: GCard, 实例: int = -1) -> void:
	basic_status_list.append(BasicStatus.new(t, c, 实例))


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
