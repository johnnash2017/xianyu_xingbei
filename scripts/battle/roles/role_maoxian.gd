extends BattleRole
## 冒险家（roleID 12）—— 移植自服务端 role/MaoXian.cpp
## 技能：欺诈（响应/攻击技能 1201：弃 2~3 张同系牌，视为一次主动攻击，虚牌系别由此决定）、
##       冒险者天堂（法术技能 1202：将提炼出的宝石/水晶交给任意一名队友）、
##       偷天换日（必杀法术技能 1203：将对方战绩区 1 宝石转移到我方，额外 +1 攻击或法术行动）、
##       特殊加工（必杀法术技能 1204：我方水晶全部替换为宝石，额外 +1 攻击或法术行动）
## 被动：强运（每发动欺诈 +1 水晶）、地下法则（购买时改为战绩区 +2 宝石）

const QI_ZHA: int = 1201                     # 欺诈（攻击技能）
const MAO_XIAN_ZHE_TIAN_TANG: int = 1202     # 冒险者天堂（特殊技能）
const TOU_TIAN_HUAN_RI: int = 1203           # 偷天换日（法术技能）
const TE_SHU_JIA_GONG: int = 1204            # 特殊加工（法术技能）

## 偷天换日 / 特殊加工 的回合限定标记（两者互斥）
var used_TouTianHuanRi: bool = false

## 欺诈的虚牌 id（原客户端固定这 6 张攻击牌，顺序照抄）
const QI_ZHA_VIRTUAL_CARDS: Array[int] = [66, 133, 87, 45, 110, 39]


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_TouTianHuanRi = false
	return SUCCESS


func available_skills() -> Array:
	var out: Array = []
	# 欺诈：弃 2~3 张同系牌 + 指定敌方目标，虚牌（args[0]）由参数按钮选择
	if player.hand_cards.size() >= 2:
		out.append({"type": GConst.ActionType.AttackSkill, "id": QI_ZHA, "need_card": 2, "card_max": 3, "need_target": 1,
			"targets": enemy_ids(), "arg_choices": _qi_zha_choices(), "card_rule": "same"})
	if player.get_energy() > 0 and not used_TouTianHuanRi:
		if engine.team_gem[1 - player.color] >= 1:
			out.append({"type": GConst.ActionType.MagicSkill, "id": TOU_TIAN_HUAN_RI, "need_card": 0, "need_target": 0})
		out.append({"type": GConst.ActionType.MagicSkill, "id": TE_SHU_JIA_GONG, "need_card": 0, "need_target": 0})
	# 冒险者天堂：把战绩区能量交给队友（目标限队友，给出量由参数按钮选择）
	var 队友: Array[int] = ally_ids()
	if engine.team_gem[player.color] + engine.team_crystal[player.color] > 0 and not 队友.is_empty():
		out.append({"type": GConst.ActionType.SpecialSkill, "id": MAO_XIAN_ZHE_TIAN_TANG, "need_card": 0, "need_target": 1,
			"targets": 队友, "arg_choices": _tian_tang_choices()})
	return out


# ============================================================
# 地下法则：购买
# ============================================================
func v_buy(args: Array) -> int:
	if player.hand_cards.size() + 3 > player.hand_cards_max:
		return GConst.GE_INVALID_ACTION
	if args.size() < 2:
		return GConst.GE_INVALID_ARGUMENT
	var gem: int = int(args[0])
	var crystal: int = int(args[1])
	if gem < 3 and crystal == 0:
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


# ============================================================
# 欺诈（攻击技能）：弃 2~3 张同系牌，虚牌视为一次主动攻击
# ============================================================
func v_attack_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != QI_ZHA:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 2 and cards.size() != 3:
		return GConst.GE_INVALID_CARDID
	for c: Variant in cards:
		if not player.has_hand_card(int(c)):
			return GConst.GE_HANDCARD_NOT_FOUND
	var args: Array = action.get("args", [])
	var dsts: Array = action.get("dst_ids", [])
	if args.is_empty() or dsts.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	var virtual_card: int = int(args[0])
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null:
		return GConst.GE_INVALID_PLAYERID
	if dst.color == player.color:
		return GConst.GE_INVALID_PLAYERID
	var card: GCard = Data.get_card(virtual_card)
	if card == null or not card.is_attack():
		return GConst.GE_INVALID_CARDID
	# 服务端 MaoXian::v_attack_skill 会调 v_attack：补上通用攻击限制
	# （面前有【挑衅】时目标只能是勇者；目标角色可拒绝被攻击，如暗杀者潜行中）
	if player.check_exclusive_effect(GConst.Exclusive.TiaoXin) and dst.role_id != 21:
		return GConst.GE_INVALID_PLAYERID
	if dst.v_attacked() != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


func p_attack_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != QI_ZHA:
		return GConst.GE_INVALID_ACTION
	return _qi_zha(action)


func _qi_zha(action: Dictionary) -> int:
	var cards: Array = action.get("card_ids", [])
	var args: Array = action.get("args", [])
	var dsts: Array = action.get("dst_ids", [])
	var virtual_card: int = int(args[0])
	var dst_id: int = int(dsts[0])
	notice_skill(QI_ZHA, [dst_id])
	# 强运：+1 水晶
	player.set_crystal(player.crystal + 1)
	# 展示并弃掉所选牌
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
	engine.take_from_hand(player.id, cards)
	engine.to_discard(cards)
	# 虚牌视为一次主动攻击（非真实牌，不移动）
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Use, "src_id": player.id, "dst_id": dst_id,
		"card_ids": [virtual_card], "is_real": false,
	})
	engine._broadcast_game()
	var harm: Dictionary = {
		"src": player.id, "dst": dst_id, "point": 2, "cause": GConst.CAUSE_ATTACK,
		"type": GConst.HarmType.Attack, "card_id": virtual_card, "is_active": true,
	}
	engine.push(BattleEngine.SAttackCard.new(player.id, dst_id, virtual_card, harm))
	return URGENT


# ============================================================
# 偷天换日 / 特殊加工（必杀法术技能）
# ============================================================
func v_magic_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if used_TouTianHuanRi:
		return GConst.GE_INVALID_ACTION
	var aid: int = int(action.get("action_id", 0))
	if aid == TOU_TIAN_HUAN_RI:
		if player.get_energy() <= 0 or engine.team_gem[1 - player.color] < 1:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	if aid == TE_SHU_JIA_GONG:
		if player.get_energy() <= 0:
			return GConst.GE_INVALID_ACTION
		return GConst.GE_SUCCESS
	return GConst.GE_INVALID_ACTION


func p_magic_skill(action: Dictionary) -> int:
	match int(action.get("action_id", 0)):
		TOU_TIAN_HUAN_RI:
			return _tou_tian_huan_ri()
		TE_SHU_JIA_GONG:
			return _te_shu_jia_gong()
	return GConst.GE_INVALID_ACTION


## 偷天换日：消耗 1 能量，将对方战绩区 1 宝石转移到我方，额外 +1 攻击/法术行动
func _tou_tian_huan_ri() -> int:
	notice_skill(TOU_TIAN_HUAN_RI, [player.id])
	_consume_one_energy()
	var enemy: int = 1 - player.color
	engine.set_team_gem(enemy, engine.team_gem[enemy] - 1)
	engine.set_team_gem(player.color, engine.team_gem[player.color] + 1)
	player.add_action(GConst.ActionType.AttackMagic, TOU_TIAN_HUAN_RI, true)
	used_TouTianHuanRi = true
	engine._broadcast_game()
	return SUCCESS


## 特殊加工：消耗 1 能量，我方水晶全部替换为宝石，额外 +1 攻击/法术行动
func _te_shu_jia_gong() -> int:
	notice_skill(TE_SHU_JIA_GONG, [player.id])
	_consume_one_energy()
	var crystal_have: int = engine.team_crystal[player.color]
	engine.set_team_crystal(player.color, 0)
	engine.set_team_gem(player.color, engine.team_gem[player.color] + crystal_have)
	player.add_action(GConst.ActionType.AttackMagic, TE_SHU_JIA_GONG, true)
	used_TouTianHuanRi = true
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 冒险者天堂（特殊技能）：将战绩区能量交给队友
# ============================================================
func v_special_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != MAO_XIAN_ZHE_TIAN_TANG:
		return GConst.GE_INVALID_ACTION
	var args: Array = action.get("args", [])
	var dsts: Array = action.get("dst_ids", [])
	if args.size() < 2 or dsts.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null or dst.color != player.color:
		return GConst.GE_INVALID_PLAYERID
	var gem: int = int(args[0])
	var crystal: int = int(args[1])
	if gem > engine.team_gem[player.color] or crystal > engine.team_crystal[player.color]:
		return GConst.GE_INVALID_ACTION
	if gem + crystal + dst.get_energy() > dst.energy_max:
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


func p_special_skill(action: Dictionary) -> int:
	var args: Array = action.get("args", [])
	var dsts: Array = action.get("dst_ids", [])
	var gem: int = int(args[0])
	var crystal: int = int(args[1])
	var dst_id: int = int(dsts[0])
	notice_skill(MAO_XIAN_ZHE_TIAN_TANG, [dst_id])
	var dst: BattlePlayer = engine.p(dst_id)
	if dst != null:
		if crystal > 0:
			dst.set_crystal(dst.crystal + crystal)
		if gem > 0:
			dst.set_gem(dst.gem + gem)
	engine.set_team_gem(player.color, engine.team_gem[player.color] - gem)
	engine.set_team_crystal(player.color, engine.team_crystal[player.color] - crystal)
	engine._broadcast_game()
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 欺诈的参数选项：虚牌（攻击牌）决定本次视为哪种攻击（服务端校验 args[0] 为攻击牌）
func _qi_zha_choices() -> Array:
	var out: Array = []
	for cid: int in QI_ZHA_VIRTUAL_CARDS:
		out.append({"text": Data.get_card(cid).card_name, "args": [cid], "need_card": 2, "need_target": 1})
	return out


## 冒险者天堂的参数选项：把战绩区能量交给队友。
## 组合照抄原客户端（最多 5 项：两个宝石 / 两个水晶 / 一宝石一水晶 / 一个宝石 / 一个水晶），
## 每项只让「还放得下这么多能量」的队友可点（v_special_skill：gem + crystal + dst 现有能量 > 上限即拒）
func _tian_tang_choices() -> Array:
	var out: Array = []
	var 宝石数: int = engine.team_gem[player.color]
	var 水晶数: int = engine.team_crystal[player.color]
	if 宝石数 >= 2:
		out.append(_tian_tang_choice(2, 0, 2))
	if 水晶数 >= 2:
		out.append(_tian_tang_choice(0, 2, 2))
	if 宝石数 >= 1 and 水晶数 >= 1:
		out.append(_tian_tang_choice(1, 1, 2))
	if 宝石数 >= 1:
		out.append(_tian_tang_choice(1, 0, 1))
	if 水晶数 >= 1:
		out.append(_tian_tang_choice(0, 1, 1))
	return out


## 一条「冒险者天堂」选项：args = [宝石, 水晶]，目标限定为能给得起的队友
func _tian_tang_choice(宝石: int, 水晶: int, 需要容量: int) -> Dictionary:
	return {
		"text": "我方 -%d 宝石 -%d 水晶，队友 +%d 宝石 +%d 水晶" % [宝石, 水晶, 宝石, 水晶],
		"args": [宝石, 水晶], "need_target": 1,
		"targets": player_ids_where(func(p: BattlePlayer) -> bool:
			return p.color == player.color and p.energy_max - p.get_energy() >= 需要容量),
	}


## 消耗 1 点个人能量（优先扣水晶，与服务端一致）
func _consume_one_energy() -> void:
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
