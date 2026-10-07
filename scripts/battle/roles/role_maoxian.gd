extends BattleRole
## 冒险家（roleID 12）—— 移植自服务端 role/MaoXian.cpp
## 技能：欺诈（响应/攻击技能 1201：弃 2~3 张同系牌，视为一次主动攻击，虚牌系别由此决定）、
##       冒险者天堂（1202：提炼后、星石还没移动时询问是否改给一名队友；不占技能栏）、
##       偷天换日（必杀法术技能 1203：将对方战绩区 1 宝石转移到我方，额外 +1 攻击或法术行动）、
##       特殊加工（必杀法术技能 1204：我方水晶全部替换为宝石，额外 +1 攻击或法术行动）
## 被动：强运（每发动欺诈 +1 水晶）、地下法则（购买时改为战绩区 +2 宝石）

const QI_ZHA: int = 1201                     # 欺诈（攻击技能）
const MAO_XIAN_ZHE_TIAN_TANG: int = 1202     # 冒险者天堂（提炼时的询问号）
const TOU_TIAN_HUAN_RI: int = 1203           # 偷天换日（法术技能）
const TE_SHU_JIA_GONG: int = 1204            # 特殊加工（法术技能）

## 偷天换日 / 特殊加工 的回合限定标记（两者互斥）
var used_TouTianHuanRi: bool = false


func p_before_turn_begin(_ctx: Dictionary) -> int:
	used_TouTianHuanRi = false
	return SUCCESS


func available_skills() -> Array:
	var out: Array = []
	# 欺诈：先在二级技能栏里选要用哪张虚牌（「先弹选项」，选完才让选牌 / 选目标），
	# 再弃 2~3 张同系牌 + 指定敌方目标，最后点一次「确定」提交（不再中途问第二次）。
	# 手里至少要有一对同系牌才放行（对照原客户端 MaoXian::normal 的两两比较）
	if _has_same_element_pair():
		out.append({"type": GConst.ActionType.AttackSkill, "id": QI_ZHA, "need_card": 2, "card_max": 3, "need_target": 1,
			"targets": enemy_ids(), "card_rule": "same", "arg_choices": _qi_zha_options()})
	if player.get_energy() > 0 and not used_TouTianHuanRi:
		if engine.team_gem[1 - player.color] >= 1:
			out.append({"type": GConst.ActionType.MagicSkill, "id": TOU_TIAN_HUAN_RI, "need_card": 0, "need_target": 0})
		out.append({"type": GConst.ActionType.MagicSkill, "id": TE_SHU_JIA_GONG, "need_card": 0, "need_target": 0})
	return out


## 手里是否有至少一对同系牌（欺诈的发动前提，对照原客户端 MaoXian::normal 的两两比较）
func _has_same_element_pair() -> bool:
	var 已有系: Dictionary[int, bool] = {}
	for cid: int in player.hand_cards:
		var c: GCard = Data.get_card(cid)
		if c == null:
			continue
		var e: int = c.element_enum()
		if 已有系.has(e):
			return true
		已有系[e] = true
	return false


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
# 虚牌（改成哪种系别的攻击）由客户端二级技能栏的选项随行动一起提交（args[0] = 虚牌 id）
# ============================================================
func v_attack_skill(action: Dictionary) -> int:
	if int(action.get("src_id", -1)) != player.id:
		return GConst.GE_INVALID_PLAYERID
	if int(action.get("action_id", 0)) != QI_ZHA:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	if cards.size() != 2 and cards.size() != 3:
		return GConst.GE_INVALID_CARDID
	# 虚牌必须是这张数下真能选的（【暗灭】要 3 张同系）
	var args: Array = action.get("args", [])
	if args.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	if not _qi_zha_virtual_cards(cards.size()).has(int(args[0])):
		return GConst.GE_INVALID_ACTION
	for c: Variant in cards:
		if not player.has_hand_card(int(c)):
			return GConst.GE_HANDCARD_NOT_FOUND
	var dsts: Array = action.get("dst_ids", [])
	if dsts.is_empty():
		return GConst.GE_INVALID_ARGUMENT
	var dst: BattlePlayer = engine.p(int(dsts[0]))
	if dst == null:
		return GConst.GE_INVALID_PLAYERID
	if dst.color == player.color:
		return GConst.GE_INVALID_PLAYERID
	# 服务端 MaoXian::v_attack_skill 会调 v_attack：补上通用攻击限制
	# （面前有【挑衅】时目标只能是勇者；目标角色可拒绝被攻击，如暗杀者潜行中）
	if player.check_exclusive_effect(GConst.Exclusive.TiaoXin) and dst.role_id != 21:
		return GConst.GE_INVALID_PLAYERID
	if dst.v_attacked() != GConst.GE_SUCCESS:
		return GConst.GE_INVALID_PLAYERID
	return GConst.GE_SUCCESS


## 欺诈：虚牌由客户端二级技能栏的选项一并提交（args[0]），这里直接按它结算，不再中途问一次。
## 万一收到非法值（正常不该发生）：有暗灭选暗灭、没暗灭随机选。
func p_attack_skill(action: Dictionary) -> int:
	if int(action.get("action_id", 0)) != QI_ZHA:
		return GConst.GE_INVALID_ACTION
	var cards: Array = action.get("card_ids", [])
	var args: Array = action.get("args", [])
	var 合法: Array[int] = _qi_zha_virtual_cards(cards.size())
	var virtual_card: int = int(args[0]) if not args.is_empty() else -1
	if not 合法.has(virtual_card):
		virtual_card = _qi_zha_default_virtual(合法)
	return _qi_zha(action, virtual_card)


func _qi_zha(action: Dictionary, virtual_card: int) -> int:
	var cards: Array = action.get("card_ids", [])
	var dsts: Array = action.get("dst_ids", [])
	var dst_id: int = int(dsts[0])
	notice_skill(QI_ZHA, [dst_id])
	# 强运：+1 水晶
	player.set_crystal(player.crystal + 1)
	# 展示并弃掉所选牌
	engine.broadcast(GConst.Msg.Card, {
		"type": GConst.CardMsgType.Show, "src_id": player.id, "dst_id": player.id,
		"card_ids": cards, "is_real": true,
	})
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
	engine.take_from_hand(player.id, cards, true)
	engine.to_discard(cards)
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
# 冒险者天堂：提炼时把星石改给队友（校验空位按队友算）
# ============================================================
## dst_id >= 0＝【冒险者天堂】把提炼出的星石给该队友：按队友的剩余空位校验；
## dst_id < 0＝常规提炼给自己，退回通用校验
func v_extract(args: Array, team_gem: int, team_crystal: int, dst_id: int) -> int:
	if dst_id < 0:
		return V_NOT_OVERRIDE
	if args.size() < 2:
		return GConst.GE_INVALID_ARGUMENT
	var 目标: BattlePlayer = engine.p(dst_id)
	if 目标 == null or 目标.color != player.color or 目标.id == player.id:
		return GConst.GE_INVALID_PLAYERID
	var g: int = int(args[0])
	var c: int = int(args[1])
	if g > team_gem or c > team_crystal or g + c > 目标.energy_max - 目标.get_energy():
		return GConst.GE_INVALID_ACTION
	return GConst.GE_SUCCESS


## 提炼改给队友后：广播【冒险者天堂】的发动通知（对照服务端 MaoXian::p_special_skill 的 noticeSkill）
func p_extract_to(ctx: Dictionary) -> int:
	if int(ctx.get("player", -1)) != player.id:
		return SUCCESS
	notice_skill(MAO_XIAN_ZHE_TIAN_TANG, [int(ctx.get("dst", -1))])
	return SUCCESS


# ============================================================
# 工具
# ============================================================
## 欺诈虚牌：各系别对应的一张【圣】命格攻击牌（顺序照原客户端：风 / 水 / 火 / 地 / 雷 / 暗灭）
const QI_ZHA_CARDS: Array[int] = [66, 133, 87, 45, 110, 39]
## 欺诈虚牌里的【暗灭】：2 张同系不能视为暗系，不放进可选
const QI_ZHA_AN_MIE: int = 39


## 欺诈可选的虚牌 id：风 / 水 / 火 / 地 / 雷；3 张同系时再补【暗灭】
func _qi_zha_virtual_cards(同系数: int) -> Array[int]:
	var out: Array[int] = []
	for cid: int in QI_ZHA_CARDS:
		if cid == QI_ZHA_AN_MIE and 同系数 < 3:
			continue
		out.append(cid)
	return out


## 欺诈的虚牌选项（二级技能栏里先选，选完才让选牌 / 选目标）：
## value / args = 虚牌 id，label = 牌名；【暗灭】要 3 张同系，故那一项自带 need_card 3 ——
## 客户端据此要求选满 3 张才让点「确定」，与服务端的 v_attack_skill 校验一致
func _qi_zha_options() -> Array:
	var out: Array = []
	for cid: int in QI_ZHA_CARDS:
		var 项: Dictionary = {"text": Data.get_card(cid).card_name, "args": [cid]}
		if cid == QI_ZHA_AN_MIE:
			项["need_card"] = 3
		out.append(项)
	return out


## 欺诈弹窗超时（或收到非法值）的默认虚牌：有暗灭选暗灭，没暗灭随机选
func _qi_zha_default_virtual(合法: Array[int]) -> int:
	if 合法.has(QI_ZHA_AN_MIE):
		return QI_ZHA_AN_MIE
	return 合法[randi_range(0, 合法.size() - 1)]


## 消耗 1 点个人能量（优先扣水晶，与服务端一致）
func _consume_one_energy() -> void:
	if player.crystal > 0:
		player.set_crystal(player.crystal - 1)
	else:
		player.set_gem(player.gem - 1)
